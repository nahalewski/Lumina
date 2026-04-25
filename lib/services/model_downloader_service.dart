import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// Service to handle downloading Whisper models from HuggingFace
class ModelDownloaderService {
  final Map<String, double> _progress = {};
  final Map<String, bool> _isDownloading = {};

  double getProgress(String modelName) => _progress[modelName] ?? 0.0;
  bool isDownloading(String modelName) => _isDownloading[modelName] ?? false;

  static const String _baseUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/';

  Future<void> downloadModel(String modelName, Function(double) onProgress) async {
    if (_isDownloading[modelName] == true) return;

    _isDownloading[modelName] = true;
    _progress[modelName] = 0.0;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${appDir.path}/models');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final savePath = '${modelsDir.path}/$modelName';
      final file = File(savePath);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse('$_baseUrl$modelName'));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to download model: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;

      final IOSink sink = file.openWrite();
      
      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          final p = downloaded / contentLength;
          _progress[modelName] = p;
          onProgress(p);
        }
      }

      await sink.flush();
      await sink.close();
      client.close();
    } catch (e) {
      debugPrint('Download error ($modelName): $e');
      rethrow;
    } finally {
      _isDownloading[modelName] = false;
    }
  }

  Future<bool> isModelInstalled(String modelName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/models/$modelName');
    return await file.exists();
  }

  Future<void> deleteModel(String modelName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/models/$modelName');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
