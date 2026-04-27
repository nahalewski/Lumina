import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/iptv_provider.dart';
import '../services/iptv_service.dart';
import 'iptv_player_screen.dart';

/// IPTV Movies screen - Redesigned to match movie.png & movie2.png
class IptvMoviesScreen extends StatefulWidget {
  const IptvMoviesScreen({super.key});

  @override
  State<IptvMoviesScreen> createState() => _IptvMoviesScreenState();
}

class _IptvMoviesScreenState extends State<IptvMoviesScreen> {
  String _searchQuery = '';
  String? _selectedGenre;

  @override
  Widget build(BuildContext context) {
    return Consumer<IptvProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFE9B3FF)));
        }

        final movies = provider.movies;
        final recentMovies = provider.recentlyAddedMovies;
        
        // Mock trending (top 10 from all movies)
        final trendingMovies = movies.take(10).toList();

        final filtered = _applyFilters(movies);
        final genreMap = _groupMoviesByGenre(filtered);
        final sortedGenres = genreMap.keys.toList()..sort();

        return Container(
          color: const Color(0xFF0D0B0F),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Search & Header
              SliverToBoxAdapter(
                child: _SearchHeader(
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),

              if (_searchQuery.isEmpty && _selectedGenre == null) ...[
                // Trending Section (Numerical Index)
                SliverToBoxAdapter(
                  child: _HorizontalSection(
                    title: 'Trending movies',
                    itemCount: trendingMovies.length,
                    height: 220,
                    itemBuilder: (context, index) => _TrendingCard(
                      movie: trendingMovies[index],
                      rank: index + 1,
                    ),
                  ),
                ),

                // Recently Added Section
                SliverToBoxAdapter(
                  child: _HorizontalSection(
                    title: 'Recently added',
                    itemCount: recentMovies.length,
                    itemBuilder: (context, index) => _MovieCard(
                      movie: recentMovies[index],
                      showProgress: true,
                    ),
                    onViewAll: () => setState(() => _selectedGenre = 'Recently Added'),
                  ),
                ),
              ],

              // Genre Sections
              ...sortedGenres.map((genre) {
                final genreMovies = genreMap[genre]!;
                if (_selectedGenre != null && _selectedGenre != genre) return const SliverToBoxAdapter(child: SizedBox.shrink());
                
                return SliverToBoxAdapter(
                  child: _HorizontalSection(
                    title: genre,
                    itemCount: genreMovies.length,
                    itemBuilder: (context, index) => _MovieCard(movie: genreMovies[index]),
                    onViewAll: () => setState(() => _selectedGenre = genre),
                  ),
                );
              }),
              
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  List<IptvMedia> _applyFilters(List<IptvMedia> movies) {
    var filtered = movies;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((m) =>
          m.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    return filtered;
  }

  Map<String, List<IptvMedia>> _groupMoviesByGenre(List<IptvMedia> movies) {
    final Map<String, List<IptvMedia>> genreMap = {};
    for (final movie in movies) {
      final genre = _cleanGenre(movie.group);
      genreMap.putIfAbsent(genre, () => []).add(movie);
    }
    return genreMap;
  }

  String _cleanGenre(String group) {
    String cleaned = group.replaceAll(RegExp(r'^(MOVIE|VOD|IPTV|MOVIES)\s*[-:]\s*', caseSensitive: false), '').trim();
    return cleaned.isEmpty ? 'General' : cleaned;
  }
}

class _SearchHeader extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchHeader({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Movies',
              style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
          const SizedBox(height: 16),
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search for movies...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.3), size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalSection extends StatelessWidget {
  final String title;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final VoidCallback? onViewAll;
  final double height;

  const _HorizontalSection({
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.onViewAll,
    this.height = 260,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (onViewAll != null)
                GestureDetector(
                  onTap: onViewAll,
                  child: const Text('view all',
                      style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: itemCount,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }
}

class _MovieCard extends StatelessWidget {
  final IptvMedia movie;
  final bool showProgress;
  const _MovieCard({required this.movie, this.showProgress = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: movie)),
      ),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: movie.logo.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: movie.logo,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorWidget: (_, __, ___) => const Center(
                                child: Icon(Icons.movie_rounded, color: Colors.white12, size: 40)),
                          )
                        : const Center(
                            child: Icon(Icons.movie_rounded, color: Colors.white12, size: 40)),
                  ),
                  // Rating Badge (Simulated)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.star, color: Color(0xFFE9B3FF), size: 10),
                          SizedBox(width: 2),
                          Text('8.4',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  if (showProgress)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.6,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9B3FF),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(movie.name,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text('Action', // Simulated genre
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final IptvMedia movie;
  final int rank;
  const _TrendingCard({required this.movie, required this.rank});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: movie)),
      ),
      child: SizedBox(
        width: 240,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Numerical Index
            Positioned(
              left: -10,
              bottom: -15,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 120,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 2
                    ..color = Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ),
            // Movie Poster
            Padding(
              padding: const EdgeInsets.only(left: 60),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: movie.logo.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: movie.logo,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorWidget: (_, __, ___) => _fallback(),
                      )
                    : _fallback(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: const Center(child: Icon(Icons.movie_rounded, color: Colors.white12, size: 40)));
}
