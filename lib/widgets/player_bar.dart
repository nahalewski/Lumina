import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/media_provider.dart';
import '../providers/subtitle_provider.dart';
import '../models/media_model.dart';

/// Floating bottom player bar with glassmorphism design
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MediaProvider, SubtitleProvider>(
      builder: (context, mediaProvider, subtitleProvider, _) {
        final media = mediaProvider.currentMedia;
        if (media == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1C).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      // Left: Media info
                      _MediaInfo(media: media),
                      const SizedBox(width: 24),
                      // Center: Controls
                      Expanded(
                        child: _PlaybackControls(
                          mediaProvider: mediaProvider,
                          subtitleProvider: subtitleProvider,
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Right: Volume & extras
                      _ExtraControls(mediaProvider: mediaProvider),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MediaInfo extends StatelessWidget {
  final MediaFile media;

  const _MediaInfo({required this.media});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              media.isVideo ? Icons.movie_rounded : Icons.audiotrack_rounded,
              color: Colors.white.withValues(alpha: 0.4),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  media.extension.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final MediaProvider mediaProvider;
  final SubtitleProvider subtitleProvider;

  const _PlaybackControls({
    required this.mediaProvider,
    required this.subtitleProvider,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = mediaProvider.playbackState == PlaybackState.playing;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Control buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ControlButton(
              icon: Icons.shuffle_rounded,
              onPressed: () {},
            ),
            const SizedBox(width: 16),
            _ControlButton(
              icon: Icons.skip_previous_rounded,
              onPressed: mediaProvider.previous,
            ),
            const SizedBox(width: 16),
            _PlayButton(
              isPlaying: isPlaying,
              onPressed: () {
                if (isPlaying) {
                  mediaProvider.pause();
                } else {
                  mediaProvider.resume();
                }
              },
            ),
            const SizedBox(width: 16),
            _ControlButton(
              icon: Icons.skip_next_rounded,
              onPressed: mediaProvider.next,
            ),
            const SizedBox(width: 16),
            _ControlButton(
              icon: Icons.repeat_rounded,
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Progress bar
        ValueListenableBuilder<Duration>(
          valueListenable: mediaProvider.totalDuration,
          builder: (context, duration, _) => ValueListenableBuilder<Duration>(
            valueListenable: mediaProvider.currentPosition,
            builder: (context, position, _) {
              final posStr = _formatDuration(position);
              final durStr = _formatDuration(duration);
              final progress = duration.inMilliseconds > 0
                  ? position.inMilliseconds / duration.inMilliseconds
                  : 0.0;
                  
              return Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      posStr,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          onTapDown: (details) {
                            final ratio = details.localPosition.dx / constraints.maxWidth;
                            final newPosition = Duration(
                              milliseconds: (duration.inMilliseconds * ratio).round(),
                            );
                            mediaProvider.seek(newPosition);
                          },
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Stack(
                              children: [
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress.clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFAAC7FF),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(
                      durStr,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _ExtraControls extends StatelessWidget {
  final MediaProvider mediaProvider;

  const _ExtraControls({required this.mediaProvider});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _ControlButton(
            icon: Icons.closed_caption_rounded,
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          _ControlButton(
            icon: Icons.queue_music_rounded,
            onPressed: () {},
          ),
          const SizedBox(width: 16),
          Icon(
            mediaProvider.settings.isMuted
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            color: Colors.white.withValues(alpha: 0.5),
            size: 18,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: Colors.white.withValues(alpha: 0.6),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: mediaProvider.settings.volume,
                onChanged: (v) => mediaProvider.setVolume(v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _ControlButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.5),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const _PlayButton({required this.isPlaying, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(
            isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      ),
    );
  }
}
