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

  /// Start the cloudflared tunnel process.
  /// Uses the existing config at ~/.cloudflared/config.yml.
  Future<bool> start() async {
    if (_process != null) {
      _addLog('Already running');
      debugPrint('[CloudflareTunnel] Already running');
      return true;
    }

    try {
      final homeDir = Platform.environment['HOME'] ?? '/Users/bennahalewski';
      final configPath = '$homeDir/.cloudflared/config.yml';

      if (!await File(configPath).exists()) {
        status.value = 'Config not found at $configPath';
        debugPrint('[CloudflareTunnel] Config not found: $configPath');
        return false;
      }

      status.value = 'Starting tunnel...';
      _addLog('Starting cloudflared with config: $configPath');
      debugPrint('[CloudflareTunnel] Starting cloudflared...');

      _process = await Process.start(
        'cloudflared',
        ['tunnel', '--config', configPath, 'run'],
        runInShell: true,
      );

      isRunning.value = true;

      // Listen to stdout for connection info
      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _addLog(line);
        debugPrint('[CloudflareTunnel] $line');

        // Count connections
        if (line.contains('Connected')) {
          connectionCount.value++;
        }
        if (line.contains('Disconnected') || line.contains('disconnected')) {
          connectionCount.value = (connectionCount.value - 1).clamp(0, 100);
        }

        // Update status
        if (line.contains('Registered tunnel connection')) {
          status.value = 'Connected (${connectionCount.value} conns)';
        } else if (line.contains('Starting tunnel')) {
          status.value = 'Connecting...';
        } else if (line.contains('error') || line.contains('Error')) {
          status.value = 'Error: $line';
        }
      });

      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _addLog('stderr: $line');
        debugPrint('[CloudflareTunnel] stderr: $line');
        if (line.contains('error') || line.contains('Error')) {
          status.value = 'Error: $line';
        }
      });

      // Handle process exit
      _process!.exitCode.then((code) {
        debugPrint('[CloudflareTunnel] Process exited with code $code');
        isRunning.value = false;
        status.value = 'Stopped (exit code $code)';
        _process = null;
      });

      return true;
    } catch (e) {
      status.value = 'Failed to start: $e';
      debugPrint('[CloudflareTunnel] Failed to start: $e');
      isRunning.value = false;
      return false;
    }
  }

  /// Stop the cloudflared tunnel process
  Future<void> stop() async {
    if (_process == null) return;

    debugPrint('[CloudflareTunnel] Stopping...');
    status.value = 'Stopping...';

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;

    _process?.kill(ProcessSignal.sigterm);
    await _process?.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      _process?.kill(ProcessSignal.sigkill);
      return -1;
    });

    _process = null;
    isRunning.value = false;
    status.value = 'Stopped';
    connectionCount.value = 0;
    _addLog('Tunnel stopped');
    debugPrint('[CloudflareTunnel] Stopped');
  }

  /// Check if the tunnel is currently running
  bool get isActive => _process != null && isRunning.value;

  /// Get the public URL for the tunnel
  String get publicUrl => 'https://lumina.orosapp.us';

  /// Clean up resources
  void dispose() {
    stop();
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    final logLine = '[$timestamp] $message';
    final currentLogs = List<String>.from(logs.value);
    currentLogs.add(logLine);
    if (currentLogs.length > 50) currentLogs.removeAt(0);
    logs.value = currentLogs;
  }
}
