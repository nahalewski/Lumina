import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/iptv_service.dart';

class IptvPipProvider extends ChangeNotifier {
  IptvMedia? currentMedia;
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool pipActive = false;
  double volume = 1.0;
  double playbackSpeed = 1.0;

  VideoPlayerController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  bool get isMuted => _controller?.value.volume == 0.0;

  Future<void> openMedia(IptvMedia media) async {
    if (currentMedia?.url != media.url) {
      await _disposeController();
      currentMedia = media;
      _isInitialized = false;
      _isPlaying = false;
      _hasError = false;
      _errorMessage = '';
      pipActive = false;

      try {
        _controller = VideoPlayerController.networkUrl(Uri.parse(media.url));
        await _controller!.initialize();
        _controller!.addListener(_onControllerUpdate);
        _controller!.setVolume(volume);
        _controller!.setPlaybackSpeed(playbackSpeed);
        await _controller!.play();
        _isInitialized = true;
        _isPlaying = true;
      } catch (e) {
        _hasError = true;
        _errorMessage = e.toString();
      }
      notifyListeners();
      return;
    }

    pipActive = false;
    if (_controller != null && !_controller!.value.isPlaying) {
      await _controller!.play();
      _isPlaying = true;
    }
    notifyListeners();
  }

  void _onControllerUpdate() {
    if (_controller == null) return;
    final playing = _controller!.value.isPlaying;
    final hasError = _controller!.value.hasError;
    final errorMessage = _controller!.value.errorDescription ?? '';
    var changed = false;

    if (playing != _isPlaying) {
      _isPlaying = playing;
      changed = true;
    }
    if (hasError != _hasError) {
      _hasError = hasError;
      changed = true;
    }
    if (hasError && errorMessage != _errorMessage) {
      _errorMessage = errorMessage;
      changed = true;
    }

    if (changed) notifyListeners();
  }

  void enterPip() {
    if (currentMedia == null || _controller == null) return;
    pipActive = true;
    notifyListeners();
  }

  Future<void> closePip() async {
    pipActive = false;
    currentMedia = null;
    await _disposeController();
    notifyListeners();
  }

  Future<void> pause() async {
    if (_controller == null) return;
    await _controller!.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> play() async {
    if (_controller == null) return;
    await _controller!.play();
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0.0, 1.0);
    if (_controller != null) {
      await _controller!.setVolume(volume);
    }
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double value) async {
    playbackSpeed = value;
    if (_controller != null) {
      await _controller!.setPlaybackSpeed(playbackSpeed);
    }
    notifyListeners();
  }

  Future<void> _disposeController() async {
    if (_controller != null) {
      _controller!.removeListener(_onControllerUpdate);
      await _controller!.dispose();
      _controller = null;
    }
    _isInitialized = false;
    _isPlaying = false;
    _hasError = false;
    _errorMessage = '';
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }
}
