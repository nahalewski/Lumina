import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/remote_media_provider.dart';
import '../widgets/falling_particles.dart';

class BasicPlayerScreen extends StatefulWidget {
  const BasicPlayerScreen({super.key});

  @override
  State<BasicPlayerScreen> createState() => _BasicPlayerScreenState();
}

class _BasicPlayerScreenState extends State<BasicPlayerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RemoteMediaProvider>().connectAndFetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      appBar: AppBar(
        title: const Text('Lumina Basic', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -1, fontFamily: 'Manrope')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded, color: Color(0xFFAAC7FF)),
            onPressed: () => context.read<RemoteMediaProvider>().connectAndFetch(),
          ),
        ],
      ),
      body: FallingFlowersBackground(
        child: Consumer<RemoteMediaProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.media.isEmpty) {
              return const Center(
                child: Text(
                  'No media found on server',
                  style: TextStyle(color: Colors.white54, fontSize: 18),
                ),
              );
            }

            return Column(
              children: [
                // Current Player (if any)
                if (provider.controller != null && provider.controller!.value.isInitialized)
                  AspectRatio(
                    aspectRatio: provider.controller!.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(provider.controller!),
                        _VideoControls(controller: provider.controller!),
                        VideoProgressIndicator(provider.controller!, allowScrubbing: true),
                      ],
                    ),
                  ),
                
                // Media List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.media.length,
                    itemBuilder: (context, index) {
                      final media = provider.media[index];
                      final isPlaying = provider.currentMedia?.id == media.id;
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          tileColor: isPlaying ? const Color(0xFFE9B3FF).withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: isPlaying 
                                ? const LinearGradient(colors: [Color(0xFFAAC7FF), Color(0xFFE9B3FF)])
                                : null,
                              color: isPlaying ? null : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              media.isVideo ? Icons.movie_rounded : Icons.audiotrack_rounded,
                              color: isPlaying ? const Color(0xFF002957) : Colors.white54,
                            ),
                          ),
                          title: Text(
                            media.title,
                            style: TextStyle(
                              color: isPlaying ? const Color(0xFFE9B3FF) : Colors.white,
                              fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                              fontFamily: 'Manrope',
                            ),
                          ),
                          subtitle: Text(
                            '${media.extension.toUpperCase()} • ${media.duration.inMinutes} min',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                          ),
                          onTap: () => provider.playMedia(media),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  final VideoPlayerController controller;

  const _VideoControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 32,
            ),
            onPressed: () {
              controller.value.isPlaying ? controller.pause() : controller.play();
            },
          ),
        ],
      ),
    );
  }
}
