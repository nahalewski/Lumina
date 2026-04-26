import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class YtDlpService {
  Future<String> get _binPath async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/bin';
  }

  Future<String> get executablePath async {
    final path = await _binPath;
    return Platform.isWindows ? '$path/yt-dlp.exe' : '$path/yt-dlp';
  }

  Future<bool> isInstalled() async {
    final path = await executablePath;
    return File(path).existsSync();
  }

  Future<void> install() async {
    final binPath = await _binPath;
    final dir = Directory(binPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final exePath = await executablePath;
    String url;
    if (Platform.isWindows) {
      url = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';
    } else if (Platform.isMacOS) {
      url = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp';
    } else {
      throw Exception('Unsupported OS');
    }

    final httpClient = HttpClient();
    final request = await httpClient.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode == 200) {
      final file = File(exePath);
      await response.pipe(file.openWrite());
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', exePath]);
      }
    } else {
      throw Exception('Failed to download yt-dlp: ${response.statusCode}');
    }
  }

  Future<String?> downloadMusic(String url, String saveDir) async {
    if (!await isInstalled()) await install();

    final exePath = await executablePath;
    final args = [
      '-x', // Extract audio
      '--audio-format', 'mp3',
      '--audio-quality', '0',
      '-o', '$saveDir/%(title)s.%(ext)s',
      url,
    ];

    try {
      final result = await Process.run(exePath, args);
      if (result.exitCode == 0) {
        // Find the downloaded file
        final dir = Directory(saveDir);
        final files = await dir.list().toList();
        // Return the latest modified mp3 file in the directory (heuristic)
        files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        for (final file in files) {
          if (file.path.endsWith('.mp3')) return file.path;
        }
      } else {
        debugPrint('yt-dlp error: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('Download error: $e');
    }
    return null;
  }

  Future<List<Map<String, String>>> searchYouTube(String query) async {
    if (!await isInstalled()) return [];

    final exePath = await executablePath;
    final args = [
      'ytsearch5:$query',
      '--get-title',
      '--get-id',
      '--flat-playlist',
    ];

    try {
      final result = await Process.run(exePath, args);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n').where((l) => l.isNotEmpty).toList();
        final List<Map<String, String>> results = [];
        for (int i = 0; i < lines.length; i += 2) {
          if (i + 1 < lines.length) {
            results.add({
              'title': lines[i],
              'id': lines[i+1],
              'url': 'https://www.youtube.com/watch?v=${lines[i+1]}',
            });
          }
        }
        return results;
      }
    } catch (e) {
      debugPrint('YouTube search error: $e');
    }
    return [];
  }
}
