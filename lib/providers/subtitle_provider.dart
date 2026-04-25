import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../models/subtitle_model.dart';
import '../models/media_model.dart';
import '../services/subtitle_engine_service.dart';

/// Manages subtitle state and synchronization
class SubtitleProvider extends ChangeNotifier {
  final SubtitleEngineService _engine = SubtitleEngineService();
  
  List<SubtitleEntry> _subtitles = [];
  SubtitleEntry? _currentSubtitle;
  SubtitleMode _mode = SubtitleMode.preprocessed;
  final SubtitleDisplayOptions _displayOptions = SubtitleDisplayOptions();
  bool _isProcessing = false;
  String _processingStatus = '';

  // Phase 3: Learning Mode
  bool _isABRepeatEnabled = false;
  Duration? _loopStart;
  Duration? _loopEnd;
  final List<SubtitleEntry> _starredSubtitles = [];
  String? _currentVideoPath;
  final List<String> _debugLogs = [];
  StreamSubscription<SubtitleEntry>? _subtitleSubscription;
  StreamSubscription<String>? _progressSubscription;

  List<SubtitleEntry> get subtitles => _subtitles;
  SubtitleEntry? get currentSubtitle => _currentSubtitle;
  SubtitleMode get mode => _mode;
  SubtitleDisplayOptions get displayOptions => _displayOptions;
  bool get isProcessing => _isProcessing;
  String get processingStatus => _processingStatus;
  bool get isABRepeatEnabled => _isABRepeatEnabled;
  Duration? get loopStart => _loopStart;
  Duration? get loopEnd => _loopEnd;
  List<SubtitleEntry> get starredSubtitles => _starredSubtitles;
  SubtitleProvider() {
    _engine.onLog = _onEngineLog;
  }

  SubtitleEngineService get engine => _engine;
  List<String> get debugLogs => List.unmodifiable(_debugLogs);

  // BUG-06: Engine logs go to debug panel; noisy position logs are filtered
  void _onEngineLog(String message) => addDebugLog(message);

  void addDebugLog(String message) {
    // BUG-06: Don't flood with per-second position ticks
    if (message.startsWith('Playback: No subtitle for')) return;
    final timestamp = DateTime.now().toIso8601String().split('T')[1].split('.')[0];
    _debugLogs.insert(0, '[$timestamp] $message');
    if (_debugLogs.length > 100) _debugLogs.removeLast();
    notifyListeners();
  }

  /// Load existing subtitles for a video if available
  Future<void> loadSubtitlesForVideo(String videoPath) async {
    if (_currentVideoPath == videoPath && _subtitles.isNotEmpty) return;
    
    _currentVideoPath = videoPath;
    _subtitles = [];
    _currentSubtitle = null;
    
    final srtPath = '${videoPath.replaceAll(RegExp(r'\.[^.]+$'), '')}.srt';
    final srtFile = File(srtPath);
    
    if (await srtFile.exists()) {
      addDebugLog('Loading subtitles from disk: ${srtPath.split('/').last}');
      try {
        final content = await srtFile.readAsString();
        _subtitles = SubtitleEntry.fromSrt(content);
        _processingStatus = 'Ready (${_subtitles.length} entries)';
        _mode = SubtitleMode.preprocessed;
      } catch (e) {
        addDebugLog('Error loading SRT: $e');
        _processingStatus = 'Error loading subtitles';
      }
    } else {
      _processingStatus = 'No subtitles found';
    }
    notifyListeners();
  }

  /// Process video in preprocessed mode (full audio -> transcribe -> translate)
  Future<void> processVideoPreprocessed(
    String videoPath, {
    bool useOllama = true,
    String ollamaModel = 'qwen2.5:14b-instruct',
    TranslationProfile translationProfile = TranslationProfile.standard,
  }) async {
    // Avoid re-processing if already active for this file
    if (_subtitles.isNotEmpty && _processingStatus.contains('Ready') && _currentVideoPath == videoPath) return;
    
    _currentVideoPath = videoPath;
    _isProcessing = true;
    _mode = SubtitleMode.preprocessed;
    notifyListeners();

    try {
      // Listen for progress updates
      _progressSubscription = _engine.transcriptionProgress.listen((status) {
        _processingStatus = status;
        addDebugLog('Engine: $status');
        notifyListeners();
      });

      addDebugLog('Starting preprocessed transcription for: $videoPath');
      _subtitles = await _engine.processVideoPreprocessed(
        videoPath,
        useOllama: useOllama,
        ollamaModel: ollamaModel,
        translationProfile: translationProfile,
      );
      _processingStatus = 'Ready - ${_subtitles.length} subtitle entries';
      addDebugLog('Transcription finished. Loaded ${_subtitles.length} entries.');
      
      // Auto-export on completion
      await _autoExport(videoPath);
      
      notifyListeners();
    } catch (e) {
      _processingStatus = 'Error: $e';
      addDebugLog('Transcription error: $e');
      _isProcessing = false;
      notifyListeners();
      rethrow;
    } finally {
      _isProcessing = false;
      _progressSubscription?.cancel();
      notifyListeners();
    }
  }

  /// Process in background for library items
  Future<void> processInBackground(
    String videoPath, {
    bool useOllama = true,
    String ollamaModel = 'qwen2.5:14b-instruct',
    TranslationProfile translationProfile = TranslationProfile.standard,
  }) async {
    await processVideoPreprocessed(
      videoPath,
      useOllama: useOllama,
      ollamaModel: ollamaModel,
      translationProfile: translationProfile,
    );
  }

  /// Start live transcription mode
  Future<void> startLiveTranscription() async {
    _isProcessing = true;
    _mode = SubtitleMode.live;
    notifyListeners();

    try {
      _subtitleSubscription = _engine.subtitleStream.listen((entry) {
        _currentSubtitle = entry;
        addDebugLog('Live: Received segment "${entry.japaneseText.substring(0, entry.japaneseText.length > 20 ? 20 : entry.japaneseText.length)}..."');
        notifyListeners();
      });

      addDebugLog('Requesting live transcription start...');
      await _engine.startLiveTranscription();
      _processingStatus = 'Live transcription active';
      addDebugLog('Live mode activated.');
    } catch (e) {
      _processingStatus = 'Error: $e';
      addDebugLog('Live mode error: $e');
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Stop live transcription
  Future<void> stopLiveTranscription() async {
    await _engine.stopLiveTranscription();
    await _subtitleSubscription?.cancel();
    _subtitleSubscription = null;
    _isProcessing = false;
    _currentSubtitle = null;
    _processingStatus = '';
    notifyListeners();
  }

  /// ARCH-01: Use dynamic path instead of hardcoded user path
  Future<void> _autoExport(String videoPath) async {
    try {
      // Export next to the source video first (most useful location)
      final videoDir = Directory(videoPath.substring(0, videoPath.lastIndexOf('/')));
      final videoName = videoPath.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final srtFile = File('${videoDir.path}/subtitles_${videoName}_$timestamp.srt');
      final buffer = StringBuffer();
      for (final entry in _subtitles) {
        buffer.write(entry.toSrt());
      }
      await srtFile.writeAsString(buffer.toString());
      addDebugLog('Exported SRT → ${srtFile.path}');

      // Also export debug log to same folder
      final logFile = File('${videoDir.path}/lumina_debug_log.txt');
      final logBuffer = StringBuffer();
      logBuffer.writeln('--- Session: ${DateTime.now()} ---');
      for (final log in _debugLogs.reversed) {
        logBuffer.writeln(log);
      }
      logBuffer.writeln();
      await logFile.writeAsString(logBuffer.toString(), mode: FileMode.append);
    } catch (e) {
      addDebugLog('Auto-export failed: $e');
    }
  }

  /// Update current subtitle based on playback position
  void updateSubtitleForPosition(Duration position) {
    if (_mode == SubtitleMode.live) return;

    if (_subtitles.isEmpty) {
      if (_currentSubtitle != null) {
        _currentSubtitle = null;
        notifyListeners(); // BUG-05: only notify when state changes
      }
      return;
    }

    final adjustedPosition = position + Duration(
      milliseconds: (_displayOptions.delaySeconds * 1000).round(),
    );

    SubtitleEntry? found;
    int lo = 0, hi = _subtitles.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final entry = _subtitles[mid];
      if (adjustedPosition >= entry.startTime && adjustedPosition < entry.endTime) {
        found = entry;
        break;
      } else if (adjustedPosition < entry.startTime) {
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }

    // Only rebuild the tree when the subtitle actually changes
    if (found != _currentSubtitle) {
      _currentSubtitle = found;
      notifyListeners();
    }
  }

  /// Toggle Japanese subtitle display
  void toggleJapanese() {
    _displayOptions.showJapanese = !_displayOptions.showJapanese;
    notifyListeners();
  }

  /// Toggle English subtitle display
  void toggleEnglish() {
    _displayOptions.showEnglish = !_displayOptions.showEnglish;
    notifyListeners();
  }

  /// Set subtitle delay
  void setSubtitleDelay(double seconds) {
    _displayOptions.delaySeconds = seconds.clamp(0.0, 3.0);
    notifyListeners();
  }

  /// Set subtitle font size
  void setFontSize(double size) {
    _displayOptions.fontSize = size.clamp(12.0, 36.0);
    notifyListeners();
  }

  /// Toggle always-on-top for subtitle window
  void toggleAlwaysOnTop() {
    _displayOptions.alwaysOnTop = !_displayOptions.alwaysOnTop;
    notifyListeners();
  }

  /// ARCH-04: Reset all subtitle state when switching to a new media file
  void resetForNewMedia() {
    _subtitles = [];
    _currentSubtitle = null;
    _isProcessing = false;
    _processingStatus = '';
    _mode = SubtitleMode.preprocessed;
    _debugLogs.clear();
    notifyListeners();
  }

  /// Export subtitles to SRT file
  Future<String> exportSubtitles() async {
    return await _engine.exportSubtitles(_subtitles);
  }

  /// Save a phrase for learning
  Future<void> savePhrase(String japanese, String english) async {
    await _engine.savePhrase(japanese, english);
  }

  /// Load subtitles from a list of entries
  void loadSubtitles(List<SubtitleEntry> entries) {
    _subtitles = entries;
    notifyListeners();
  }

  /// Load an external SRT file provided by the user
  Future<void> loadExternalSrt(String srtPath) async {
    final srtFile = File(srtPath);
    if (await srtFile.exists()) {
      addDebugLog('Importing external SRT: ${srtPath.split('/').last}');
      try {
        final content = await srtFile.readAsString();
        _subtitles = SubtitleEntry.fromSrt(content);
        _processingStatus = 'Imported (${_subtitles.length} entries)';
        _mode = SubtitleMode.preprocessed;
        _currentSubtitle = null;
        notifyListeners();
      } catch (e) {
        addDebugLog('Error importing SRT: $e');
      }
    }
  }

  void updateFontSize(double size) {
    _displayOptions.fontSize = size;
    notifyListeners();
  }

  void updateDelay(double seconds) {
    _displayOptions.delaySeconds = seconds;
    notifyListeners();
  }

  void updateVerticalOffset(double offset) {
    _displayOptions.verticalOffset = offset;
    notifyListeners();
  }

  void updateColor(int colorValue) {
    _displayOptions.colorValue = colorValue;
    notifyListeners();
  }

  void updateBackgroundColor(int colorValue) {
    _displayOptions.backgroundColorValue = colorValue;
    notifyListeners();
  }

  // ─── Phase 3: Learning Mode ──────────────────────────────────────────────

  void toggleABRepeat() {
    if (_isABRepeatEnabled) {
      _isABRepeatEnabled = false;
      _loopStart = null;
      _loopEnd = null;
    } else if (_currentSubtitle != null) {
      _isABRepeatEnabled = true;
      _loopStart = _currentSubtitle!.startTime;
      _loopEnd = _currentSubtitle!.endTime;
    }
    notifyListeners();
  }

  void starSubtitle(SubtitleEntry entry) {
    if (!_starredSubtitles.any((s) => s.startTime == entry.startTime && s.englishText == entry.englishText)) {
      _starredSubtitles.add(entry);
      notifyListeners();
    }
  }

  void unstarSubtitle(SubtitleEntry entry) {
    _starredSubtitles.removeWhere((s) => s.startTime == entry.startTime && s.englishText == entry.englishText);
    notifyListeners();
  }

  bool isStarred(SubtitleEntry entry) {
    return _starredSubtitles.any((s) => s.startTime == entry.startTime && s.englishText == entry.englishText);
  }

  /// Check if the current subtitle contains any word from the vocabulary list
  SubtitleEntry? findVocabularyMatch(SubtitleEntry current) {
    if (_starredSubtitles.isEmpty) return null;
    
    // Check if any starred phrase's Japanese text exists in the current subtitle's Japanese text
    for (var starred in _starredSubtitles) {
      if (starred.japaneseText.isNotEmpty && 
          current.japaneseText.contains(starred.japaneseText) &&
          starred.japaneseText != current.japaneseText) {
        return starred;
      }
    }
    return null;
  }

  // ─── Subtitle Editing / Correction (#2) ──────────────────────────────────

  /// Edit a subtitle entry at the given index
  void editSubtitle(int index, {String? japaneseText, String? englishText}) {
    if (index < 0 || index >= _subtitles.length) return;
    final entry = _subtitles[index];
    if (japaneseText != null) {
      _subtitles[index] = SubtitleEntry(
        index: entry.index,
        startTime: entry.startTime,
        endTime: entry.endTime,
        japaneseText: japaneseText,
        englishText: englishText ?? entry.englishText,
      );
    } else if (englishText != null) {
      _subtitles[index] = SubtitleEntry(
        index: entry.index,
        startTime: entry.startTime,
        endTime: entry.endTime,
        japaneseText: entry.japaneseText,
        englishText: englishText,
      );
    }
    notifyListeners();
  }

  /// Save edited subtitles back to the SRT file on disk
  Future<void> saveEditedSrt() async {
    if (_currentVideoPath == null || _subtitles.isEmpty) return;
    
    final srtPath = '${_currentVideoPath!.replaceAll(RegExp(r'\.[^.]+$'), '')}.srt';
    try {
      final buffer = StringBuffer();
      for (final entry in _subtitles) {
        buffer.write(entry.toSrt());
      }
      await File(srtPath).writeAsString(buffer.toString());
      addDebugLog('Edited SRT saved to: ${srtPath.split('/').last}');
    } catch (e) {
      addDebugLog('Error saving edited SRT: $e');
    }
  }

  @override
  void dispose() {
    _subtitleSubscription?.cancel();
    _progressSubscription?.cancel();
    super.dispose();
  }

  // ─── Subtitle Search (#6) ────────────────────────────────────────────────

  /// Search across all subtitles for matching text (Japanese or English)
  /// Returns entries where either text field contains the query (case-insensitive)
  List<SubtitleEntry> searchSubtitles(String query) {
    if (query.isEmpty) return [];
    final lowerQuery = query.toLowerCase();
    return _subtitles.where((entry) =>
      entry.japaneseText.toLowerCase().contains(lowerQuery) ||
      entry.englishText.toLowerCase().contains(lowerQuery)
    ).toList();
  }

  /// Seek to a specific subtitle entry's start time
  void seekToSubtitle(SubtitleEntry entry) {
    _currentSubtitle = entry;
    notifyListeners();
  }

  /// Export current subtitles to an SRT file
  Future<void> exportSrt() async {

    if (_subtitles.isEmpty) return;

    final srtContent = _subtitles.map((e) => e.toSrt()).join('');
    final defaultName = _currentVideoPath != null 
        ? '${_currentVideoPath!.split('/').last.split('.').first}.srt'
        : 'subtitles.srt';

    try {
      final String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'Export Subtitles',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['srt'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(srtContent);
        addDebugLog('Subtitles exported to: ${outputFile.split('/').last}');
      }
    } catch (e) {
      addDebugLog('Error exporting SRT: $e');
    }
  }
}
