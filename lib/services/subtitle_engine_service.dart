import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/subtitle_model.dart';
import '../models/media_model.dart';
import 'platform_channel_service.dart';
import 'ollama_service.dart';

/// Core subtitle engine:
///   Video audio → whisper-cli (large-v3, Japanese) → Qwen translation → SRT
class SubtitleEngineService {
  final PlatformChannelService _platformChannel = PlatformChannelService();
  final OllamaService _ollama = OllamaService();

  Function(String)? onLog;

  bool _isProcessing = false;
  bool _isTranscribingChunk = false;
  SubtitleMode _currentMode = SubtitleMode.preprocessed;

  // Track active external processes (ffmpeg, whisper-cli) to allow cancellation
  final Map<String, List<Process>> _activeProcesses = {};
  // Deduplicate concurrent calls for the same file
  final Map<String, Future<List<SubtitleEntry>>> _activeTranscriptions = {};

  bool _useOllama = true;
  String _ollamaModel = 'qwen2.5:14b-instruct';
  TranslationProfile _translationProfile = TranslationProfile.standard;

  // Audio buffer for live mode chunk accumulation
  final List<int> _audioBuffer = [];
  // 3 seconds of int16 audio at 16 kHz = 48 000 samples × 2 bytes
  static const int _minChunkBytes = 16000 * 3 * 2;

  static const String _whisperCliPath = '/opt/homebrew/bin/whisper-cli';
  static const String _whisperCliPathIntel = '/usr/local/bin/whisper-cli';

  final StreamController<SubtitleEntry> _subtitleController =
      StreamController<SubtitleEntry>.broadcast();
  final StreamController<String> _transcriptionProgressController =
      StreamController<String>.broadcast();

  StreamSubscription? _audioChunkSubscription;

  Stream<SubtitleEntry> get subtitleStream => _subtitleController.stream;
  Stream<String> get transcriptionProgress => _transcriptionProgressController.stream;
  bool get isProcessing => _isProcessing;
  SubtitleMode get currentMode => _currentMode;

  // ─── Public API ────────────────────────────────────────────────────────────

  Future<List<SubtitleEntry>> processVideoPreprocessed(
    String videoPath, {
    bool useOllama = true,
    String ollamaModel = 'qwen2.5:14b-instruct',
    TranslationProfile translationProfile = TranslationProfile.standard,
  }) async {
    _useOllama = useOllama;
    _ollamaModel = ollamaModel;
    _translationProfile = translationProfile;

    // Check for existing future
    final existingFuture = _activeTranscriptions[videoPath];
    if (existingFuture != null) return existingFuture;

    final future = _runPreprocessedTranscription(videoPath);
    _activeTranscriptions[videoPath] = future;
    try {
      return await future;
    } finally {
      _activeTranscriptions.remove(videoPath);
      _activeProcesses.remove(videoPath);
    }
  }

  Future<void> cancelTranscription(String videoPath) async {
    final processes = _activeProcesses[videoPath];
    if (processes != null) {
      for (final p in processes) {
        p.kill();
      }
      _activeProcesses.remove(videoPath);
    }
    _transcriptionProgressController.add('Cancelled processing for $videoPath');
  }

  Future<void> startLiveTranscription() async {
    _isProcessing = true;
    _currentMode = SubtitleMode.live;
    _audioBuffer.clear();

    try {
      final granted = await _platformChannel.requestMicrophonePermission();
      if (!granted) {
        _transcriptionProgressController.add('ERROR: Microphone permission denied.');
        _isProcessing = false;
        return;
      }

      await _platformChannel.startLiveTranscription();
      _transcriptionProgressController.add('Live: Mic active, listening...');

      // Non-blocking accumulator — never await whisper inside the event callback
      _audioChunkSubscription =
          _platformChannel.audioChunkStream.listen((chunk) {
        final data = chunk['data'] as String?;
        if (data == null || data.isEmpty) return;

        final bytes = base64Decode(data);
        if (bytes.isEmpty) return;

        _audioBuffer.addAll(bytes);

        // When we have enough audio AND no chunk is currently being processed,
        // kick off transcription in the background without blocking the stream.
        if (_audioBuffer.length >= _minChunkBytes && !_isTranscribingChunk) {
          _isTranscribingChunk = true;
          final samples = List<int>.from(_audioBuffer.sublist(0, _minChunkBytes));
          _audioBuffer.removeRange(0, _minChunkBytes);

          // Fire and forget — does NOT block the audio stream listener
          _transcribeChunkAsync(samples);
        }
      }, onError: (e) {
        _transcriptionProgressController.add('Live stream ERROR: $e');
      });
    } catch (e) {
      _isProcessing = false;
      rethrow;
    }
  }

  /// Processes a chunk asynchronously without blocking the audio event stream
  void _transcribeChunkAsync(List<int> samples) {
    _transcribeChunk(samples).then((text) {
      if (text.isNotEmpty) {
        _subtitleController.add(SubtitleEntry(
          index: DateTime.now().millisecondsSinceEpoch,
          startTime: Duration.zero,
          endTime: Duration.zero,
          japaneseText: text,
          englishText: '',
        ));
        _transcriptionProgressController.add('Live: "$text"');
      }
    }).catchError((e) {
      _transcriptionProgressController.add('Live chunk ERROR: $e');
    }).whenComplete(() {
      _isTranscribingChunk = false;
    });
  }


  Future<void> stopLiveTranscription() async {
    _isProcessing = false;
    _audioBuffer.clear();
    await _audioChunkSubscription?.cancel();
    _audioChunkSubscription = null;
    await _platformChannel.stopLiveTranscription();
  }

  Future<String> exportSubtitles(List<SubtitleEntry> entries) async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath =
        '${dir.path}/subtitles_${DateTime.now().millisecondsSinceEpoch}.srt';
    final srtContent = entries.map((e) => e.toSrt()).join();
    await _platformChannel.exportSubtitles(srtContent, filePath);
    return filePath;
  }

  Future<void> savePhrase(String japanese, String english) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/saved_phrases.csv');
    final exists = await file.exists();
    final line =
        '"${japanese.replaceAll('"', '""')}","${english.replaceAll('"', '""')}"';
    await file.writeAsString(
      '${exists ? '' : 'Japanese,English\n'}$line\n',
      mode: exists ? FileMode.append : FileMode.write,
    );
  }

  // ─── Core Pipeline ─────────────────────────────────────────────────────────

  Future<List<SubtitleEntry>> _runPreprocessedTranscription(
      String videoPath) async {
    _isProcessing = true;
    _currentMode = SubtitleMode.preprocessed;

    try {
      _transcriptionProgressController.add('Extracting audio from video...');
      final audioPath = await _platformChannel.extractAudio(videoPath);

      _transcriptionProgressController.add('Isolating vocals (AI hearing boost)...');
      final cleanAudioPath = await _isolateVocals(audioPath);

      _transcriptionProgressController.add('Transcribing Japanese (Whisper Large-v3)...');
      final jaSubtitles = await _transcribeFullAudio(cleanAudioPath);
      
      // Cleanup temporary audio files
      try {
        if (cleanAudioPath != audioPath) await File(cleanAudioPath).delete();
        await File(audioPath).delete();
      } catch (e) {
        debugPrint('Cleanup error: $e');
      }

      _transcriptionProgressController
          .add('Transcription complete — ${jaSubtitles.length} segments.');

      if (jaSubtitles.isEmpty) {
        _transcriptionProgressController
            .add('WARNING: Whisper returned zero segments. Check model and audio.');
        return [];
      }

      List<SubtitleEntry> result = jaSubtitles;

      if (_useOllama) {
        _transcriptionProgressController
            .add('Translating via Qwen ($_ollamaModel)...');
        final jaLines = jaSubtitles.map((s) => s.japaneseText).toList();
        final enLines = await _ollama.translateJapanese(
          jaLines,
          _ollamaModel,
          _translationProfile,
          (p) => _transcriptionProgressController
              .add('Translating: ${(p * 100).toStringAsFixed(1)}%'),
        );

        result = [
          for (var i = 0; i < jaSubtitles.length; i++)
            SubtitleEntry(
              index: jaSubtitles[i].index,
              startTime: jaSubtitles[i].startTime,
              endTime: jaSubtitles[i].endTime,
              japaneseText: jaSubtitles[i].japaneseText,
              englishText:
                  i < enLines.length ? enLines[i] : jaSubtitles[i].japaneseText,
            ),
        ];
      }

      result = _deduplicateSubtitles(result);

      _transcriptionProgressController
          .add('Ready — ${result.length} subtitles.');
      if (result.isNotEmpty) {
        _transcriptionProgressController.add(
            'Coverage: ${result.first.startTime.inSeconds}s → '
            '${result.last.startTime.inSeconds}s');
      }

      return result;
    } catch (e) {
      _transcriptionProgressController.add('Error: $e');
      debugPrint('Transcription error: $e');
      rethrow;
    } finally {
      _isProcessing = false;
    }
  }

  // ─── Whisper Invocation ────────────────────────────────────────────────────

  Future<List<SubtitleEntry>> _transcribeFullAudio(String audioPath) async {
    final modelPath = await _resolveModelPath();
    _transcriptionProgressController
        .add('Using model: ${modelPath.split('/').last}');

    final cliPath = await _getWhisperCliPath();

    final String processedAudio = audioPath;

    final outputBase = '${processedAudio}_ja';

    final args = [
      '-f', processedAudio,
      '-m', modelPath,
      '-l', 'ja',
      '--output-srt',
      '--print-progress',
      '-t', '8',
      '-ml', '0', // No character limit per segment
      '--max-context', '32', // Prevent infinite repetition loops
      '--beam-size', '8',
      '--best-of', '5',
      '--no-speech-thold', '0.2', // Be more aggressive in transcribing noise/music
      '-of', outputBase,
    ];

    _transcriptionProgressController.add('Running: $cliPath ${args.join(' ')}');

    final process = await Process.start(cliPath, args, runInShell: true);
    _activeProcesses[audioPath.replaceAll('_clean.wav', '').replaceAll('.wav', '')]?.add(process);
    
    // Also support videoPath if that's what was registered
    _activeProcesses.forEach((key, list) {
      if (audioPath.contains(key)) list.add(process);
    });

    final stderrBuffer = StringBuffer();
    process.stdout.transform(utf8.decoder).listen((_) {}); // drain
    process.stderr.transform(utf8.decoder).listen((data) {
      stderrBuffer.write(data);
      final m = RegExp(r'\[\s*(\d+)%\]').firstMatch(data);
      if (m != null) {
        _transcriptionProgressController.add('Transcribing: ${m.group(1)}%');
      }
    });

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('whisper-cli failed (exit $exitCode): ${stderrBuffer.toString()}');
    }

    final srtFile = File('$outputBase.srt');
    if (!await srtFile.exists()) return [];

    final content = await srtFile.readAsString();
    await srtFile.delete();
    return _parseSrtContent(content);
  }

  Future<String> _resolveModelPath() async {
    // Prefer large-v3, fall back to small, then tiny
    final appDir = await getApplicationDocumentsDirectory();
    final candidates = [
      '${appDir.path}/models/ggml-large-v3.bin',
      '${appDir.path}/models/ggml-small.bin',
      '${appDir.path}/models/ggml-tiny.bin',
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    // Last-resort: project-relative paths (dev machine)
    final devBase =
        '${Platform.environment['HOME']}/Documents/SRT PLAYER/lumina_media/models';
    for (final name in ['ggml-large-v3.bin', 'ggml-small.bin', 'ggml-tiny.bin']) {
      final p = '$devBase/$name';
      if (await File(p).exists()) return p;
    }
    throw Exception('No Whisper model found. Please add a model to the models/ directory.');
  }

  Future<String> _getWhisperCliPath() async {
    if (await File(_whisperCliPath).exists()) return _whisperCliPath;
    if (await File(_whisperCliPathIntel).exists()) return _whisperCliPathIntel;
    return 'whisper-cli'; // rely on PATH as last resort
  }

  // ─── Live Mode Chunk ───────────────────────────────────────────────────────

  Future<String> _transcribeChunk(List<int> bytes) async {
    final tempDir = Directory.systemTemp;
    final base = '${tempDir.path}/chunk_${DateTime.now().millisecondsSinceEpoch}';
    final wavPath = '$base.wav';

    try {
      await File(wavPath).writeAsBytes(_buildWav(Uint8List.fromList(bytes), 16000));

      // BUG-08: Use _resolveModelPath() which checks all known locations
      // Prefer tiny for low-latency, fall back to whatever is available
      String modelPath;
      try {
        // Try to find tiny model first for speed
        final appDir = await getApplicationDocumentsDirectory();
        final devBase = '${Platform.environment['HOME']}/Documents/SRT PLAYER/lumina_media/models';
        final tinyPaths = [
          '${appDir.path}/models/ggml-tiny.bin',
          '$devBase/ggml-tiny.bin',
          '$devBase/ggml-small.bin',
        ];
        modelPath = tinyPaths.firstWhere(
          (p) => File(p).existsSync(),
          orElse: () => '',
        );
        if (modelPath.isEmpty) modelPath = await _resolveModelPath(); // fallback to best available
      } catch (_) {
        modelPath = await _resolveModelPath();
      }
      final cliPath = await _getWhisperCliPath();

      final result = await Process.run(cliPath, [
        '-f', wavPath,
        '-m', modelPath,
        '-l', 'ja',
        '--output-json',
        '-t', '2',
        '-of', base,
      ], runInShell: true);

      String text = '';
      final jsonFile = File('$base.json');
      if (await jsonFile.exists()) {
        final entries = _parseWhisperJson(await jsonFile.readAsString());
        if (entries.isNotEmpty) text = entries.first.japaneseText;
        await jsonFile.delete();
      } else if (result.stdout is String && (result.stdout as String).isNotEmpty) {
        final entries = _parseWhisperJson(result.stdout as String);
        if (entries.isNotEmpty) text = entries.first.japaneseText;
      }

      return text;
    } catch (e) {
      debugPrint('Chunk transcription error: $e');
      return '';
    } finally {
      try { await File(wavPath).delete(); } catch (_) {}
    }
  }

  // ─── Deduplication ────────────────────────────────────────────────────────

  List<SubtitleEntry> _deduplicateSubtitles(List<SubtitleEntry> entries) {
    if (entries.isEmpty) return entries;

    final result = <SubtitleEntry>[];
    final history = <String>[];
    const maxHistory = 100; // Increased to catch long-range loops

    for (final entry in entries) {
      final en = entry.englishText.toLowerCase().trim();
      final ja = entry.japaneseText.toLowerCase().trim();
      if (en.isEmpty && ja.isEmpty) continue;

      final hash = '${en}_$ja';
      
      final durationMs = entry.endTime.inMilliseconds - entry.startTime.inMilliseconds;
      // Whisper hallucinations are almost exactly 30s
      final is30sBlock = durationMs >= 29500 && durationMs <= 30500;
      
      // Only deduplicate if it's a long segment or a 30s hallucination.
      // Short common phrases like "Yes", "No", "God" (手と手を合わせて...) should NOT be filtered.
      if (ja.length > 8 && history.contains(hash)) {
        if (is30sBlock) continue; // Definitely a hallucination
        
        // If not a 30s block, check if it's very recent (last 3 segments)
        // to handle slight overlaps from Whisper
        final recent = history.sublist(history.length > 3 ? history.length - 3 : 0);
        if (recent.contains(hash)) continue;
      }

      // ARCH-05: Hallucination Filter for recurring 30s blocks with same text
      if (is30sBlock && history.any((h) => h.contains(ja)) && ja.length > 3) {
        continue;
      }

      // Check for common phonetic loop patterns (e.g., 'Rihutereugen')
      if (ja == 'リヒトレーゲン' && is30sBlock) {
         continue; 
      }

      history.add(hash);
      if (history.length > maxHistory) history.removeAt(0);

      // Strip common whisper closing hallucinations
      if (ja.contains('ご視聴ありがとうございました') ||
          ja.contains('チャンネル登録') ||
          ja.contains('視聴ありがとうございました')) {
        continue;
      }

      result.add(entry);
    }
    return result;
  }

  // ─── Parsers ───────────────────────────────────────────────────────────────

  List<SubtitleEntry> _parseSrtContent(String content) {
    if (content.isEmpty) return [];
    return SubtitleEntry.fromSrt(content);
  }

  List<SubtitleEntry> _parseWhisperJson(String jsonContent) {
    final entries = <SubtitleEntry>[];
    if (jsonContent.isEmpty) return entries;

    try {
      // Strip non-JSON preamble
      final start = jsonContent.indexOf('{');
      final end = jsonContent.lastIndexOf('}');
      if (start == -1 || end <= start) return entries;
      final clean = jsonContent.substring(start, end + 1);

      final dynamic data = jsonDecode(clean);
      List<dynamic> segments = [];
      if (data is Map) {
        if (data['transcription'] is List) {
          segments = data['transcription'];
        } else if (data['segments'] is List) {
          segments = data['segments'];
        }
      } else if (data is List) {
        segments = data;
      }

      for (var i = 0; i < segments.length; i++) {
        final seg = segments[i];
        if (seg is! Map) continue;
        final startSec = (seg['start'] as num?)?.toDouble() ?? 0.0;
        final endSec = (seg['end'] as num?)?.toDouble() ?? 0.0;
        // whisper JSON always uses seconds (float)
        final start = Duration(milliseconds: (startSec * 1000).round());
        final end = Duration(milliseconds: (endSec * 1000).round());
        final text = (seg['text'] as String?)?.trim() ?? '';
        if (text.isNotEmpty) {
          entries.add(SubtitleEntry(
            index: i + 1,
            startTime: start,
            endTime: end,
            japaneseText: text,
            englishText: '',
          ));
        }
      }
    } catch (e) {
      debugPrint('Whisper JSON parse error: $e');
    }

    return entries;
  }

  // ─── Audio Utilities ───────────────────────────────────────────────────────

  Uint8List _buildWav(Uint8List pcm, int sampleRate) {
    final header = ByteData(44);
    // RIFF
    header.setUint8(0, 0x52); header.setUint8(1, 0x49);
    header.setUint8(2, 0x46); header.setUint8(3, 0x46);
    header.setUint32(4, 36 + pcm.length, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41);
    header.setUint8(10, 0x56); header.setUint8(11, 0x45);
    // fmt
    header.setUint8(12, 0x66); header.setUint8(13, 0x6d);
    header.setUint8(14, 0x74); header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    // data
    header.setUint8(36, 0x64); header.setUint8(37, 0x61);
    header.setUint8(38, 0x74); header.setUint8(39, 0x61);
    header.setUint32(40, pcm.length, Endian.little);

    final out = Uint8List(44 + pcm.length);
    out.setAll(0, header.buffer.asUint8List(0, 44));
    out.setAll(44, pcm);
    return out;
  }

  Future<String> _isolateVocals(String audioPath) async {
    final outputPath = '${audioPath}_clean.wav';
    // BUG-09: Removed dead 'filter' constant and debug comment
    const filterSafe = 'highpass=f=100,lowpass=f=7000,acompressor=threshold=-20dB:ratio=4:attack=5:release=50';

    final ffmpegPath = (await File('/opt/homebrew/bin/ffmpeg').exists())
        ? '/opt/homebrew/bin/ffmpeg'
        : 'ffmpeg';

    final process = await Process.start(ffmpegPath, [
      '-y', '-i', audioPath,
      '-af', filterSafe,
      '-ar', '16000',
      '-ac', '1',
      outputPath,
    ]);

    // Register process for cancellation
    final baseKey = audioPath.replaceAll('.wav', '');
    _activeProcesses.putIfAbsent(baseKey, () => []).add(process);
    _activeProcesses.forEach((key, list) {
      if (audioPath.contains(key)) list.add(process);
    });

    // Log ffmpeg output to help debug cutting off
    process.stderr.transform(utf8.decoder).listen((data) {
      if (onLog != null) onLog!('FFmpeg: ${data.trim()}');
    });

    final exitCode = await process.exitCode;
    if (exitCode == 0) return outputPath;

    if (onLog != null) onLog!('Vocal isolation failed with exit code $exitCode — using raw audio.');
    return audioPath;
  }
}
