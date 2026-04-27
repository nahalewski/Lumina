import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';

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

  Future<bool> isFfmpegInstalled() async {
    return await _findFfmpeg() != null;
  }

  Future<void> install() async {
    final binPath = await _binPath;
    final dir = Directory(binPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final exePath = await executablePath;
    String url;
    if (Platform.isWindows) {
      url =
          'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';
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

  Future<void> installFfmpeg() async {
    final binPath = await _binPath;
    final dir = Directory(binPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    if (Platform.isWindows) {
      final zipPath = '$binPath/ffmpeg.zip';
      // Essentials build is smaller (~35MB zipped)
      const url = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip';
      
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        final file = File(zipPath);
        await response.pipe(file.openWrite());
        
        // Extract
        final bytes = File(zipPath).readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);

        for (final file in archive) {
          final filename = file.name;
          if (file.isFile) {
            final data = file.content as List<int>;
            // We need ffmpeg.exe and ffprobe.exe from the bin folder
            if (filename.contains('bin/ffmpeg.exe')) {
              final outFile = File('$binPath/ffmpeg.exe');
              await outFile.writeAsBytes(data);
            } else if (filename.contains('bin/ffprobe.exe')) {
              final outFile = File('$binPath/ffprobe.exe');
              await outFile.writeAsBytes(data);
            }
          }
        }
        
        // Cleanup
        await File(zipPath).delete();
      }
    }
  }

  Future<String?> downloadMusic(
    String url,
    String saveDir, {
    Map<String, dynamic>? spotifyMetadata,
  }) async {
    if (!await isInstalled()) await install();
    
    // Ensure FFmpeg is present for MP3 conversion
    if (!await isFfmpegInstalled()) {
      debugPrint('FFmpeg missing, attempting auto-install...');
      try {
        await installFfmpeg();
      } catch (e) {
        debugPrint('Auto-install of FFmpeg failed: $e');
      }
    }

    final exePath = await executablePath;
    final ffmpeg = await _findFfmpeg();
    final args = [
      '-x', // Extract audio
      '--audio-format', 'mp3',
      '--audio-quality', '0',
      '--restrict-filenames',
      '--embed-thumbnail',
      '--add-metadata',
      if (ffmpeg != null) ...['--ffmpeg-location', ffmpeg],
      '-o', '$saveDir/%(title)s.%(ext)s',
      '--print', 'after_move:filepath', // Get exact final path
      url,
    ];

    String? finalPath;

    try {
      debugPrint('MediaProvider: Starting download: $url');
      debugPrint('MediaProvider: Command: $exePath ${args.join(' ')}');
      
      final result = await Process.run(exePath, args);
      
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().trim().split('\n');
        finalPath = lines.last.trim();
        if (finalPath.isEmpty || !File(finalPath).existsSync()) {
           finalPath = null;
        }
      } else {
        debugPrint('MediaProvider: yt-dlp failed with exit code ${result.exitCode}');
        debugPrint('MediaProvider: Error: ${result.stderr}');
      }

      // Fallback: search directory for the most recent mp3
      if (finalPath == null) {
        debugPrint('MediaProvider: Falling back to directory scan...');
        final dir = Directory(saveDir);
        final files = await dir.list().toList();
        files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        
        for (final file in files) {
          if (file.path.toLowerCase().endsWith('.mp3')) {
            if (DateTime.now().difference(file.statSync().modified).inMinutes < 2) {
              finalPath = file.path;
              break;
            }
          }
        }
      }

      if (finalPath != null) {
        debugPrint('MediaProvider: Download successful: $finalPath');
        
        // Apply high-quality Spotify metadata/artwork if available
        await _applySpotifyMetadata(finalPath, spotifyMetadata);
        
        // Rename file based on Spotify metadata if available
        if (spotifyMetadata != null) {
          try {
            final title = spotifyMetadata['name']?.toString() ?? '';
            final artist = (spotifyMetadata['artists'] as List?)?.first['name']?.toString() ?? '';
            if (title.isNotEmpty && artist.isNotEmpty) {
              final ext = finalPath.split('.').last;
              final newName = '$artist - $title.$ext'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
              final newPath = '${p.dirname(finalPath)}/$newName';
              if (finalPath != newPath) {
                final newFile = await File(finalPath).rename(newPath);
                finalPath = newFile.path;
              }
            }
          } catch (e) {
            debugPrint('Error renaming file: $e');
          }
        }

        // Clean up any leftover image files from yt-dlp
        final baseName = finalPath!.replaceAll(RegExp(r'\.[^.]+$'), '');
        for (final ext in ['.webp', '.jpg', '.png', '.jpeg']) {
          final imgFile = File('$baseName$ext');
          if (await imgFile.exists()) {
            await imgFile.delete().catchError((_) => imgFile);
          }
        }
        
        return finalPath;
      }
    } catch (e) {
      debugPrint('MediaProvider: Exception during download: $e');
    }
    return null;
  }

  Future<Map<String, String>> getMediaMetadata(String filePath) async {
    final ffmpeg = await _findFfmpeg();
    if (ffmpeg == null) return {};

    // ffprobe is usually in the same directory as ffmpeg
    final ffprobe = ffmpeg.replaceAll('ffmpeg', 'ffprobe');
    if (!File(ffprobe).existsSync()) return {};

    final args = [
      '-v', 'quiet',
      '-print_format', 'json',
      '-show_format',
      filePath,
    ];

    try {
      final result = await Process.run(ffprobe, args);
      if (result.exitCode == 0) {
        final data = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
        final format = data['format'] as Map<String, dynamic>?;
        final tags = format?['tags'] as Map<String, dynamic>?;
        
        if (tags != null) {
          return {
            'title': tags['title']?.toString() ?? '',
            'artist': tags['artist']?.toString() ?? '',
            'album': tags['album']?.toString() ?? '',
            'date': tags['date']?.toString() ?? '',
            'track': tags['track']?.toString() ?? '',
          };
        }
      }
    } catch (e) {
      debugPrint('Error extracting metadata with ffprobe: $e');
    }
    return {};
  }

  Future<void> _applySpotifyMetadata(
    String filePath,
    Map<String, dynamic>? metadata,
  ) async {
    if (metadata == null || metadata.isEmpty) return;
    final ffmpeg = await _findFfmpeg();
    if (ffmpeg == null) return;

    final album = metadata['album'] as Map<String, dynamic>?;
    final artists = (metadata['artists'] as List?)
            ?.whereType<Map>()
            .map((artist) => artist['name']?.toString())
            .whereType<String>()
            .where((name) => name.isNotEmpty)
            .join(', ') ??
        '';
    final images = album?['images'] as List?;
    final imageUrl = images?.isNotEmpty == true
        ? (images!.first as Map)['url']?.toString()
        : null;
    String? coverPath;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200) {
          coverPath = '$filePath.spotify-cover.jpg';
          await File(coverPath).writeAsBytes(response.bodyBytes);
        }
      } catch (_) {}
    }

    final isMp3 = filePath.toLowerCase().endsWith('.mp3');
    final ext = filePath.split('.').last;
    final tempPath = '$filePath.spotify-tags.tmp.$ext';
    
    final args = [
      '-y',
      '-i', filePath,
      if (coverPath != null) ...['-i', coverPath],
      '-map', '0:a',
      if (coverPath != null) ...['-map', '1:v'],
      '-c', 'copy',
      if (isMp3) ...['-id3v2_version', '3'],
      if (coverPath != null && isMp3) ...[
        '-metadata:s:v', 'title=Album cover',
        '-metadata:s:v', 'comment=Cover (front)',
        '-disposition:v', 'attached_pic',
      ],
      '-metadata', 'title=${metadata['name'] ?? ''}',
      '-metadata', 'artist=$artists',
      '-metadata', 'album=${album?['name'] ?? ''}',
      '-metadata', 'date=${album?['release_date'] ?? ''}',
      '-metadata', 'track=${metadata['track_number'] ?? ''}',
      tempPath,
    ];

    try {
      final result = await Process.run(ffmpeg, args);
      if (result.exitCode == 0 && await File(tempPath).exists()) {
        await File(tempPath).rename(filePath);
      } else {
        debugPrint('ffmpeg metadata error: ${result.stderr}');
        await File(tempPath).delete().catchError((_) => File(tempPath));
      }
    } catch (e) {
      debugPrint('Spotify metadata tagging error: $e');
    } finally {
      if (coverPath != null) {
        await File(coverPath).delete().catchError((_) => File(coverPath!));
      }
    }
  }

  Future<String?> _findFfmpeg() async {
    // Check in the same bin directory as yt-dlp first
    final binPath = await _binPath;
    final localFfmpeg = Platform.isWindows ? '$binPath/ffmpeg.exe' : '$binPath/ffmpeg';
    if (File(localFfmpeg).existsSync()) return localFfmpeg;

    final candidates =
        Platform.isWindows ? const ['ffmpeg.exe', 'ffmpeg'] : const ['ffmpeg'];
    for (final candidate in candidates) {
      try {
        final result = await Process.run(candidate, ['-version']);
        if (result.exitCode == 0) return candidate;
      } catch (_) {}
    }
    return null;
  }

  Future<List<Map<String, String>>> searchYouTube(String query) async {
    if (!await isInstalled()) return [];

    final exePath = await executablePath;
    final args = [
      'ytsearch25:$query',
      '--print',
      '%(title)s',
      '--print',
      '%(id)s',
      '--print',
      '%(thumbnail)s',
    ];

    try {
      final result = await Process.run(exePath, args);
      if (result.exitCode == 0) {
        final lines = result.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .where((l) => l.trim().isNotEmpty)
            .map((l) => l.trim())
            .toList();
        final List<Map<String, String>> results = [];
        for (int i = 0; i < lines.length; i += 3) {
          if (i + 2 < lines.length) {
            results.add({
              'title': lines[i],
              'id': lines[i + 1],
              'thumbnail': lines[i + 2],
              'url': 'https://www.youtube.com/watch?v=${lines[i + 1]}',
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
