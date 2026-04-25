import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/iptv_provider.dart';
import '../services/iptv_service.dart';
import 'iptv_player_screen.dart';

/// IPTV Movies screen - organized by genre/category
class IptvMoviesScreen extends StatefulWidget {
  const IptvMoviesScreen({super.key});

  @override
  State<IptvMoviesScreen> createState() => _IptvMoviesScreenState();
}

class _IptvMoviesScreenState extends State<IptvMoviesScreen> {
  String _searchQuery = '';
  String? _selectedGenre;

  Future<void> _playMovie(IptvMedia movie) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IptvPlayerScreen(media: movie),
      ),
    );
  }

  String _cleanGenre(String group) {
    String cleaned = group
        .replaceAll(RegExp(r'^MOVIE\s*[-:]\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^VOD\s*[-:]\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^MOVIES\s*[-:]\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^IPTV\s*[-:]\s*', caseSensitive: false), '')
        .trim();
    if (cleaned.isEmpty || cleaned.toLowerCase() == 'movie' || cleaned.toLowerCase() == 'vod' || cleaned.toLowerCase() == 'movies') {
      return 'All Movies';
    }
    return cleaned;
  }

  IconData _genreIcon(String genre) {
    final g = genre.toLowerCase();
    if (g.contains('recent')) return Icons.auto_awesome_rounded;
    if (g.contains('action') || g.contains('adventure') || g.contains('thriller')) return Icons.flash_on_rounded;
    if (g.contains('horror') || g.contains('scary') || g.contains('terror')) return Icons.dangerous_rounded;
    if (g.contains('comedy') || g.contains('funny') || g.contains('humor')) return Icons.emoji_emotions_rounded;
    if (g.contains('drama') || g.contains('romance') || g.contains('love')) return Icons.favorite_rounded;
    if (g.contains('sci-fi') || g.contains('sci fi') || g.contains('science') || g.contains('fantasy')) return Icons.rocket_launch_rounded;
    if (g.contains('documentary') || g.contains('docu')) return Icons.menu_book_rounded;
    if (g.contains('animation') || g.contains('cartoon') || g.contains('anime') || g.contains('kids') || g.contains('family') || g.contains('children')) return Icons.child_care_rounded;
    return Icons.movie_rounded;
  }

  Color _genreColor(String genre) {
    final g = genre.toLowerCase();
    if (g.contains('recent')) return const Color(0xFFE9B3FF);
    if (g.contains('action')) return const Color(0xFFFF4444);
    if (g.contains('horror')) return const Color(0xFF6B1D1D);
    if (g.contains('comedy')) return const Color(0xFFFFB347);
    if (g.contains('drama') || g.contains('romance')) return const Color(0xFFFF6B9D);
    if (g.contains('sci-fi') || g.contains('fantasy')) return const Color(0xFF7B68EE);
    return const Color(0xFFE9B3FF);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<IptvProvider>(
      builder: (context, provider, _) {
        final movies = provider.movies;
        final movieGroups = provider.movieGroups;
        final recentMovies = provider.recentlyAddedMovies;

        var filtered = movies;
        if (_searchQuery.isNotEmpty) {
          filtered = filtered.where((m) =>
            m.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            m.group.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
        }

        final Map<String, List<IptvMedia>> genreMap = {};
        for (final movie in filtered) {
          final genre = _cleanGenre(movie.group);
          genreMap.putIfAbsent(genre, () => []);
          genreMap[genre]!.add(movie);
        }

        final sortedGenres = genreMap.keys.toList()..sort();

        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9B3FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.movie_rounded, color: Color(0xFFE9B3FF), size: 22),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Movies', style: TextStyle(fontFamily: 'Manrope', fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('IPTV Video on Demand', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
                    onPressed: () => provider.loadMedia(),
                  ),
                ],
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Search movies...',
                    prefixIcon: Icon(Icons.search, color: Colors.white24),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            ),
            // Content
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFE9B3FF)))
                  : CustomScrollView(
                      slivers: [
                        // Recently Added Section (Only if no search/filter)
                        if (_searchQuery.isEmpty && _selectedGenre == null && recentMovies.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _buildGenreSection('Recently Added', recentMovies),
                          ),
                        // Genres
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final genre = sortedGenres[index];
                                final genreMovies = genreMap[genre]!;
                                if (_selectedGenre != null && genre != _cleanGenre(_selectedGenre!)) {
                                  return const SizedBox.shrink();
                                }
                                return _buildGenreSection(genre, genreMovies, wrapInPadding: false);
                              },
                              childCount: sortedGenres.length,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGenreSection(String genre, List<IptvMedia> movies, {bool wrapInPadding = true}) {
    Widget content = Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_genreIcon(genre), size: 20, color: _genreColor(genre)),
              const SizedBox(width: 8),
              Text(genre, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${movies.length} titles', style: const TextStyle(color: Colors.white24, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: movies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final movie = movies[index];
                return GestureDetector(
                  onTap: () => _playMovie(movie),
                  child: SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              image: movie.logo.isNotEmpty 
                                ? DecorationImage(image: NetworkImage(movie.logo), fit: BoxFit.cover)
                                : null,
                            ),
                            child: movie.logo.isEmpty 
                              ? Center(child: Icon(Icons.movie_rounded, color: Colors.white12, size: 40))
                              : null,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(movie.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
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

    return wrapInPadding ? Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: content) : content;
  }
}
