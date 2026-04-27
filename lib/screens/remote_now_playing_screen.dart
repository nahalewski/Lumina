import 'dart:async';

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
    _hideTimer = Timer(const Duration(seconds: 3), () {
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
              'No media selected',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

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
                  _RemotePlayerChrome(
                    title: media.title,
                    controller: controller,
                    onBack: widget.onBack,
                    onPlayPause: provider.togglePlayPause,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RemotePlayerChrome extends StatelessWidget {
  final String title;
  final VideoPlayerController? controller;
  final VoidCallback? onBack;
  final Future<void> Function() onPlayPause;

  const _RemotePlayerChrome({
    required this.title,
    required this.controller,
    required this.onBack,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<RemoteMediaProvider>(context, listen: false);
    final initialized = controller != null && controller!.value.isInitialized;
    final isPlaying = initialized && controller!.value.isPlaying;

    return Stack(
      children: [
        // Top Bar
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: onBack,
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.airplay_rounded, color: Colors.white70),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Searching for AirPlay devices...'),
                            backgroundColor: Color(0xFF0A84FF),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.cast_rounded, color: Colors.white70),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Searching for Casting devices...'),
                            backgroundColor: Color(0xFFE9B3FF),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded, color: Colors.white70),
                      onPressed: () => _showOptions(context, provider),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Middle Seek/Play Controls
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 42),
                onPressed: initialized ? () {
                  final newPos = controller!.value.position - const Duration(seconds: 10);
                  controller!.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
                } : null,
              ),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFE9B3FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.all(20),
                ),
                icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                iconSize: 48,
                onPressed: initialized ? onPlayPause : null,
              ),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 42),
                onPressed: initialized ? () {
                  final newPos = controller!.value.position + const Duration(seconds: 10);
                  controller!.seekTo(newPos);
                } : null,
              ),
            ],
          ),
        ),

        // Bottom Bar
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (initialized)
                    Column(
                      children: [
                        VideoProgressIndicator(
                          controller!,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Color(0xFFE9B3FF),
                            bufferedColor: Colors.white30,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(controller!.value.position),
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                            Text(
                              _formatDuration(controller!.value.duration),
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => provider.stopPlayback(),
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('STOP'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                          foregroundColor: Colors.redAccent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? "$hours:$minutes:$seconds" : "$minutes:$seconds";
  }

  void _showOptions(BuildContext context, RemoteMediaProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Playback Options',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.high_quality_rounded, color: Color(0xFFAAC7FF)),
              title: const Text('Quality', style: TextStyle(color: Colors.white)),
              trailing: const Text('Original (Auto)', style: TextStyle(color: Colors.white38)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Quality is currently locked to Original Source')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded, color: Color(0xFFAAC7FF)),
              title: const Text('Playback Speed', style: TextStyle(color: Colors.white)),
              trailing: Text('${provider.controller?.value.playbackSpeed ?? 1.0}x', style: const TextStyle(color: Color(0xFFE9B3FF))),
              onTap: () => _showSpeedDialog(context, provider),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showSpeedDialog(BuildContext context, RemoteMediaProvider provider) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Playback Speed', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
            return RadioListTile<double>(
              title: Text('${speed}x', style: const TextStyle(color: Colors.white)),
              value: speed,
              groupValue: provider.controller?.value.playbackSpeed ?? 1.0,
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
