import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/media_model.dart';

class OllamaService {
  static const String _baseUrl = 'http://localhost:11434/api/chat';
  static const String _tagsUrl = 'http://localhost:11434/api/tags';

  Future<List<String>> getModels() async {
    try {
      final response = await http.get(Uri.parse(_tagsUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> models = data['models'] ?? [];
        return models.map((m) => m['name'] as String).toList();
      }
    } catch (e) {
      debugPrint('Error fetching Ollama models: $e');
    }
    return [];
  }

  /// Translate a batch of Japanese subtitle lines directly to English using Qwen.
  Future<List<String>> translateJapanese(
    List<String> jaLines,
    String model,
    TranslationProfile profile,
    Function(double progress) onProgress,
  ) async {
    final results = <String>[];
    const batchSize = 10;

    final adultSystemPrompt = 
        'You are a professional Japanese-to-English adult content translator. Your goal is to provide highly accurate, explicit, and contextual translations in ENGLISH ONLY. '
        'In sexual contexts, terms like "iku" (イクッ) or "mou deru" (もう出る) MUST be translated as "I\'m cumming", "I\'m about to blow", or similar direct expressions. '
        'DO NOT use polite euphemisms like "I\'m going" or "I\'m coming out" unless it literally refers to leaving a room. '
        'Preserve all emotional punctuation and symbols like hearts (♥, \u2665) as raw characters. '
        'Output ONLY a valid JSON array of ENGLISH strings, one per input line. Array length must match input exactly. NEVER output Chinese.';

    final standardSystemPrompt = 
        'You are a high-end Japanese-to-English anime subtitle translator. Your goal is to provide accurate ENGLISH translations. '
        'Preserve the tone, character voice, and specific universe terminology. '
        'DO NOT translate iconic proper nouns literally. Keep them as they are or transliterate them: '
        '- "Bankai" (挽回/卍解) -> "Bankai" (NOT "comeback") '
        '- "Shikai" -> "Shikai" '
        '- "Zanpakuto" -> "Zanpakuto" '
        '- "Shin\'uchi" (真打) -> "Shin\'uchi" '
        '- "Shinigami" -> "Shinigami" or "Soul Reaper" '
        '- "Ichimonji" -> "Ichimonji" '
        'Preserve hearts (♥) and symbols as raw characters. '
        'Output ONLY a valid JSON array of ENGLISH strings, one per input line. Array length must match input exactly. NEVER output Chinese.';

    final systemPrompt = profile == TranslationProfile.adult ? adultSystemPrompt : standardSystemPrompt;

    for (var i = 0; i < jaLines.length; i += batchSize) {
      final batch = jaLines.sublist(
          i, (i + batchSize).clamp(0, jaLines.length));

      try {
        final response = await http.post(
          Uri.parse(_baseUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': jsonEncode(batch)},
            ],
            'stream': false,
            'format': 'json',
            'options': {
              'temperature': profile == TranslationProfile.adult ? 0.1 : 0.3,
            },
          }),
        ).timeout(const Duration(seconds: 120));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final responseText = data['message']['content'] as String;
          final dynamic decoded = jsonDecode(responseText);

          List<String> translated = [];
          if (decoded is List) {
            translated = decoded.map((e) => e.toString()).toList();
          } else if (decoded is Map) {
            // Qwen often wraps the array: {"lines":[...]}, {"translations":[...]}, etc.
            // Find the first value that is a List and use it.
            for (final v in decoded.values) {
              if (v is List) {
                translated = v.map((e) => e.toString()).toList();
                break;
              }
            }
          }

          for (var j = 0; j < batch.length; j++) {
            String line = j < translated.length ? translated[j].trim() : batch[j];
            results.add(_unescapeUnicode(line));
          }
        } else {
          debugPrint('Qwen HTTP error: ${response.statusCode}');
          results.addAll(batch);
        }
      } catch (e) {
        debugPrint('Qwen translation error: $e');
        // Fall back to original Japanese rather than crashing the whole run
        results.addAll(batch);
      }

      onProgress((i + batch.length) / jaLines.length);
    }

    return results;
  }

  String _unescapeUnicode(String text) {
    try {
      return text.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (match) {
        return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
      });
    } catch (e) {
      return text;
    }
  }
}
