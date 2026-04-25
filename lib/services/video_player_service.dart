import 'dart:async';
import 'package:flutter/services.dart';

/// Service that communicates with the native macOS AVPlayer via platform channels
class VideoPlayerService {
  static const _methodChannel = MethodChannel('com.lumina.media/video_player');
  static const _eventChannel = EventChannel('com.lumina.media/video_player_events');

  static final VideoPlayerService _instance = VideoPlayerService._();
  factory VideoPlayerService() => _instance;
  VideoPlayerService._();

  final StreamController<Map<String, dynamic>> _eventController = 
      StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _eventSubscription;

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  bool _initialized = false;

  /// Initialize the event stream listener
  void initialize() {
    if (_initialized) return;
    _initialized = true;
    
    _eventSubscription = _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map))
        .listen((event) {
      _eventController.add(event);
    });
  }

  /// Open and play a video file
  Future<bool> open(String path) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('open', {
        'path': path,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to open video: ${e.message}');
    }
  }

  /// Play the video
  Future<void> play() async {
    try {
      await _methodChannel.invokeMethod<void>('play');
    } on PlatformException catch (e) {
      throw Exception('Failed to play: ${e.message}');
    }
  }

  /// Pause the video
  Future<void> pause() async {
    try {
      await _methodChannel.invokeMethod<void>('pause');
    } on PlatformException catch (e) {
      throw Exception('Failed to pause: ${e.message}');
    }
  }

  /// Seek to a position (in milliseconds)
  Future<void> seek(double positionMs) async {
    try {
      await _methodChannel.invokeMethod<void>('seek', {
        'position': positionMs,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to seek: ${e.message}');
    }
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    try {
      await _methodChannel.invokeMethod<void>('setVolume', {
        'volume': volume,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to set volume: ${e.message}');
    }
  }

  /// Close the video player
  Future<void> close() async {
    try {
      await _methodChannel.invokeMethod<void>('close');
    } on PlatformException catch (e) {
      throw Exception('Failed to close: ${e.message}');
    }
  }

  /// Get current position in milliseconds
  Future<double> getPosition() async {
    try {
      final result = await _methodChannel.invokeMethod<double>('getPosition');
      return result ?? 0.0;
    } on PlatformException {
      return 0.0;
    }
  }

  /// Get duration in milliseconds
  Future<double> getDuration() async {
    try {
      final result = await _methodChannel.invokeMethod<double>('getDuration');
      return result ?? 0.0;
    } on PlatformException {
      return 0.0;
    }
  }

  /// Check if video is playing
  Future<bool> isPlaying() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isPlaying');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _eventSubscription?.cancel();
    _eventController.close();
  }
}
