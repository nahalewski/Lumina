import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/media_provider.dart';
import 'document_library_screen.dart';
import '../services/ebook_manga_metadata_service.dart';

class MangaDetailScreen extends StatelessWidget {
  final DocumentItem seriesRepresentative;
  final List<DocumentItem> volumes;

  const MangaDetailScreen({
    super.key,
    required this.seriesRepresentative,
    required this.volumes,
  });

  @override
  Widget build(BuildContext context) {
    // Sort volumes by volume number, then chapter
    final sortedVolumes = List<DocumentItem>.from(volumes)
      ..sort((a, b) {
        final volA = double.tryParse(a.volume ?? '') ?? 0.0;
        final volB = double.tryParse(b.volume ?? '') ?? 0.0;
        if (volA != volB) return volA.compareTo(volB);
        
        final chA = double.tryParse(a.issue ?? '') ?? 0.0;
        final chB = double.tryParse(b.issue ?? '') ?? 0.0;
        return chA.compareTo(chB);
      });

    final artists = seriesRepresentative.artists.isNotEmpty 
        ? seriesRepresentative.artists 
        : seriesRepresentative.authors;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F11),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPoster(),
                      const SizedBox(width: 32),
                      Expanded(child: _buildInfo(context, artists)),
                    ],
                  ),
                  const SizedBox(height: 48),
                  _buildVolumeList(context, sortedVolumes),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: const Color(0xFF0F0F11),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (seriesRepresentative.localCoverPath != null)
              Opacity(
                opacity: 0.3,
                child: Image.file(
                  File(seriesRepresentative.localCoverPath!),
                  fit: BoxFit.cover,
                ),
              )
            else if (seriesRepresentative.coverUrl != null)
              Opacity(
                opacity: 0.3,
                child: CachedNetworkImage(
                  imageUrl: seriesRepresentative.coverUrl!,
                  fit: BoxFit.cover,
                ),
              ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFF0F0F11)],
                ),
              ),
            ),
          ],
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildPoster() {
    return Container(
      width: 220,
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _DocumentCover(
          item: seriesRepresentative,
          isManga: true,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildInfo(BuildContext context, List<String> artists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          seriesRepresentative.series ?? seriesRepresentative.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w900,
            fontFamily: 'Manrope',
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (seriesRepresentative.rating != null) ...[
              const Icon(Icons.star_rounded, color: Color(0xFFE9B3FF), size: 24),
              const SizedBox(width: 6),
              Text(
                seriesRepresentative.rating!.toStringAsFixed(1),
                style: const TextStyle(
                  color: Color(0xFFE9B3FF),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 24),
            ],
            Text(
              '${volumes.length} Volumes/Chapters',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (seriesRepresentative.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: seriesRepresentative.tags.take(6).map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9B3FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE9B3FF).withValues(alpha: 0.2)),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(color: Color(0xFFE9B3FF), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              )).toList(),
            ),
          ),
        if (seriesRepresentative.summary != null) ...[
          const Text(
            'SYNOPSIS',
            style: TextStyle(
              color: Colors.white30,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            seriesRepresentative.summary!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 15,
              height: 1.6,
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 24),
        if (artists.isNotEmpty) ...[
          const Text(
            'ARTISTS / AUTHORS',
            style: TextStyle(
              color: Colors.white30,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            artists.join(', '),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVolumeList(BuildContext context, List<DocumentItem> sortedVolumes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'COLLECTION',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'Manrope',
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            childAspectRatio: 0.65,
            crossAxisSpacing: 16,
            mainAxisSpacing: 24,
          ),
          itemCount: sortedVolumes.length,
          itemBuilder: (context, index) {
            final item = sortedVolumes[index];
            return InkWell(
              onTap: () => _openManga(context, item, sortedVolumes),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _DocumentCover(item: item, isManga: true, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.volume != null ? 'Volume ${item.volume}' : item.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.issue != null)
                    Text(
                      'Chapter ${item.issue}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _openManga(BuildContext context, DocumentItem item, List<DocumentItem> allVolumes) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentReaderScreen(
          item: item,
          type: DocumentLibraryType.manga,
          mangaItems: allVolumes,
          initialIndex: allVolumes.indexOf(item),
        ),
      ),
    );
  }
}

class _DocumentCover extends StatelessWidget {
  final DocumentItem item;
  final bool isManga;
  final BoxFit fit;
  const _DocumentCover({
    required this.item,
    required this.isManga,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    if (item.localCoverPath != null && File(item.localCoverPath!).existsSync()) {
      return Image.file(File(item.localCoverPath!), fit: fit);
    }
    if (item.coverUrl != null) {
      return CachedNetworkImage(imageUrl: item.coverUrl!, fit: fit);
    }
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          isManga ? Icons.auto_stories_rounded : Icons.menu_book_rounded,
          color: const Color(0xFFE9B3FF),
          size: 40,
        ),
      ),
    );
  }
}
