import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/iptv_service.dart';

/// Full-screen IPTV player for live channels, movies, and TV shows.
/// Opens as a modal with full playback controls.
class IptvPlayerScreen extends StatefulWidget {
  final IptvMedia media;
  final String? subtitle;

  const IptvPlayerScreen({
    super.key,
    required this.media,
    this.subtitle,
  });

  @override
  State<IptvPlayerScreen> createState() => _IptvPlayerScreenState();
}

class _IptvPlayerScreenState extends State<IptvPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  double _playbackSpeed = 1.0;
  double _volume = 1.0;
  bool _isMuted = false;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controlsTimer?.cancel();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.media.url));
      await _controller!.initialize();
      _controller!.addListener(_onControllerUpdate);
      if (mounted) {
        setState(() => _isInitialized = true);
        _controller!.play();
        _startControlsTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _onControllerUpdate() {
    if (_controller == null) return;
    final playing = _controller!.value.isPlaying;
    if (playing != _isPlaying) {
      setState(() => _isPlaying = playing);
    }
    if (_controller!.value.hasError && !_hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = _controller!.value.errorDescription ?? 'Unknown error';
      });
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startControlsTimer();
  }

  String _formatPosition(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  void _skipForward() {
    final pos = _controller!.value.position + const Duration(seconds: 10);
    _controller!.seekTo(pos);
    _startControlsTimer();
  }

  void _skipBackward() {
    final pos = _controller!.value.position - const Duration(seconds: 10);
    _controller!.seekTo(pos < Duration.zero ? Duration.zero : pos);
    _startControlsTimer();
  }

  void _setSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _controller!.setPlaybackSpeed(speed);
    _startControlsTimer();
  }

  void _setVolume(double vol) {
    setState(() {
      _volume = vol;
      _isMuted = vol == 0;
    });
    _controller!.setVolume(vol);
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0 : _volume);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.media.name,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.media.logo != null && widget.media.logo!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Image.network(
                widget.media.logo!,
                width: 32,
                height: 32,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
      body: _hasError
          ? _buildErrorState()
          : _isInitialized
              ? _buildPlayerWithControls()
              : _buildLoadingState(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            const Text(
              'Playback Error',
              style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _errorMessage = '';
                });
                _initPlayer();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(color: Color(0xFFE9B3FF), strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            widget.media.isLive ? 'Connecting to channel...' : 'Loading stream...',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerWithControls() {
    return Stack(
      children: [
        // Video player
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
        // Tap to toggle controls
        GestureDetector(
          onTap: _toggleControls,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.transparent,
          ),
        ),
        // Controls overlay
        if (_showControls) ...[
          // Top gradient
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                ),
              ),
            ),
          ),
          // Bottom controls
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                ),
              ),
              child: Column(
                children: [
                  // Seek bar (only for non-live content)
                  if (!widget.media.isLive)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            _formatPosition(_controller!.value.position),
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                activeTrackColor: const Color(0xFFE9B3FF),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: const Color(0xFFE9B3FF),
                              ),
                              child: Slider(
                                value: _controller!.value.position.inMilliseconds
                                    .toDouble()
                                    .clamp(0, _controller!.value.duration.inMilliseconds.toDouble()),
                                max: _controller!.value.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                                onChanged: (v) => _controller!.seekTo(Duration(milliseconds: v.round())),
                                onChangeEnd: (_) => _startControlsTimer(),
                              ),
                            ),
                          ),
                          Text(
                            _formatPosition(_controller!.value.duration),
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  // Control buttons row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Speed indicator
                        GestureDetector(
                          onTap: () => _showSpeedSelector(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9B3FF).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(color: Color(0xFFE9B3FF), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Skip backward
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 28),
                          onPressed: _skipBackward,
                        ),
                        // Play/Pause
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFE9B3FF).withValues(alpha: 0.2),
                          ),
                          child: IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                              color: const Color(0xFFE9B3FF),
                              size: 48,
                            ),
                            onPressed: () {
                              if (_isPlaying) {
                                _controller?.pause();
                              } else {
                                _controller?.play();
                              }
                              _startControlsTimer();
                            },
                          ),
                        ),
                        // Skip forward
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 28),
                          onPressed: _skipForward,
                        ),
                        const Spacer(),
                        // Volume
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                              onPressed: _toggleMute,
                            ),
                            SizedBox(
                              width: 80,
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                  activeTrackColor: Colors.white70,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.white,
                                ),
                                child: Slider(
                                  value: _isMuted ? 0 : _volume,
                                  max: 1.0,
                                  onChanged: _setVolume,
                                  onChangeEnd: (_) => _startControlsTimer(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Media info
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.media.isLive
                                ? Colors.red.withValues(alpha: 0.2)
                                : const Color(0xFFE9B3FF).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.media.isLive ? 'LIVE' : widget.media.group,
                            style: TextStyle(
                              color: widget.media.isLive ? Colors.red : const Color(0xFFE9B3FF),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.media.tvgName ?? widget.media.group,
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showSpeedSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Playback Speed',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((speed) {
                final isSelected = speed == _playbackSpeed;
                return ChoiceChip(
                  label: Text('${speed}x'),
                  selected: isSelected,
                  onSelected: (_) {
                    _setSpeed(speed);
                    Navigator.of(ctx).pop();
                  },
                  selectedColor: const Color(0xFFE9B3FF),
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
