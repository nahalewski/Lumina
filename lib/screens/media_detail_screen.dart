import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_model.dart';
import '../providers/media_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MediaDetailScreen extends StatelessWidget {
  final MediaFile media;
  final List<MediaFile> library;

  const MediaDetailScreen({
    super.key,
    required this.media,
    this.library = const [],
  });

  @override
  Widget build(BuildContext context) {
    final related = _relatedItems();
    final overview = media.synopsis ?? media.description;
    return Scaffold(
      backgroundColor: const Color(0xFF131315),
      body: Stack(
        children: [
          // Backdrop
          if (media.backdropUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.3,
                child: CachedNetworkImage(
                  imageUrl: media.backdropUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              ),
            ),

          // Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF131315).withValues(alpha: 0.8),
                    const Color(0xFF131315),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Content
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon:
                      const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Poster
                      Hero(
                        tag: 'media-poster-${media.id}',
                        child: Container(
                          width: 200,
                          height: 300,
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
                            child: media.posterUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: media.posterUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        Container(color: Colors.white10),
                                    errorWidget: (context, url, error) =>
                                        const Icon(Icons.movie_rounded,
                                            size: 50, color: Colors.white24),
                                  )
                                : Container(
                                    color: Colors.white10,
                                    child: const Icon(Icons.movie_rounded,
                                        size: 50, color: Colors.white24),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 32),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              media.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (media.showTitle != null &&
                                media.showTitle != media.title)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  media.showTitle!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                if (media.rating != null) ...[
                                  const Icon(Icons.star_rounded,
                                      color: Color(0xFFE9B3FF), size: 20),
                                  const SizedBox(width: 4),
                                  Text(
                                    media.rating!.toStringAsFixed(1),
                                    style: const TextStyle(
                                        color: Color(0xFFE9B3FF),
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 16),
                                ],
                                if (media.releaseYear != null)
                                  Text(
                                    media.releaseYear.toString(),
                                    style:
                                        const TextStyle(color: Colors.white60),
                                  ),
                                const SizedBox(width: 16),
                                if (media.resolution != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.white24),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      media.resolution!,
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 10),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            // Action Buttons
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Provider.of<MediaProvider>(context,
                                            listen: false)
                                        .playMedia(media);
                                    Navigator.pop(context);
                                  },
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('PLAY'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFAAC7FF),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            if (overview != null && overview.isNotEmpty) ...[
                              const Text(
                                'Overview',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                overview,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 15,
                                    height: 1.5),
                              ),
                            ],
                            const SizedBox(height: 24),
                            _CreditsBlock(media: media),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (media.genres.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: media.genres
                          .map((genre) => Chip(
                                label: Text(genre,
                                    style: const TextStyle(fontSize: 12)),
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.05),
                                labelStyle:
                                    const TextStyle(color: Colors.white60),
                                side: BorderSide.none,
                              ))
                          .toList(),
                    ),
                  ),
                ),
              if (related.isNotEmpty)
                SliverToBoxAdapter(
                  child: _RelatedLibraryRow(items: related, library: library),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<MediaFile> _relatedItems() {
    final currentTitle = media.mediaKind == MediaKind.tv
        ? media.showTitle
        : media.movieTitle ?? media.libraryTitle;
    return library
        .where((item) => item.id != media.id)
        .where((item) {
          if (media.mediaKind == MediaKind.tv) {
            return item.mediaKind == MediaKind.tv &&
                item.showTitle != null &&
                item.showTitle == currentTitle;
          }
          if (media.mediaKind == MediaKind.movie) {
            final sameGenre = media.genres.isNotEmpty &&
                item.genres.any((genre) => media.genres.contains(genre));
            final sharedCast = media.cast.isNotEmpty &&
                item.cast.any((person) => media.cast.contains(person));
            return item.mediaKind == MediaKind.movie &&
                (sameGenre || sharedCast || _sameFranchise(item));
          }
          return false;
        })
        .take(12)
        .toList();
  }

  bool _sameFranchise(MediaFile item) {
    final base = _franchiseSeed(media.movieTitle ?? media.title);
    return base.length > 4 &&
        _franchiseSeed(item.movieTitle ?? item.title).contains(base);
  }

  String _franchiseSeed(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), '')
        .replaceAll(RegExp(r'\b[ivx]+|\d+\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }
}

class _CreditsBlock extends StatelessWidget {
  final MediaFile media;

  const _CreditsBlock({required this.media});

  @override
  Widget build(BuildContext context) {
    final rows = [
      if (media.cast.isNotEmpty) ('Cast', media.cast.take(10).join(', ')),
      if (media.directors.isNotEmpty)
        ('Director', media.directors.take(3).join(', ')),
      if (media.writers.isNotEmpty)
        ('Writer', media.writers.take(4).join(', ')),
      if (media.trailerUrl != null) ('Trailer', media.trailerUrl!),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows) ...[
          Text(
            row.$1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            row.$2,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _RelatedLibraryRow extends StatelessWidget {
  final List<MediaFile> items;
  final List<MediaFile> library;

  const _RelatedLibraryRow({required this.items, required this.library});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Related in Library',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = items[index];
                final imageUrl = item.posterUrl ?? item.coverArtUrl;
                return SizedBox(
                  width: 122,
                  child: InkWell(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MediaDetailScreen(media: item, library: library),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl == null
                                ? Container(
                                    color: Colors.white10,
                                    child: const Center(
                                      child: Icon(Icons.movie_rounded,
                                          color: Colors.white24),
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.libraryTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
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
      ),
    );
  }
}
