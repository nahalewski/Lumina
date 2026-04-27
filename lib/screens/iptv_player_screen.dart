import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/iptv_pip_provider.dart';
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
  bool _showControls = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializePip());
  }

  void _initializePip() {
    final pip = Provider.of<IptvPipProvider>(context, listen: false);
    pip.openMedia(widget.media);
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    super.dispose();
  }

  void _enterPip() {
    final pip = Provider.of<IptvPipProvider>(context, listen: false);
    pip.enterPip();
    Navigator.of(context).pop();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
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

  void _skipForward(IptvPipProvider pip) {
    final controller = pip.controller;
    if (controller == null) return;
    final pos = controller.value.position + const Duration(seconds: 10);
    controller.seekTo(pos);
    _startControlsTimer();
  }

  void _skipBackward(IptvPipProvider pip) {
    final controller = pip.controller;
    if (controller == null) return;
    final pos = controller.value.position - const Duration(seconds: 10);
    controller.seekTo(pos < Duration.zero ? Duration.zero : pos);
    _startControlsTimer();
  }

  Future<void> _setSpeed(double speed) async {
    final pip = Provider.of<IptvPipProvider>(context, listen: false);
    await pip.setPlaybackSpeed(speed);
    _startControlsTimer();
  }

  Future<void> _setVolume(double vol) async {
    final pip = Provider.of<IptvPipProvider>(context, listen: false);
    await pip.setVolume(vol);
  }

  Future<void> _toggleMute() async {
    final pip = Provider.of<IptvPipProvider>(context, listen: false);
    await pip.setVolume(pip.isMuted ? pip.volume : 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<IptvPipProvider>(
      builder: (context, pip, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: _enterPip,
            ),
            title: Text(
              widget.media.name,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (widget.media.logo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: CachedNetworkImage(
                    imageUrl: widget.media.logo,
                    width: 32,
                    height: 32,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
          body: pip.hasError
              ? _buildErrorState(pip)
              : pip.isInitialized
                  ? _buildPlayerWithControls(pip)
                  : _buildLoadingState(pip),
        );
      },
    );
  }

  Widget _buildErrorState(IptvPipProvider pip) {
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
              pip.errorMessage,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                pip.openMedia(widget.media);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(IptvPipProvider pip) {
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

  Widget _buildPlayerWithControls(IptvPipProvider pip) {
    final controller = pip.controller!;
    return Stack(
      children: [
        // Video player
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
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
                            _formatPosition(controller.value.position),
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
                                value: controller.value.position.inMilliseconds
                                    .toDouble()
                                    .clamp(0, controller.value.duration.inMilliseconds.toDouble()),
                                max: controller.value.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                                onChanged: (v) => controller.seekTo(Duration(milliseconds: v.round())),
                                onChangeEnd: (_) => _startControlsTimer(),
                              ),
                            ),
                          ),
                          Text(
                            _formatPosition(controller.value.duration),
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
                          onTap: _showSpeedSelector,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9B3FF).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${pip.playbackSpeed}x',
                              style: const TextStyle(color: Color(0xFFE9B3FF), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Skip backward
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 28),
                          onPressed: () => _skipBackward(pip),
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
                              pip.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                              color: const Color(0xFFE9B3FF),
                              size: 48,
                            ),
                            onPressed: () {
                              pip.togglePlayPause();
                              _startControlsTimer();
                            },
                          ),
                        ),
                        // Skip forward
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 28),
                          onPressed: () => _skipForward(pip),
                        ),
                        const Spacer(),
                        // Volume
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                pip.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
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
                                  value: pip.isMuted ? 0 : pip.volume,
                                  max: 1.0,
                                  onChanged: (value) async {
                                    await _setVolume(value);
                                  },
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
            Consumer<IptvPipProvider>(
              builder: (context, pip, child) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((speed) {
                    final isSelected = speed == pip.playbackSpeed;
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
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
