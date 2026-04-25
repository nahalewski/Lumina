import 'package:flutter/services.dart';

/// Service that communicates with the native macOS layer via platform channels
class PlatformChannelService {
  static const _channel = MethodChannel('com.lumina.media/subtitle_engine');

  static final PlatformChannelService _instance = PlatformChannelService._();
  factory PlatformChannelService() => _instance;
  PlatformChannelService._();

  /// Event stream for live audio chunks from native layer
  final EventChannel _audioChunkChannel = const EventChannel(
    'com.lumina.media/audio_chunks',
  );

  Stream<Map<String, dynamic>>? _audioChunkStream;

  /// Extract audio from a video file and return the path to the extracted audio
  Future<String> extractAudio(String videoPath) async {
    try {
      final result = await _channel.invokeMethod<String>('extractAudio', {
        'videoPath': videoPath,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('Failed to extract audio: ${e.message}');
    }
  }

  /// Start live audio capture for real-time transcription
  Future<bool> startLiveTranscription() async {
    try {
      final result = await _channel.invokeMethod<bool>('startLiveTranscription');
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to start live transcription: ${e.message}');
    }
  }

  /// Stop live audio capture
  Future<bool> stopLiveTranscription() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopLiveTranscription');
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to stop live transcription: ${e.message}');
    }
  }

  /// Get current audio level (for visualization)
  Future<double> getAudioLevel() async {
    try {
      final result = await _channel.invokeMethod<double>('getAudioLevel');
      return result ?? 0.0;
    } on PlatformException {
      return 0.0;
    }
  }

  /// Export subtitles to an SRT file
  Future<bool> exportSubtitles(String srtContent, String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>('exportSubtitles', {
        'srtContent': srtContent,
        'filePath': filePath,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to export subtitles: ${e.message}');
    }
  }

  /// Request microphone permission on macOS
  Future<bool> requestMicrophonePermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestMicrophonePermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Toggle native fullscreen on macOS
  Future<void> toggleFullscreen() async {
    try {
      await _channel.invokeMethod('toggleFullscreen');
    } on PlatformException catch (e) {
      print('Failed to toggle fullscreen: ${e.message}');
    }
  }

  /// Listen for audio chunks from native layer (for live transcription)
  Stream<Map<String, dynamic>> get audioChunkStream {
    _audioChunkStream ??= _audioChunkChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _audioChunkStream!;
  }
}
