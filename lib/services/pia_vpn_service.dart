import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service to interact with the Private Internet Access (PIA) VPN CLI (piactl.exe)
class PiaVpnService {
  final String _piactlPath = r'C:\Program Files\Private Internet Access\piactl.exe';

  /// Check if the PIA VPN client is installed on the system
  Future<bool> isInstalled() async {
    if (!Platform.isWindows) return false;
    return File(_piactlPath).exists();
  }

  /// Connect to the VPN. If region is 'custom', uses the provided OVPN file path.
  Future<void> connect({String region = 'canada', String? customPath}) async {
    if (!Platform.isWindows) return;

    if (region == 'custom' && customPath != null) {
      debugPrint('[Vpn] Connecting via custom OVPN profile: $customPath');
      try {
        // Try to find openvpn.exe
        final openVpnPaths = [
          r'C:\Program Files\OpenVPN\bin\openvpn.exe',
          r'C:\Program Files (x86)\OpenVPN\bin\openvpn.exe',
        ];
        String? openVpnExe;
        for (final p in openVpnPaths) {
          if (await File(p).exists()) {
            openVpnExe = p;
            break;
          }
        }
        
        if (openVpnExe == null) {
          debugPrint('[Vpn] openvpn.exe not found. Ensure OpenVPN is installed.');
          return;
        }

        // Start openvpn in background
        await Process.start(openVpnExe, ['--config', customPath], runInShell: true);
      } catch (e) {
        debugPrint('[Vpn] Error starting OpenVPN: $e');
      }
      return;
    }

    if (!await isInstalled()) {
      debugPrint('[PiaVpn] piactl.exe not found at $_piactlPath');
      return;
    }

    try {
      debugPrint('[PiaVpn] Setting region to $region...');
      await Process.run(_piactlPath, ['set', 'region', region]);
      
      debugPrint('[PiaVpn] Connecting...');
      await Process.run(_piactlPath, ['connect']);
    } catch (e) {
      debugPrint('[PiaVpn] Error during connection: $e');
    }
  }

  /// Returns the current PIA connection state string, e.g. "Connected", "Disconnected".
  Future<String> getConnectionState() async {
    if (!Platform.isWindows) return 'Unavailable';
    if (!await isInstalled()) return 'Not installed';
    try {
      final result = await Process.run(_piactlPath, ['get', 'connectionstate'],
          runInShell: true);
      return (result.stdout as String).trim();
    } catch (_) {
      return 'Unknown';
    }
  }

  /// Returns the current VPN IP assigned by PIA, or null if not connected.
  Future<String?> getVpnIp() async {
    if (!Platform.isWindows) return null;
    if (!await isInstalled()) return null;
    try {
      final result = await Process.run(_piactlPath, ['get', 'vpnip'],
          runInShell: true);
      final ip = (result.stdout as String).trim();
      return ip.isNotEmpty ? ip : null;
    } catch (_) {
      return null;
    }
  }

  /// Disconnect from the VPN
  Future<void> disconnect() async {
    if (!Platform.isWindows) return;
    if (!await isInstalled()) return;

    try {
      debugPrint('[PiaVpn] Disconnecting...');
      await Process.run(_piactlPath, ['disconnect']);
    } catch (e) {
      debugPrint('[PiaVpn] Error during disconnection: $e');
    }
  }
}
