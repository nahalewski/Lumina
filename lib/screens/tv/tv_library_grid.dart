import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/media_provider.dart';
import '../../widgets/tv/tv_focus_wrapper.dart';

class TvLibraryGrid extends StatelessWidget {
  final VoidCallback onPlayMedia;

  const TvLibraryGrid({
    super.key,
    required this.onPlayMedia,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        final bool isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 1000;
        
        return Consumer<MediaProvider>(
          builder: (context, provider, _) {
            final mediaList = provider.mediaFiles;
            
            if (mediaList.isEmpty) {
              return const Center(
                child: Text(
                  'No media found',
                  style: TextStyle(fontSize: 24, color: Colors.white54),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(isMobile ? 16 : 48, isMobile ? 24 : 48, isMobile ? 16 : 48, 12),
                  child: Text(
                    'Media Library',
                    style: TextStyle(
                      fontSize: isMobile ? 28 : 48,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.fromLTRB(isMobile ? 16 : 48, 0, isMobile ? 16 : 48, 48),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isMobile ? 2 : (isTablet ? 3 : 4),
                      childAspectRatio: 1.6,
                      crossAxisSpacing: isMobile ? 16 : 32,
                      mainAxisSpacing: isMobile ? 16 : 32,
                    ),
                    itemCount: mediaList.length,
                    itemBuilder: (context, index) {
                      final media = mediaList[index];
                      return TvFocusWrapper(
                        onTap: () {
                          provider.setCurrentMedia(media);
                          onPlayMedia();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.white.withValues(alpha: 0.05),
                            image: media.thumbnailPath != null 
                              ? DecorationImage(
                                  image: AssetImage(media.thumbnailPath!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.8),
                                      ],
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        media.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: isMobile ? 14 : 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        media.extension.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white.withValues(alpha: 0.6),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Icon(
                                  media.isVideo ? Icons.movie_rounded : Icons.audiotrack_rounded,
                                  color: Colors.white.withValues(alpha: 0.5),
                                  size: isMobile ? 16 : 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
