import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/media_provider.dart';
import '../providers/subtitle_provider.dart';
import '../models/media_model.dart';
import '../models/subtitle_model.dart';
import '../widgets/subtitle_overlay.dart';
import '../services/platform_channel_service.dart';

/// Now Playing screen - video player with subtitle overlay
/// Uses video_player package for in-app video rendering
class NowPlayingScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const NowPlayingScreen({super.key, this.onBack});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _showSubtitleSettings = false;
  bool _showSubtitleSearch = false;
  bool _showDebugPanel = false;
  bool _learningMode = false;
  bool _isControlsVisible = true;
  Timer? _controlsTimer;
  bool _isFullscreen = false;
  bool _showSpeedSelector = false;
  bool _showQueue = false;
  final FocusNode _focusNode = FocusNode();


  @override
  void initState() {
    super.initState();
    final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
    final subtitleProvider = Provider.of<SubtitleProvider>(context, listen: false);
    
    if (mediaProvider.videoController == null && mediaProvider.currentMedia != null) {
      mediaProvider.initController(mediaProvider.currentMedia!.filePath, subtitleProvider: subtitleProvider);
    } else if (mediaProvider.videoController != null) {
      mediaProvider.syncSubtitleProvider(subtitleProvider);
    }

    if (mediaProvider.currentMedia != null) {
      subtitleProvider.loadSubtitlesForVideo(mediaProvider.currentMedia!.filePath).then((_) {
        if (subtitleProvider.subtitles.isEmpty && !subtitleProvider.isProcessing) {
          _startTranscription(mediaProvider.currentMedia!.filePath);
        }
      });
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _showControls() {
    setState(() => _isControlsVisible = true);
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isControlsVisible = false);
    });
  }

  void _togglePlayPause() {
    final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
    final controller = mediaProvider.videoController;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    _showControls();
  }

  void _seekForward() {
    final controller = Provider.of<MediaProvider>(context, listen: false).videoController;
    if (controller == null) return;
    final newPos = controller.value.position + const Duration(seconds: 10);
    controller.seekTo(newPos);
    _showControls();
  }

  void _seekBackward() {
    final controller = Provider.of<MediaProvider>(context, listen: false).videoController;
    if (controller == null) return;
    final newPos = controller.value.position - const Duration(seconds: 10);
    controller.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
    _showControls();
  }

  void _seekTo(double ms) {
    final controller = Provider.of<MediaProvider>(context, listen: false).videoController;
    if (controller == null) return;
    controller.seekTo(Duration(milliseconds: ms.round()));
  }

  void _toggleFullscreen() {
    final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    mediaProvider.toggleFullscreen();
    
    if (Platform.isMacOS) {
      PlatformChannelService().toggleFullscreen();
    }
    
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _startTranscription(String videoPath) {
    final provider = Provider.of<SubtitleProvider>(context, listen: false);
    final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
    
    provider.processVideoPreprocessed(
      videoPath,
      useOllama: mediaProvider.settings.useOllamaTranslation,
      ollamaModel: mediaProvider.settings.ollamaModel,
      translationProfile: mediaProvider.settings.translationProfile,
    ).catchError((e) {
      debugPrint('Transcription error: $e');
    });
  }

  /// Keyboard shortcuts handler (#1)
  void _handleKeyEvent(LogicalKeyboardKey key, MediaProvider mediaProvider, SubtitleProvider subtitleProvider) {
    final controller = mediaProvider.videoController;
    if (controller == null) return;

    switch (key) {
      case LogicalKeyboardKey.space:
        _togglePlayPause();
      case LogicalKeyboardKey.arrowLeft:
        _seekBackward();
      case LogicalKeyboardKey.arrowRight:
        _seekForward();
      case LogicalKeyboardKey.arrowUp:
        mediaProvider.setVolume((mediaProvider.volume.value + 0.1).clamp(0.0, 1.0));
      case LogicalKeyboardKey.arrowDown:
        mediaProvider.setVolume((mediaProvider.volume.value - 0.1).clamp(0.0, 1.0));
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
      case LogicalKeyboardKey.escape:
        if (_isFullscreen) _toggleFullscreen();
      case LogicalKeyboardKey.keyM:
        mediaProvider.toggleMute();
      case LogicalKeyboardKey.keyJ:
        subtitleProvider.toggleJapanese();
      case LogicalKeyboardKey.keyE:
        subtitleProvider.toggleEnglish();
      case LogicalKeyboardKey.keyR:
        subtitleProvider.toggleABRepeat();
      case LogicalKeyboardKey.comma:
        mediaProvider.setPlaybackSpeed((mediaProvider.settings.playbackSpeed - 0.25).clamp(0.25, 2.0));
      case LogicalKeyboardKey.period:
        mediaProvider.setPlaybackSpeed((mediaProvider.settings.playbackSpeed + 0.25).clamp(0.25, 2.0));
      case LogicalKeyboardKey.digit0:
        controller.seekTo(Duration.zero);
      case LogicalKeyboardKey.digit1:
        controller.seekTo(mediaProvider.totalDuration.value * 0.1);
      case LogicalKeyboardKey.digit2:
        controller.seekTo(mediaProvider.totalDuration.value * 0.2);
      case LogicalKeyboardKey.digit3:
        controller.seekTo(mediaProvider.totalDuration.value * 0.3);
      case LogicalKeyboardKey.digit4:
        controller.seekTo(mediaProvider.totalDuration.value * 0.4);
      case LogicalKeyboardKey.digit5:
        controller.seekTo(mediaProvider.totalDuration.value * 0.5);
      case LogicalKeyboardKey.digit6:
        controller.seekTo(mediaProvider.totalDuration.value * 0.6);
      case LogicalKeyboardKey.digit7:
        controller.seekTo(mediaProvider.totalDuration.value * 0.7);
      case LogicalKeyboardKey.digit8:
        controller.seekTo(mediaProvider.totalDuration.value * 0.8);
      case LogicalKeyboardKey.digit9:
        controller.seekTo(mediaProvider.totalDuration.value * 0.9);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, mediaProvider, _) {
        if (mediaProvider.currentMedia == null) {
          return const Center(child: Text('No media selected', style: TextStyle(color: Colors.white70)));
        }

        final media = mediaProvider.currentMedia!;
        final controller = mediaProvider.videoController;
        final provider = Provider.of<SubtitleProvider>(context);

        if (mediaProvider.playerError) {
          return _buildErrorState(media, mediaProvider.errorMessage);
        }

        return KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is KeyDownEvent) {
              _handleKeyEvent(event.logicalKey, mediaProvider, provider);
            }
          },


          child: GestureDetector(
            onTap: _showControls,
            onDoubleTap: _toggleFullscreen,
            child: Stack(
              children: [
                if (controller != null && controller.value.isInitialized)
                  Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  )
                else
                  Container(color: Colors.black),

                if (mediaProvider.playbackState == PlaybackState.loading)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(color: Color(0xFFAAC7FF), strokeWidth: 3),
                        ),
                        const SizedBox(height: 16),
                        Text('Opening video...', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
                      ],
                    ),
                  ),
                  
                if (_learningMode)
                  const LearningSubtitleOverlay()
                else
                  const SubtitleOverlay(),

                const VocabularyMatchOverlay(),

                if (_isControlsVisible) ...[
                  _TopControls(
                    media: media,
                    provider: provider,
                    isFullscreen: _isFullscreen,
                    onBack: widget.onBack ?? () {},
                    onToggleSubtitleSettings: () {
                      setState(() => _showSubtitleSettings = !_showSubtitleSettings);
                    },
                    onToggleLearningMode: () {
                      setState(() => _learningMode = !_learningMode);
                    },
                    onToggleDebug: () {
                      setState(() => _showDebugPanel = !_showDebugPanel);
                    },
                    onToggleFullscreen: _toggleFullscreen,
                    onToggleQueue: () {
                      setState(() => _showQueue = !_showQueue);
                    },
                  ),

                  _BottomControls(
                    currentPosition: mediaProvider.currentPosition,
                    totalDuration: mediaProvider.totalDuration,
                    isPlaying: mediaProvider.isPlaying, 
                    onPlayPause: _togglePlayPause,
                    onSeekForward: _seekForward,
                    onSeekBackward: _seekBackward,
                    onSeek: _seekTo,
                    volume: mediaProvider.volume,
                    onVolumeChanged: (v) => mediaProvider.setVolume(v),
                    playbackSpeed: mediaProvider.settings.playbackSpeed,
                    onSpeedChanged: (speed) => mediaProvider.setPlaybackSpeed(speed),
                    showSpeedSelector: _showSpeedSelector,
                    onToggleSpeedSelector: () => setState(() => _showSpeedSelector = !_showSpeedSelector),
                    onToggleABRepeat: () => provider.toggleABRepeat(),
                    isABRepeatEnabled: provider.isABRepeatEnabled,
                  ),
                ],

                if (_showSubtitleSettings)
                  _SubtitleSettingsPanel(
                    provider: provider,
                    onClose: () => setState(() => _showSubtitleSettings = false),
                    onOpenDebug: () {
                      setState(() {
                        _showSubtitleSettings = false;
                        _showDebugPanel = true;
                      });
                    },
                    onOpenSearch: () {
                      setState(() {
                        _showSubtitleSettings = false;
                        _showSubtitleSearch = true;
                      });
                    },
                  ),

                if (_showSubtitleSearch)
                  _SubtitleSearchPanel(
                    provider: provider,
                    onClose: () => setState(() => _showSubtitleSearch = false),
                    onSeekTo: (entry) {
                      final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
                      mediaProvider.videoController?.seekTo(entry.startTime);
                      provider.seekToSubtitle(entry);
                      setState(() => _showSubtitleSearch = false);
                    },
                  ),

                if (_showDebugPanel)
                  _DebugPanel(
                    provider: provider,
                    onClose: () => setState(() => _showDebugPanel = false),
                  ),


                if (provider.isProcessing)
                  _ProcessingBanner(
                    status: provider.processingStatus,
                    mode: provider.mode,
                    onTap: () => setState(() => _showDebugPanel = true),
                  ),

                if (_showQueue)
                  _QueuePanel(
                    mediaProvider: mediaProvider,
                    onClose: () => setState(() => _showQueue = false),
                    onSelectMedia: (media) {
                      mediaProvider.playMedia(media);
                      setState(() => _showQueue = false);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(MediaFile media, String errorMessage) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: Colors.red.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(
              'Video Player Error',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                errorMessage,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Media: ${media.title}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back to Library'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A84FF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugPanel extends StatelessWidget {
  final SubtitleProvider provider;
  final VoidCallback onClose;

  const _DebugPanel({required this.provider, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Consumer<SubtitleProvider>(
      builder: (context, provider, _) {
        final logs = provider.debugLogs;
        final lastLog = logs.isNotEmpty ? logs.first : '—';
        final errorCount = logs.where((l) => l.contains('ERROR') || l.contains('error')).length;
        final subtitleCount = provider.subtitles.length;
        final isProcessing = provider.isProcessing;
        final status = provider.processingStatus;

        String stage = 'Idle';
        Color stageColor = Colors.white38;
        if (isProcessing) {
          if (status.contains('Extracting') || status.contains('extract')) { stage = '1 / 4  Audio Extraction'; stageColor = const Color(0xFFFFD60A); }
          else if (status.contains('Isolating') || status.contains('FFmpeg')) { stage = '2 / 4  Vocal Isolation'; stageColor = const Color(0xFFFFD60A); }
          else if (status.contains('Transcrib') || status.contains('%')) { stage = '3 / 4  Whisper Transcription'; stageColor = const Color(0xFFAAC7FF); }
          else if (status.contains('Translat')) { stage = '4 / 4  Qwen Translation'; stageColor = const Color(0xFF9DFF9D); }
          else { stage = 'Processing…'; stageColor = const Color(0xFFAAC7FF); }
        } else if (subtitleCount > 0) {
          stage = '✓  Done';
          stageColor = const Color(0xFF42E355);
        }

        final pctMatch = RegExp(r'(\d+)%').firstMatch(status);
        final pct = pctMatch != null ? int.tryParse(pctMatch.group(1)!) : null;

        final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
        final contentType = mediaProvider.currentMedia?.contentType ?? ContentType.general;
        final typeLabel = contentType.name.toUpperCase();
        final typeIcon = contentType == ContentType.anime ? '🌸' : (contentType == ContentType.adult ? '🔞' : '📄');
        final typeColor = contentType == ContentType.adult ? Colors.redAccent : (contentType == ContentType.anime ? const Color(0xFFE9B3FF) : Colors.white60);

        return Positioned(
          top: 56,
          right: 12,
          child: Container(
            width: 320,
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E10).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFAAC7FF).withValues(alpha: 0.25)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bug_report_rounded, color: Color(0xFFAAC7FF), size: 17),
                      const SizedBox(width: 8),
                      const Text('Engine Debug', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Text(typeIcon, style: const TextStyle(fontSize: 10)),
                            const SizedBox(width: 4),
                            Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          final allLogs = logs.join('\n');
                          Clipboard.setData(ClipboardData(text: allLogs));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Logs copied'), duration: Duration(seconds: 2)),
                          );
                        },
                        child: const Icon(Icons.copy_rounded, color: Colors.white38, size: 16),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(onTap: onClose, child: const Icon(Icons.close_rounded, color: Colors.white38, size: 18)),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DebugCard(
                        icon: Icons.timeline_rounded,
                        label: 'Pipeline Stage',
                        value: stage,
                        valueColor: stageColor,
                      ),
                      const SizedBox(height: 6),
                      if (isProcessing && pct != null) ...[
                        Row(
                          children: [
                            const SizedBox(width: 4),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct / 100.0,
                                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFAAC7FF)),
                                  minHeight: 5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('$pct%', style: const TextStyle(color: Color(0xFFAAC7FF), fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (isProcessing && pct == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFAAC7FF)),
                              minHeight: 5,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(child: _DebugCard(icon: Icons.subtitles_rounded, label: 'Subtitles', value: '$subtitleCount loaded')),
                          const SizedBox(width: 6),
                          Expanded(child: _DebugCard(
                            icon: Icons.warning_amber_rounded,
                            label: 'Errors',
                            value: '$errorCount',
                            valueColor: errorCount > 0 ? Colors.redAccent : const Color(0xFF42E355),
                          )),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _DebugCard(
                        icon: provider.mode == SubtitleMode.live ? Icons.mic_rounded : Icons.video_file_rounded,
                        label: 'Mode',
                        value: provider.mode == SubtitleMode.live ? 'Live Mic' : 'Preprocessed (Whisper Large-v3)',
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Last Status', style: TextStyle(color: Colors.white38, fontSize: 10)),
                            const SizedBox(height: 3),
                            Text(
                              status.isNotEmpty ? status : '—',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('Recent Logs', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Container(
                        height: 140,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: logs.length > 12 ? 12 : logs.length,
                          itemBuilder: (context, i) {
                            final log = logs[i];
                            final isErr = log.contains('ERROR') || log.contains('error');
                            final isWarn = log.contains('WARNING') || log.contains('warn');
                            Color logColor = Colors.white54;
                            if (isErr) logColor = Colors.redAccent;
                            if (isWarn) logColor = const Color(0xFFFFD60A);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(log, style: TextStyle(color: logColor, fontSize: 10, fontFamily: 'monospace'), maxLines: 2, overflow: TextOverflow.ellipsis),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DebugCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DebugCard({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white38),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 0.3)),
              Text(value, style: TextStyle(color: valueColor ?? Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopControls extends StatelessWidget {
  final MediaFile media;
  final SubtitleProvider provider;
  final bool isFullscreen;
  final VoidCallback onBack;
  final VoidCallback onToggleSubtitleSettings;
  final VoidCallback onToggleLearningMode;
  final VoidCallback onToggleDebug;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleQueue;

  const _TopControls({
    required this.media,
    required this.provider,
    required this.isFullscreen,
    required this.onBack,
    required this.onToggleSubtitleSettings,
    required this.onToggleLearningMode,
    required this.onToggleDebug,
    required this.onToggleFullscreen,
    required this.onToggleQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 24,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                media.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (provider.mode == SubtitleMode.live)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF42E355).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF42E355).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record_rounded, color: Color(0xFF42E355), size: 8),
                    SizedBox(width: 6),
                    Text('LIVE', style: TextStyle(color: Color(0xFF42E355), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  ],
                ),
              ),
            const SizedBox(width: 4),
            Consumer<MediaProvider>(
              builder: (context, mediaProvider, _) {
                final isAdult = mediaProvider.settings.translationProfile == TranslationProfile.adult;
                return Tooltip(
                  message: isAdult ? 'Adult Mode (Adult translations)' : 'Anime Mode (Standard translations)',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final newProfile = isAdult ? TranslationProfile.standard : TranslationProfile.adult;
                        mediaProvider.setTranslationProfile(newProfile);
                        if (mediaProvider.currentMedia != null) {
                          mediaProvider.currentMedia!.contentType = 
                              newProfile == TranslationProfile.adult ? ContentType.adult : ContentType.anime;
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: isAdult
                            ? BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                              )
                            : BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                              ),
                        child: Text(
                          isAdult ? '🔞' : '🌸',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
            _IconButton(
              icon: Icons.queue_music_rounded,
              tooltip: 'Playback Queue',
              onPressed: onToggleQueue,
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: provider.displayOptions.showJapanese ? 'Hide Japanese' : 'Show Japanese',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => provider.toggleJapanese(),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: provider.displayOptions.showJapanese
                        ? BoxDecoration(
                            color: const Color(0xFFE9B3FF).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE9B3FF).withValues(alpha: 0.5)),
                          )
                        : null,
                    child: Text(
                      'あ',
                      style: TextStyle(
                        fontSize: 17,
                        color: provider.displayOptions.showJapanese
                            ? const Color(0xFFE9B3FF)
                            : Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _IconButton(
              icon: isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              tooltip: isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
              onPressed: onToggleFullscreen,
            ),
            const SizedBox(width: 4),
            _IconButton(
              icon: Icons.bug_report_rounded,
              tooltip: 'Engine Debug',
              onPressed: onToggleDebug,
            ),
            const SizedBox(width: 4),
            _IconButton(
              icon: Icons.closed_caption_rounded,
              tooltip: 'Subtitle Settings',
              onPressed: onToggleSubtitleSettings,
            ),
            const SizedBox(width: 4),
            _IconButton(
              icon: Icons.airplay_rounded,
              tooltip: 'AirPlay',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Searching for AirPlay devices...'),
                    backgroundColor: Color(0xFF0A84FF),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
            _IconButton(
              icon: Icons.cast_rounded,
              tooltip: 'Cast to Device',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Searching for Casting devices...'),
                    backgroundColor: Color(0xFFE9B3FF),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  final ValueListenable<Duration> currentPosition;
  final ValueListenable<Duration> totalDuration;
  final ValueListenable<bool> isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekForward;
  final VoidCallback onSeekBackward;
  final ValueChanged<double> onSeek;
  final ValueListenable<double> volume;
  final ValueChanged<double> onVolumeChanged;
  final double playbackSpeed;
  final ValueChanged<double> onSpeedChanged;
  final bool showSpeedSelector;
  final VoidCallback onToggleSpeedSelector;
  final VoidCallback onToggleABRepeat;
  final bool isABRepeatEnabled;

  const _BottomControls({
    required this.currentPosition,
    required this.totalDuration,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSeekForward,
    required this.onSeekBackward,
    required this.onSeek,
    required this.volume,
    required this.onVolumeChanged,
    required this.playbackSpeed,
    required this.onSpeedChanged,
    required this.showSpeedSelector,
    required this.onToggleSpeedSelector,
    required this.onToggleABRepeat,
    required this.isABRepeatEnabled,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static const List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.7),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Speed selector popup
            if (showSpeedSelector)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F21).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _speedOptions.map((speed) {
                    final isSelected = (speed - playbackSpeed).abs() < 0.01;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onSpeedChanged(speed),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF0A84FF).withValues(alpha: 0.3) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${speed}x',
                              style: TextStyle(
                                color: isSelected ? const Color(0xFFAAC7FF) : Colors.white.withValues(alpha: 0.6),
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Seek bar
            Row(
              children: [
                ValueListenableBuilder<Duration>(
                  valueListenable: currentPosition,
                  builder: (context, pos, _) => Text(
                    _formatDuration(pos),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: const Color(0xFF0A84FF),
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                      thumbColor: Colors.white,
                    ),
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: totalDuration,
                      builder: (context, total, _) => ValueListenableBuilder<Duration>(
                        valueListenable: currentPosition,
                        builder: (context, pos, _) => Slider(
                          value: pos.inMilliseconds.toDouble().clamp(0, total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1),
                          max: total.inMilliseconds.toDouble() > 0 ? total.inMilliseconds.toDouble() : 1,
                          onChanged: onSeek,
                        ),
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<Duration>(
                  valueListenable: totalDuration,
                  builder: (context, total, _) => Text(
                    _formatDuration(total),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // A-B Repeat button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onToggleABRepeat,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isABRepeatEnabled
                                ? const Color(0xFF0A84FF).withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.repeat_one_rounded,
                            color: isABRepeatEnabled ? const Color(0xFF0A84FF) : Colors.white.withValues(alpha: 0.5),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    _ControlButton(
                      icon: Icons.skip_previous_rounded,
                      size: 28,
                      onPressed: onSeekBackward,
                    ),
                    const SizedBox(width: 24),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onPlayPause,
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: ValueListenableBuilder<bool>(
                            valueListenable: isPlaying,
                            builder: (context, playing, _) => Icon(
                              playing
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    _ControlButton(
                      icon: Icons.skip_next_rounded,
                      size: 28,
                      onPressed: onSeekForward,
                    ),
                    const SizedBox(width: 16),
                    // Speed button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onToggleSpeedSelector,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: showSpeedSelector
                                ? const Color(0xFF0A84FF).withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${playbackSpeed}x',
                            style: TextStyle(
                              color: showSpeedSelector ? const Color(0xFFAAC7FF) : Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.volume_up_rounded, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                      SizedBox(
                        width: 100,
                        child: ValueListenableBuilder<double>(
                          valueListenable: volume,
                          builder: (context, v, _) => Slider(
                            value: v,
                            onChanged: onVolumeChanged,
                            activeColor: Colors.white.withValues(alpha: 0.6),
                            inactiveColor: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.7),
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.onPressed,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.7),
            size: size,
          ),
        ),
      ),
    );
  }
}

class _SubtitleSettingsPanel extends StatelessWidget {
  final SubtitleProvider provider;
  final VoidCallback onClose;
  final VoidCallback onOpenDebug;
  final VoidCallback onOpenSearch;

  const _SubtitleSettingsPanel({
    required this.provider,
    required this.onClose,
    required this.onOpenDebug,
    required this.onOpenSearch,
  });


  @override
  Widget build(BuildContext context) {
    return Consumer<SubtitleProvider>(
      builder: (context, provider, _) {
        return Positioned(
          top: 64,
          right: 16,
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1F1F21).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Subtitle Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Manrope',
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onClose,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.5),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ToggleRow(
                  label: 'English Subtitles',
                  value: provider.displayOptions.showEnglish,
                  onChanged: (_) => provider.toggleEnglish(),
                ),
                _buildHelpText('Display AI-translated English text.'),
                const SizedBox(height: 8),
                _ToggleRow(
                  label: 'Japanese (Original)',
                  value: provider.displayOptions.showJapanese,
                  onChanged: (_) => provider.toggleJapanese(),
                ),
                _buildHelpText('Display the original Japanese text transcribed from audio.'),
                const SizedBox(height: 16),
                const Text(
                  'Subtitle Delay',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Row(
                  children: [
                    Text(
                      '${provider.displayOptions.delaySeconds.toStringAsFixed(1)}s',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: provider.displayOptions.delaySeconds,
                        min: 0,
                        max: 3,
                        divisions: 30,
                        activeColor: const Color(0xFFAAC7FF),
                        inactiveColor: Colors.white.withValues(alpha: 0.1),
                        onChanged: (v) => provider.updateDelay(v),
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Font Size',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Row(
                  children: [
                    Text(
                      '${provider.displayOptions.fontSize.round()}px',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: provider.displayOptions.fontSize,
                        min: 12,
                        max: 48,
                        divisions: 36,
                        activeColor: const Color(0xFFAAC7FF),
                        inactiveColor: Colors.white.withValues(alpha: 0.1),
                        onChanged: (v) => provider.updateFontSize(v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Vertical Position',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Row(
                  children: [
                    Text(
                      '${provider.displayOptions.verticalOffset.round()}px',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: provider.displayOptions.verticalOffset,
                        min: 40,
                        max: 400,
                        divisions: 36,
                        activeColor: const Color(0xFFAAC7FF),
                        inactiveColor: Colors.white.withValues(alpha: 0.1),
                        onChanged: (v) => provider.updateVerticalOffset(v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      Provider.of<MediaProvider>(context, listen: false).pickSubtitleFile();
                    },
                    icon: const Icon(Icons.file_upload_rounded, size: 16),
                    label: const Text('Import External SRT'),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      foregroundColor: const Color(0xFFAAC7FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => provider.exportSrt(),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Export Current SRT'),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFE9B3FF).withValues(alpha: 0.1),
                      foregroundColor: const Color(0xFFE9B3FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: provider.isProcessing
                        ? null
                        : () {
                            final media = Provider.of<MediaProvider>(context, listen: false).currentMedia;
                            if (media != null) {
                              provider.processVideoPreprocessed(media.filePath);
                            }
                          },
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF0A84FF).withValues(alpha: 0.2),
                      foregroundColor: const Color(0xFFAAC7FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Generate Subtitles (Preprocessed)'),
                  ),
                ),
                _buildHelpText('Transcribe the entire video at once for full navigation and high accuracy.'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: provider.isProcessing
                        ? provider.stopLiveTranscription
                        : provider.startLiveTranscription,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF42E355).withValues(alpha: 0.1),
                      foregroundColor: const Color(0xFF42E355),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      provider.isProcessing && provider.mode == SubtitleMode.live
                          ? 'Stop Live Transcription'
                          : 'Start Live Transcription',
                    ),
                  ),
                ),
                _buildHelpText('Transcribe audio in real-time as you watch. Instant but may be less accurate.'),

                if (provider.subtitles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () async {
                        try {
                          final path = await provider.exportSubtitles();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Subtitles exported to $path')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Export failed: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Export .SRT'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: onOpenSearch,
                    icon: const Icon(Icons.search_rounded, size: 16),
                    label: const Text('Search Subtitles'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFAAC7FF),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: onOpenDebug,
                    icon: const Icon(Icons.bug_report_rounded, size: 16),
                    label: const Text('Open Engine Debugger'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFAAC7FF),
                    ),
                  ),
                ),

              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHelpText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 10,
          height: 1.3,
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFFAAC7FF),
          activeTrackColor: const Color(0xFFAAC7FF).withValues(alpha: 0.3),
        ),
      ],
    );
  }
}

/// Subtitle search panel — search across all subtitles and jump to matches
class _SubtitleSearchPanel extends StatefulWidget {
  final SubtitleProvider provider;
  final VoidCallback onClose;
  final ValueChanged<SubtitleEntry> onSeekTo;

  const _SubtitleSearchPanel({
    required this.provider,
    required this.onClose,
    required this.onSeekTo,
  });

  @override
  State<_SubtitleSearchPanel> createState() => _SubtitleSearchPanelState();
}

class _SubtitleSearchPanelState extends State<_SubtitleSearchPanel> {
  final TextEditingController _searchController = TextEditingController();
  List<SubtitleEntry> _results = [];
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      _results = widget.provider.searchSubtitles(value);
    });
  }

  String _formatTime(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 64,
      right: 16,
      child: Container(
        width: 360,
        constraints: const BoxConstraints(maxHeight: 500),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F21).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFFAAC7FF), size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    'Search Subtitles',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Manrope',
                    ),
                  ),
                  const Spacer(),
                  if (_query.isNotEmpty)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.clear_rounded, color: Colors.white.withValues(alpha: 0.4), size: 18),
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onClose,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.5), size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search Japanese or English...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 14),
                  ),
                ),
              ),
            ),

            // Results count
            if (_query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '${_results.length} match${_results.length == 1 ? '' : 'es'}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                    ),
                  ],
                ),
              ),

            // Results list
            if (_results.isNotEmpty)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final entry = _results[index];
                    final isCurrent = entry == widget.provider.currentSubtitle;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: isCurrent
                            ? const Color(0xFF0A84FF).withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: () => widget.onSeekTo(entry),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isCurrent
                                    ? const Color(0xFF0A84FF).withValues(alpha: 0.3)
                                    : Colors.white.withValues(alpha: 0.05),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Timestamp badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _formatTime(entry.startTime),
                                    style: TextStyle(
                                      color: const Color(0xFFAAC7FF).withValues(alpha: 0.7),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (entry.englishText.isNotEmpty)
                                        Text(
                                          entry.englishText,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      if (entry.japaneseText.isNotEmpty && entry.englishText.isNotEmpty)
                                        const SizedBox(height: 2),
                                      if (entry.japaneseText.isNotEmpty)
                                        Text(
                                          entry.japaneseText,
                                          style: TextStyle(
                                            color: const Color(0xFFE9B3FF).withValues(alpha: 0.7),
                                            fontSize: 12,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white.withValues(alpha: 0.3),
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              )
            else if (_query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.search_off_rounded, size: 36, color: Colors.white.withValues(alpha: 0.15)),
                      const SizedBox(height: 8),
                      Text(
                        'No matches found',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.search_rounded, size: 36, color: Colors.white.withValues(alpha: 0.12)),
                      const SizedBox(height: 8),
                      Text(
                        'Type to search across all subtitles',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProcessingBanner extends StatelessWidget {

  final String status;
  final SubtitleMode mode;
  final VoidCallback? onTap;

  const _ProcessingBanner({
    required this.status,
    required this.mode,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 64,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1F1F21).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: mode == SubtitleMode.live
                    ? const Color(0xFF42E355).withValues(alpha: 0.4)
                    : const Color(0xFFAAC7FF).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: mode == SubtitleMode.live
                        ? const Color(0xFF42E355)
                        : const Color(0xFFAAC7FF),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  status.isNotEmpty ? status : (mode == SubtitleMode.live ? 'Live transcription active' : 'Processing...'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, size: 14, color: Colors.white.withValues(alpha: 0.3)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QueuePanel extends StatelessWidget {
  final MediaProvider mediaProvider;
  final VoidCallback onClose;
  final Function(MediaFile) onSelectMedia;

  const _QueuePanel({
    required this.mediaProvider,
    required this.onClose,
    required this.onSelectMedia,
  });

  @override
  Widget build(BuildContext context) {
    final queue = mediaProvider.playbackQueue;
    final currentMedia = mediaProvider.currentMedia;

    return Positioned(
      top: 64,
      right: 16,
      bottom: 100,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: const Color(0xFF131315).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Playback Queue',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Manrope',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: queue.isEmpty
                  ? Center(
                      child: Text(
                        'Queue is empty',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: queue.length,
                      itemBuilder: (context, index) {
                        final media = queue[index];
                        final isCurrent = media.id == currentMedia?.id;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? const Color(0xFFE9B3FF).withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: media.thumbnailPath != null
                                  ? Image.file(
                                      File(media.thumbnailPath!),
                                      width: 48,
                                      height: 32,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 48,
                                      height: 32,
                                      color: Colors.white.withValues(alpha: 0.05),
                                      child: const Icon(Icons.movie_rounded,
                                          size: 16, color: Colors.white24),
                                    ),
                            ),
                            title: Text(
                              media.displayTitle,
                              style: TextStyle(
                                color: isCurrent ? const Color(0xFFE9B3FF) : Colors.white,
                                fontSize: 13,
                                fontWeight:
                                    isCurrent ? FontWeight.bold : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              media.durationFormatted,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                            ),
                            onTap: () => onSelectMedia(media),
                            trailing: isCurrent
                                ? const Icon(Icons.play_arrow_rounded,
                                    color: Color(0xFFE9B3FF), size: 20)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
