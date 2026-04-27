import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Manages a Cloudflare Tunnel (cloudflared) process to expose the
/// local Media Server to the internet via lumina.orosapp.us.
///
/// Uses the existing tunnel config at ~/.cloudflared/config.yml
/// which already routes lumina.orosapp.us → localhost:8080.
class CloudflareTunnelService {
  Process? _process;
  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  final ValueNotifier<String> status = ValueNotifier('');
  final ValueNotifier<int> connectionCount = ValueNotifier(0);
  final ValueNotifier<List<String>> logs = ValueNotifier([]);
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  // Reconnect state
  bool _intentionallyStopped = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const List<int> _reconnectDelaysSeconds = [5, 10, 20, 40, 60, 90, 120, 120, 120, 120];

  // Timer-based reconnect (cancellable, unlike Future.delayed)
  Timer? _reconnectTimer;

  // Watchdog: verify process is alive every 30s
  Timer? _watchdogTimer;

  // Stability tracker: reset reconnect counter after 5 min of stable connection
  Timer? _stabilityTimer;
  bool _wasConnected = false;

  /// Start the cloudflared tunnel process.
  Future<bool> start({bool isReconnect = false}) async {
    _intentionallyStopped = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Force kill any existing cloudflared process before starting
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', 'cloudflared-windows-amd64.exe'], runInShell: true);
      } else {
        await Process.run('pkill', ['cloudflared']);
      }
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (_) {}

    if (_process != null) {
      _addLog('Already running — restarting...');
      await _killProcess();
    }

    try {
      final homeDir = Platform.isWindows
          ? Platform.environment['USERPROFILE']
          : Platform.environment['HOME'] ?? '/Users/bennahalewski';

      if (homeDir == null) {
        status.value = 'Home directory not found';
        _addLog('ERROR: Cannot determine home directory');
        return false;
      }

      final configPath = Platform.isWindows
          ? '$homeDir\\.cloudflared\\config.yml'
          : '$homeDir/.cloudflared/config.yml';

      if (!await File(configPath).exists()) {
        status.value = 'Config not found: $configPath';
        _addLog('ERROR: cloudflared config not found at $configPath');
        debugPrint('[CloudflareTunnel] Config not found: $configPath');
        return false;
      }

      final cloudflaredExe = await _findCloudflaredExe();
      if (cloudflaredExe == null) {
        status.value = 'cloudflared not found — install it first';
        _addLog('ERROR: cloudflared executable not found in known locations or PATH');
        return false;
      }

      status.value = 'Starting tunnel...';
      _addLog('Starting cloudflared (exe: $cloudflaredExe)');
      debugPrint('[CloudflareTunnel] Starting cloudflared...');

      _process = await Process.start(
        cloudflaredExe,
        ['tunnel', '--config', configPath, 'run'],
        runInShell: true,
      );

      if (!isReconnect) {
        _reconnectAttempts = 0;
      }

      isRunning.value = true;
      _wasConnected = false;
      _startWatchdog();

      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleLogLine);

      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleStderrLine);

      _process!.exitCode.then(_handleProcessExit);

      return true;
    } catch (e) {
      status.value = 'Failed to start: $e';
      _addLog('ERROR: $e');
      debugPrint('[CloudflareTunnel] Failed to start: $e');
      isRunning.value = false;
      return false;
    }
  }

  void _handleLogLine(String line) {
    if (line.trim().isEmpty) return;
    _addLog(line);

    if (line.contains('Connected')) {
      connectionCount.value++;
    }
    if (line.contains('Disconnected') || line.contains('disconnected')) {
      connectionCount.value = (connectionCount.value - 1).clamp(0, 100);
    }
    _parseStatusFromLine(line);
  }

  void _handleStderrLine(String line) {
    if (line.trim().isEmpty) return;
    _addLog(line);
    debugPrint('[CloudflareTunnel] $line');
    _parseStatusFromLine(line);
  }

  void _parseStatusFromLine(String line) {
    final lower = line.toLowerCase();

    // Connected signals
    if (lower.contains('registered tunnel connection') ||
        (lower.contains('connection') && lower.contains('registered'))) {
      status.value = 'Connected — lumina.orosapp.us';
      connectionCount.value = (connectionCount.value + 1).clamp(0, 100);
      _onConnected();
      return;
    }

    if (lower.contains('connecting') || lower.contains('starting tunnel')) {
      status.value = 'Connecting...';
      return;
    }

    // Only flag real errors: lines that start with ERR or have explicit fatal keywords.
    // Cloudflared uses structured logs like: "ERR Failed to serve tunnel..."
    // Ignore transient messages that contain "error" as part of normal retry output.
    final isFatalError = line.startsWith('ERR ') ||
        lower.contains('failed to serve tunnel') ||
        lower.contains('unable to reach') ||
        lower.contains('authentication failed') ||
        lower.contains('certificate') && lower.contains('expired');

    if (isFatalError) {
      final msg = line.length > 80 ? '${line.substring(0, 80)}…' : line;
      status.value = 'Error: $msg';
    }
  }

  void _onConnected() {
    _stabilityTimer?.cancel();
    _wasConnected = true;
    // After 5 minutes of stable connection, reset reconnect counter
    _stabilityTimer = Timer(const Duration(minutes: 5), () {
      if (!_intentionallyStopped && isRunning.value) {
        _reconnectAttempts = 0;
        _addLog('Connection stable — reconnect counter reset');
      }
    });
  }

  Future<void> _handleProcessExit(int code) async {
    debugPrint('[CloudflareTunnel] Process exited with code $code');
    _addLog('Process exited (code $code)');
    _stopWatchdog();
    _stabilityTimer?.cancel();

    if (isRunning.value) {
      isRunning.value = false;
    }
    _process = null;

    if (_intentionallyStopped) {
      status.value = 'Stopped';
      connectionCount.value = 0;
      return;
    }

    // Unexpected exit — attempt reconnect with backoff
    if (_reconnectAttempts < _maxReconnectAttempts) {
      final delayIdx = _reconnectAttempts.clamp(0, _reconnectDelaysSeconds.length - 1);
      final delaySecs = _reconnectDelaysSeconds[delayIdx];
      _reconnectAttempts++;

      status.value = 'Lost connection — reconnecting in ${delaySecs}s '
          '(attempt $_reconnectAttempts/$_maxReconnectAttempts)';
      _addLog('Unexpected exit (code $code). Reconnecting in ${delaySecs}s...');

      _reconnectTimer = Timer(Duration(seconds: delaySecs), () async {
        if (!_intentionallyStopped) {
          _addLog('Reconnect attempt $_reconnectAttempts...');
          await start(isReconnect: true);
        }
      });
    } else {
      status.value = 'Tunnel stopped after $_maxReconnectAttempts failed reconnects. Toggle to retry.';
      _addLog('Giving up after $_maxReconnectAttempts reconnect attempts');
      connectionCount.value = 0;
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_intentionallyStopped) {
        _watchdogTimer?.cancel();
        return;
      }
      final proc = _process;
      if (proc == null && isRunning.value) {
        // Process handle lost but isRunning still true — force reconnect
        _addLog('Watchdog: process handle lost unexpectedly — triggering reconnect');
        isRunning.value = false;
        _handleProcessExit(-1);
      }
    });
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  Future<String?> _findCloudflaredExe() async {
    if (Platform.isWindows) {
      final candidates = [
        'C:\\cloudflared-windows-amd64.exe',
        'C:\\cloudflared.exe',
        'C:\\Windows\\System32\\cloudflared.exe',
        r'C:\Program Files\cloudflared\cloudflared.exe',
      ];
      for (final p in candidates) {
        if (await File(p).exists()) return p;
      }
      try {
        final result = await Process.run('where', ['cloudflared'], runInShell: true);
        if (result.exitCode == 0) {
          final path = (result.stdout as String).trim().split('\n').first.trim();
          if (path.isNotEmpty) return path;
        }
      } catch (_) {}
      return null;
    } else {
      final candidates = [
        '/usr/local/bin/cloudflared',
        '/usr/bin/cloudflared',
        '/opt/homebrew/bin/cloudflared',
      ];
      for (final p in candidates) {
        if (await File(p).exists()) return p;
      }
      try {
        final result = await Process.run('which', ['cloudflared']);
        if (result.exitCode == 0) {
          final path = (result.stdout as String).trim();
          if (path.isNotEmpty) return path;
        }
      } catch (_) {}
      return null;
    }
  }

  /// Stop the cloudflared tunnel process.
  Future<void> stop() async {
    _intentionallyStopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = _maxReconnectAttempts; // block any in-flight reconnect
    _stopWatchdog();
    _stabilityTimer?.cancel();

    if (_process == null) {
      isRunning.value = false;
      status.value = 'Stopped';
      connectionCount.value = 0;
      return;
    }

    debugPrint('[CloudflareTunnel] Stopping...');
    status.value = 'Stopping...';
    await _killProcess();
    status.value = 'Stopped';
    connectionCount.value = 0;
    _addLog('Tunnel stopped by user');
    debugPrint('[CloudflareTunnel] Stopped');
  }

  Future<void> _killProcess() async {
    final proc = _process;
    _process = null; // clear first so watchdog doesn't trigger
    isRunning.value = false;

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;

    if (proc != null) {
      proc.kill(ProcessSignal.sigterm);
      await proc.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  }

  /// Check if the tunnel is currently running.
  bool get isActive => _process != null && isRunning.value;

  /// Get the public URL for the tunnel.
  String get publicUrl => 'https://lumina.orosapp.us';

  void dispose() {
    _intentionallyStopped = true;
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    _stabilityTimer?.cancel();
    stop();
  }

  void _addLog(String message) {
    final timestamp =
        DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    final logLine = '[$timestamp] $message';
    final currentLogs = List<String>.from(logs.value);
    currentLogs.add(logLine);
    if (currentLogs.length > 200) currentLogs.removeRange(0, currentLogs.length - 200);
    logs.value = currentLogs;
  }
}
