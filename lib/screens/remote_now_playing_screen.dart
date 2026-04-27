import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../providers/remote_media_provider.dart';

class RemoteNowPlayingScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const RemoteNowPlayingScreen({super.key, this.onBack});

  @override
  State<RemoteNowPlayingScreen> createState() => _RemoteNowPlayingScreenState();
}

class _RemoteNowPlayingScreenState extends State<RemoteNowPlayingScreen> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RemoteMediaProvider>(
      builder: (context, provider, _) {
        final media = provider.currentMedia;
        final controller = provider.controller;

        if (media == null) {
          return const Center(
            child: Text(
              'Nothing is playing',
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
          );
        }

        // Music player mode
        if (media.isAudio) {
          return _MusicPlayerView(
            media: media,
            controller: controller,
            provider: provider,
            onBack: widget.onBack,
          );
        }

        // Video player mode
        return GestureDetector(
          onTap: _showControls,
          child: Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null && controller.value.isInitialized)
                  Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  )
                else
                  const SizedBox.expand(),
                if (provider.isPreparingPlayback)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFFE9B3FF)),
                        SizedBox(height: 16),
                        Text('Opening video...',
                            style: TextStyle(color: Colors.white60)),
                      ],
                    ),
                  ),
                if (provider.playbackError != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.redAccent, size: 52),
                          const SizedBox(height: 12),
                          const Text('Could not start playback',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(
                            provider.playbackError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_controlsVisible)
                  _VideoChrome(
                    media: media,
                    controller: controller,
                    provider: provider,
                    onBack: widget.onBack,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Music Player ─────────────────────────────────────────────────────────────

class _MusicPlayerView extends StatefulWidget {
  final RemoteMediaFile media;
  final VideoPlayerController? controller;
  final RemoteMediaProvider provider;
  final VoidCallback? onBack;

  const _MusicPlayerView({
    required this.media,
    required this.controller,
    required this.provider,
    required this.onBack,
  });

  @override
  State<_MusicPlayerView> createState() => _MusicPlayerViewState();
}

class _MusicPlayerViewState extends State<_MusicPlayerView> {
  Timer? _posTimer;

  @override
  void initState() {
    super.initState();
    _posTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _posTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final initialized = ctrl != null && ctrl.value.isInitialized;
    final isPlaying = initialized && ctrl.value.isPlaying;
    final position = initialized ? ctrl.value.position : Duration.zero;
    final duration = initialized ? ctrl.value.duration : Duration.zero;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final art = widget.media.coverArtUrl?.isNotEmpty == true
        ? widget.media.coverArtUrl
        : widget.media.posterUrl;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF0D0D14)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white70, size: 28),
                    onPressed: widget.onBack,
                  ),
                  const Expanded(
                    child: Text(
                      'NOW PLAYING',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded,
                        color: Colors.white70),
                    onPressed: () => _showOptions(context),
                  ),
                ],
              ),
            ),

            // Album art
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: art != null
                          ? CachedNetworkImage(
                              imageUrl: art,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  _artPlaceholder(),
                            )
                          : _artPlaceholder(),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Track info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.media.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.media.artist ?? 'Unknown Artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 14),
                  ),
                  if (widget.media.album != null)
                    Text(
                      widget.media.album!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 12),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: const Color(0xFFE9B3FF),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: initialized
                          ? (v) => ctrl.seekTo(Duration(
                                milliseconds:
                                    (v * duration.inMilliseconds).round(),
                              ))
                          : null,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(position),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                      Text(_fmt(duration),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded,
                      color: Colors.white, size: 36),
                  onPressed: () => widget.provider.skipPrevious(),
                ),
                IconButton(
                  icon: const Icon(Icons.replay_10_rounded,
                      color: Colors.white70, size: 28),
                  onPressed: initialized
                      ? () {
                          final np = position - const Duration(seconds: 10);
                          ctrl.seekTo(
                              np < Duration.zero ? Duration.zero : np);
                        }
                      : null,
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE9B3FF),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 36,
                    ),
                    onPressed: initialized
                        ? () => widget.provider.togglePlayPause()
                        : null,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10_rounded,
                      color: Colors.white70, size: 28),
                  onPressed: initialized
                      ? () => ctrl.seekTo(
                          position + const Duration(seconds: 10))
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded,
                      color: Colors.white, size: 36),
                  onPressed: () => widget.provider.skipNext(),
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _artPlaceholder() => Container(
        color: const Color(0xFF1E1E22),
        child: const Icon(Icons.audiotrack_rounded,
            color: Colors.white12, size: 80),
      );

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E22),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Playback Options',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading:
                  const Icon(Icons.speed_rounded, color: Color(0xFFAAC7FF)),
              title: const Text('Playback Speed',
                  style: TextStyle(color: Colors.white)),
              trailing: Text(
                '${widget.controller?.value.playbackSpeed ?? 1.0}x',
                style: const TextStyle(color: Color(0xFFE9B3FF)),
              ),
              onTap: () {
                Navigator.pop(context);
                _showSpeedSheet(context);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.stop_rounded, color: Colors.redAccent),
              title: const Text('Stop Playback',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                widget.provider.stopPlayback();
                widget.onBack?.call();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSpeedSheet(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Playback Speed',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
            return RadioListTile<double>(
              title: Text('${speed}x',
                  style: const TextStyle(color: Colors.white)),
              value: speed,
              groupValue:
                  widget.controller?.value.playbackSpeed ?? 1.0,
              onChanged: (val) {
                if (val != null) widget.provider.setPlaybackSpeed(val);
                Navigator.pop(context);
              },
              activeColor: const Color(0xFFE9B3FF),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Video Player Chrome ───────────────────────────────────────────────────────

class _VideoChrome extends StatelessWidget {
  final RemoteMediaFile media;
  final VideoPlayerController? controller;
  final RemoteMediaProvider provider;
  final VoidCallback? onBack;

  const _VideoChrome({
    required this.media,
    required this.controller,
    required this.provider,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final initialized = controller != null && controller!.value.isInitialized;
    final isPlaying = initialized && controller!.value.isPlaying;

    return Stack(
      children: [
        // Top bar
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: onBack,
                    ),
                    Expanded(
                      child: Text(
                        media.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded,
                          color: Colors.white70),
                      onPressed: () => _showOptions(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Center controls
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded,
                    color: Colors.white, size: 36),
                onPressed: () => provider.skipPrevious(),
              ),
              IconButton(
                icon: const Icon(Icons.replay_10_rounded,
                    color: Colors.white, size: 40),
                onPressed: initialized
                    ? () {
                        final np = controller!.value.position -
                            const Duration(seconds: 10);
                        controller!.seekTo(
                            np < Duration.zero ? Duration.zero : np);
                      }
                    : null,
              ),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFE9B3FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.all(18),
                ),
                icon: Icon(isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
                iconSize: 44,
                onPressed: initialized ? provider.togglePlayPause : null,
              ),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded,
                    color: Colors.white, size: 40),
                onPressed: initialized
                    ? () => controller!.seekTo(controller!.value.position +
                        const Duration(seconds: 10))
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded,
                    color: Colors.white, size: 36),
                onPressed: () => provider.skipNext(),
              ),
            ],
          ),
        ),

        // Bottom bar
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (initialized) ...[
                    VideoProgressIndicator(
                      controller!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFFE9B3FF),
                        bufferedColor: Colors.white30,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmt(controller!.value.position),
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11),
                        ),
                        Text(
                          _fmt(controller!.value.duration),
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => provider.stopPlayback(),
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('STOP'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.redAccent.withValues(alpha: 0.2),
                          foregroundColor: Colors.redAccent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E22),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Playback Options',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading:
                  const Icon(Icons.speed_rounded, color: Color(0xFFAAC7FF)),
              title: const Text('Playback Speed',
                  style: TextStyle(color: Colors.white)),
              trailing: Text(
                '${controller?.value.playbackSpeed ?? 1.0}x',
                style: const TextStyle(color: Color(0xFFE9B3FF)),
              ),
              onTap: () => _showSpeedDialog(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSpeedDialog(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Playback Speed',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
            return RadioListTile<double>(
              title: Text('${speed}x',
                  style: const TextStyle(color: Colors.white)),
              value: speed,
              groupValue: controller?.value.playbackSpeed ?? 1.0,
              onChanged: (val) {
                if (val != null) provider.setPlaybackSpeed(val);
                Navigator.pop(context);
              },
              activeColor: const Color(0xFFE9B3FF),
            );
          }).toList(),
        ),
      ),
    );
  }
}
