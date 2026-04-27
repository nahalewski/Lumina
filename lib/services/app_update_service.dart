import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  final String version;
  final int build;
  final String releaseNotes;
  final int fileSize;

  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.releaseNotes,
    required this.fileSize,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        version: json['version'] as String? ?? '',
        build: json['build'] as int? ?? 0,
        releaseNotes: json['releaseNotes'] as String? ?? '',
        fileSize: json['size'] as int? ?? 0,
      );

  String get fileSizeLabel {
    if (fileSize == 0) return '';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class AppUpdateService {
  static const MethodChannel _channel = MethodChannel('lumina/app_update');
  static const String _checkPath = '/api/update/check';
  static const String _downloadPath = '/api/update/download';

  /// Returns [AppUpdateInfo] if the server has a newer build than installed.
  /// Returns null if already up-to-date or the server has no APK staged.
  Future<AppUpdateInfo?> checkForUpdate(String serverUrl, String token) async {
    try {
      final uri = Uri.parse('${serverUrl.trimRight()}$_checkPath');
      final response = await http.get(
        uri,
        headers: {'x-lumina-token': token},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data.containsKey('error')) return null;

      final info = AppUpdateInfo.fromJson(data);
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      if (info.build > currentBuild) return info;
    } catch (e) {
      debugPrint('[AppUpdate] Check failed: $e');
    }
    return null;
  }

  /// Downloads the APK and returns the local [File].
  /// [onProgress] receives values 0.0–1.0 during download.
  Future<File?> downloadApk(
    String serverUrl,
    String token, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final uri = Uri.parse('${serverUrl.trimRight()}$_downloadPath');
      final request = http.Request('GET', uri)
        ..headers['x-lumina-token'] = token;

      final response =
          await request.send().timeout(const Duration(minutes: 15));
      if (response.statusCode != 200) return null;

      final total = response.contentLength ?? 0;
      var received = 0;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/lumina_update.apk');
      final sink = file.openWrite();

      await response.stream.map((chunk) {
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
        return chunk;
      }).pipe(sink);

      onProgress?.call(1.0);
      return file;
    } catch (e) {
      debugPrint('[AppUpdate] Download failed: $e');
    }
    return null;
  }

  /// Launches the system APK installer for the given file.
  Future<void> installApk(File apkFile) async {
    await _channel.invokeMethod<void>('installApk', apkFile.path);
  }
}
