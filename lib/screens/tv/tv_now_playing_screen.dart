import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../providers/media_provider.dart';
import '../../providers/subtitle_provider.dart';
import '../../widgets/subtitle_overlay.dart';
import '../../widgets/tv/tv_focus_wrapper.dart';

class TvNowPlayingScreen extends StatefulWidget {
  final VoidCallback onBack;

  const TvNowPlayingScreen({super.key, required this.onBack});

  @override
  State<TvNowPlayingScreen> createState() => _TvNowPlayingScreenState();
}

class _TvNowPlayingScreenState extends State<TvNowPlayingScreen> {
  bool _isControlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isControlsVisible = false);
    });
  }

  void _onActivity() {
    if (!_isControlsVisible) {
      setState(() => _isControlsVisible = true);
    }
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MediaProvider, SubtitleProvider>(
      builder: (context, mediaProvider, subtitleProvider, _) {
        final controller = mediaProvider.videoController;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Shortcuts(
            shortcuts: {
              LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
              LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
              LogicalKeySet(LogicalKeyboardKey.mediaPlayPause): const PlayPauseIntent(),
            },
            child: Actions(
              actions: {
                PlayPauseIntent: CallbackAction<PlayPauseIntent>(
                  onInvoke: (_) => _togglePlay(mediaProvider),
                ),
              },
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  _onActivity();
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.escape || 
                        event.logicalKey == LogicalKeyboardKey.backspace) {
                      widget.onBack();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Stack(
                  children: [
                    // Video Player
                    if (controller != null && controller.value.isInitialized)
                      Center(
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      )
                    else
                      const Center(child: CircularProgressIndicator()),

                    // Subtitles
                    const SubtitleOverlay(),

                    // TV Controls Overlay
                    if (_isControlsVisible) _buildTvControls(mediaProvider, subtitleProvider),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _togglePlay(MediaProvider provider) {
    if (provider.isPlaying.value) {

      provider.videoController?.pause();
    } else {
      provider.videoController?.play();
    }
    _onActivity();
  }

  Widget _buildTvControls(MediaProvider mediaProvider, SubtitleProvider subtitleProvider) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.center,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Progress Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: _TvProgressBar(mediaProvider: mediaProvider),
          ),
          const SizedBox(height: 32),
          // Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TvControlButton(
                icon: Icons.skip_previous_rounded,
                onTap: () => mediaProvider.videoController?.seekTo(Duration.zero),
              ),
              const SizedBox(width: 32),
              _TvControlButton(
                icon: Icons.replay_10_rounded,
                onTap: () => _seek(mediaProvider, -10),
              ),
              const SizedBox(width: 48),
              _TvControlButton(
                icon: mediaProvider.isPlaying.value ? Icons.pause_rounded : Icons.play_arrow_rounded,

                isLarge: true,
                onTap: () => _togglePlay(mediaProvider),
              ),
              const SizedBox(width: 48),
              _TvControlButton(
                icon: Icons.forward_10_rounded,
                onTap: () => _seek(mediaProvider, 10),
              ),
              const SizedBox(width: 32),
              _TvControlButton(
                icon: Icons.subtitles_rounded,
                onTap: () => subtitleProvider.toggleJapanese(),
                isSelected: subtitleProvider.displayOptions.showJapanese,
              ),
            ],
          ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }

  void _seek(MediaProvider provider, int seconds) {
    final controller = provider.videoController;
    if (controller == null) return;
    final newPos = controller.value.position + Duration(seconds: seconds);
    controller.seekTo(newPos);
    _onActivity();
  }
}

class _TvProgressBar extends StatelessWidget {
  final MediaProvider mediaProvider;

  const _TvProgressBar({required this.mediaProvider});

  @override
  Widget build(BuildContext context) {
    final position = mediaProvider.currentPosition.value;
    final duration = mediaProvider.totalDuration.value;
    final progress = duration.inMilliseconds > 0 
        ? position.inMilliseconds / duration.inMilliseconds 
        : 0.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatDuration(position), style: const TextStyle(color: Colors.white70, fontSize: 18)),
            Text(_formatDuration(duration), style: const TextStyle(color: Colors.white70, fontSize: 18)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Color(0xFFE9B3FF)),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _TvControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isLarge;
  final bool isSelected;

  const _TvControlButton({
    required this.icon,
    required this.onTap,
    this.isLarge = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusWrapper(
      onTap: onTap,
      scaleFactor: 1.2,
      child: Container(
        width: isLarge ? 80 : 64,
        height: isLarge ? 80 : 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected 
              ? const Color(0xFFE9B3FF).withValues(alpha: 0.3) 
              : Colors.white.withValues(alpha: 0.1),
        ),
        child: Icon(
          icon,
          size: isLarge ? 48 : 32,
          color: isSelected ? const Color(0xFFE9B3FF) : Colors.white,
        ),
      ),
    );
  }
}

class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}
