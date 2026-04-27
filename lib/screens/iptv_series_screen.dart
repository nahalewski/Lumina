import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/iptv_provider.dart';
import '../services/iptv_service.dart';
import '../themes/sakura_theme.dart';
import 'iptv_player_screen.dart';

/// IPTV Series screen - Redesigned to match tv.png & tv1.png
class IptvSeriesScreen extends StatefulWidget {
  const IptvSeriesScreen({super.key});

  @override
  State<IptvSeriesScreen> createState() => _IptvSeriesScreenState();
}

class _IptvSeriesScreenState extends State<IptvSeriesScreen> {
  String _searchQuery = '';
  String? _selectedShow;
  String? _selectedSeason;

  void _selectShow(String name, Map<String, List<IptvMedia>> seasons) {
    final firstSeason = (seasons.keys.toList()..sort()).first;
    setState(() {
      _selectedShow = name;
      _selectedSeason = firstSeason;
    });
  }

  void _back() => setState(() {
        _selectedShow = null;
        _selectedSeason = null;
      });

  @override
  Widget build(BuildContext context) {
    return Consumer<IptvProvider>(
      builder: (context, provider, child) {
        final grouped = provider.groupedSeries;

        if (provider.isLoading) {
          return const Center(
              child: CircularProgressIndicator(color: SakuraTheme.sakuraPink));
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _selectedShow == null
              ? _SeriesHome(
                  key: const ValueKey('home'),
                  grouped: grouped,
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  onShowTapped: _selectShow,
                  recentlyAdded: provider.recentlyAddedSeries,
                )
              : _ShowDetail(
                  key: ValueKey('detail:$_selectedShow'),
                  showName: _selectedShow!,
                  seasons: grouped[_selectedShow!] ?? {},
                  selectedSeason: _selectedSeason!,
                  onSeasonChanged: (s) => setState(() => _selectedSeason = s),
                  onBack: _back,
                ),
        );
      },
    );
  }
}

// ─── Series Home (Netflix Style) ───────────────────────────────────────────

class _SeriesHome extends StatefulWidget {
  final Map<String, Map<String, List<IptvMedia>>> grouped;
  final ValueChanged<String> onSearchChanged;
  final void Function(String, Map<String, List<IptvMedia>>) onShowTapped;
  final List<IptvMedia> recentlyAdded;

  const _SeriesHome({
    super.key,
    required this.grouped,
    required this.onSearchChanged,
    required this.onShowTapped,
    required this.recentlyAdded,
  });

  @override
  State<_SeriesHome> createState() => _SeriesHomeState();
}

class _SeriesHomeState extends State<_SeriesHome> {
  String _searchQuery = '';
  String? _selectedGenre;

  @override
  Widget build(BuildContext context) {
    final genreMap = _buildGenreMap(widget.grouped);
    final sortedGenres = genreMap.keys.toList()..sort();
    
    // Mock trending (top 10 series)
    final trendingSeries = widget.grouped.keys.take(10).toList();

    return Container(
      color: const Color(0xFF0D0B0F),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: _Header(
              onSearchChanged: (v) {
                setState(() => _searchQuery = v);
                widget.onSearchChanged(v);
              },
            ),
          ),

          if (_searchQuery.isEmpty && _selectedGenre == null) ...[
            // Trending Section
            SliverToBoxAdapter(
              child: _HorizontalSection(
                title: 'Trending shows',
                itemCount: trendingSeries.length,
                height: 220,
                itemBuilder: (context, index) {
                  final name = trendingSeries[index];
                  final seasons = widget.grouped[name]!;
                  return _TrendingCard(
                    name: name,
                    logo: _showLogo(seasons),
                    rank: index + 1,
                    onTap: () => widget.onShowTapped(name, seasons),
                  );
                },
              ),
            ),

            // Recently Added
            SliverToBoxAdapter(
              child: _HorizontalSection(
                title: 'Recently added',
                itemCount: widget.recentlyAdded.length,
                itemBuilder: (context, index) {
                  final ep = widget.recentlyAdded[index];
                  final name = _showNameForEpisode(ep);
                  final seasons = widget.grouped[name] ?? {};
                  return _SeriesCard(
                    name: name,
                    logo: ep.logo,
                    episodes: _totalEpisodes(seasons),
                    onTap: () => widget.onShowTapped(name, seasons),
                    showProgress: true,
                  );
                },
              ),
            ),
          ],

          // Genre Sections
          ...sortedGenres.map((genre) {
            final genreShowNames = genreMap[genre]!;
            if (_selectedGenre != null && _selectedGenre != genre) return const SliverToBoxAdapter(child: SizedBox.shrink());

            return SliverToBoxAdapter(
              child: _HorizontalSection(
                title: genre,
                itemCount: genreShowNames.length,
                itemBuilder: (context, index) {
                  final name = genreShowNames[index];
                  final seasons = widget.grouped[name]!;
                  return _SeriesCard(
                    name: name,
                    logo: _showLogo(seasons),
                    episodes: _totalEpisodes(seasons),
                    onTap: () => widget.onShowTapped(name, seasons),
                  );
                },
                onViewAll: () => setState(() => _selectedGenre = genre),
              ),
            );
          }),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Map<String, List<String>> _buildGenreMap(Map<String, Map<String, List<IptvMedia>>> grouped) {
    final map = <String, List<String>>{};
    for (final showName in grouped.keys) {
      if (_searchQuery.isNotEmpty && !showName.toLowerCase().contains(_searchQuery.toLowerCase())) continue;
      final genre = _genreForShow(showName, grouped);
      map.putIfAbsent(genre, () => []).add(showName);
    }
    return map;
  }

  String _genreForShow(String showName, Map<String, Map<String, List<IptvMedia>>> grouped) {
    final seasons = grouped[showName];
    if (seasons == null || seasons.isEmpty) return 'Other';
    for (final episodeList in seasons.values) {
      for (final episode in episodeList) {
        if (episode.group.isNotEmpty) {
          return episode.group.replaceAll(RegExp(r'^(SERIES|TV|IPTV|SHOWS)\s*[-:]\s*', caseSensitive: false), '').trim();
        }
      }
    }
    return 'Other';
  }

  String _showLogo(Map<String, List<IptvMedia>> seasons) {
    for (final episodeList in seasons.values) {
      for (final episode in episodeList) {
        if (episode.logo.isNotEmpty) return episode.logo;
      }
    }
    return '';
  }

  String _showNameForEpisode(IptvMedia ep) {
    for (final name in widget.grouped.keys) {
      final seasons = widget.grouped[name]!;
      for (final episodes in seasons.values) {
        if (episodes.any((e) => e.url == ep.url)) return name;
      }
    }
    return ep.name;
  }

  int _totalEpisodes(Map<String, List<IptvMedia>> seasons) {
    int total = 0;
    for (final eps in seasons.values) {
      total += eps.length;
    }
    return total;
  }
}

class _Header extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;
  const _Header({required this.onSearchChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TV Shows',
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
                hintText: 'Search for series...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.3), size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: onSearchChanged,
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

class _SeriesCard extends StatelessWidget {
  final String name;
  final String logo;
  final int episodes;
  final VoidCallback onTap;
  final bool showProgress;

  const _SeriesCard({
    required this.name,
    required this.logo,
    required this.episodes,
    required this.onTap,
    this.showProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                    child: logo.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: logo,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorWidget: (_, __, ___) => const Center(
                                child: Icon(Icons.tv_rounded, color: Colors.white12, size: 40)),
                          )
                        : const Center(
                            child: Icon(Icons.tv_rounded, color: Colors.white12, size: 40)),
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
                          widthFactor: 0.4,
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
            Text(name,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text('$episodes Episodes',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final String name;
  final String logo;
  final int rank;
  final VoidCallback onTap;

  const _TrendingCard({
    required this.name,
    required this.logo,
    required this.rank,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 240,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
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
                child: logo.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: logo,
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
      child: const Center(child: Icon(Icons.tv_rounded, color: Colors.white12, size: 40)));
}

class _GenreBar extends StatelessWidget {
  final List<String> genres;
  final String selectedGenre;
  final ValueChanged<String> onGenreSelected;

  const _GenreBar({
    required this.genres,
    required this.selectedGenre,
    required this.onGenreSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: genres.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final genre = genres[index];
          final isActive = genre == selectedGenre;
          return GestureDetector(
            onTap: () => onGenreSelected(genre),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFE9B3FF).withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isActive ? const Color(0xFFE9B3FF) : Colors.white12),
              ),
              child: Text(
                genre,
                style: TextStyle(
                  color: isActive ? const Color(0xFFE9B3FF) : Colors.white38,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final String name;
  final String logo;
  final int seasonCount;
  final VoidCallback onTap;

  const _PosterCard({
    required this.name,
    required this.logo,
    required this.seasonCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (logo.isNotEmpty)
                    CachedNetworkImage(imageUrl: logo, fit: BoxFit.cover)
                  else
                    const Center(child: Icon(Icons.tv_rounded, color: Colors.white12, size: 40)),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('$seasonCount Seasons',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(name,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ─── Show Detail ─────────────────────────────────────────────────────────────

class _ShowDetail extends StatefulWidget {
  final String showName;
  final Map<String, List<IptvMedia>> seasons;
  final String selectedSeason;
  final ValueChanged<String> onSeasonChanged;
  final VoidCallback onBack;

  const _ShowDetail({
    super.key,
    required this.showName,
    required this.seasons,
    required this.selectedSeason,
    required this.onSeasonChanged,
    required this.onBack,
  });

  @override
  State<_ShowDetail> createState() => _ShowDetailState();
}

class _ShowDetailState extends State<_ShowDetail> {
  int _activeTab = 0; // 0: Episodes, 1: Details

  @override
  Widget build(BuildContext context) {
    final sortedSeasons = widget.seasons.keys.toList()..sort();
    final episodes = widget.seasons[widget.selectedSeason] ?? [];
    final heroLogo = _findHeroLogo(episodes);

    return Container(
      color: const Color(0xFF0D0B0F),
      child: Column(
        children: [
          // Hero Section
          _ShowHero(
            showName: widget.showName,
            logo: heroLogo,
            metadata: _getMetadata(episodes),
            onBack: widget.onBack,
            onPlay: () => _playEpisode(episodes.first),
          ),

          // Tabs
          _DetailTabs(
            activeIndex: _activeTab,
            onChanged: (i) => setState(() => _activeTab = i),
          ),

          // Content
          Expanded(
            child: _activeTab == 0
                ? _EpisodeBrowser(
                    seasons: sortedSeasons,
                    selectedSeason: widget.selectedSeason,
                    episodes: episodes,
                    onSeasonChanged: widget.onSeasonChanged,
                    onEpisodeTapped: _playEpisode,
                  )
                : _DetailsView(showName: widget.showName, episodes: episodes),
          ),
        ],
      ),
    );
  }

  String _findHeroLogo(List<IptvMedia> episodes) {
    for (final e in episodes) {
      if (e.logo.isNotEmpty) return e.logo;
    }
    return '';
  }

  String _getMetadata(List<IptvMedia> episodes) {
    final genre = episodes.isNotEmpty ? episodes.first.group : 'TV Series';
    return '$genre • 2024 • 8.2 Rating'; // Mocked
  }

  void _playEpisode(IptvMedia episode) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: episode)),
    );
  }
}

class _ShowHero extends StatelessWidget {
  final String showName;
  final String logo;
  final String metadata;
  final VoidCallback onBack;
  final VoidCallback onPlay;

  const _ShowHero({
    required this.showName,
    required this.logo,
    required this.metadata,
    required this.onBack,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 380,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop
          if (logo.isNotEmpty)
            CachedNetworkImage(
              imageUrl: logo,
              fit: BoxFit.cover,
              color: Colors.black.withValues(alpha: 0.4),
              colorBlendMode: BlendMode.darken,
            ),
          // Gradient Overlays
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                  const Color(0xFF0D0B0F),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 48, 48, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
                const Spacer(),
                Text(showName,
                    style: const TextStyle(
                        fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5)),
                const SizedBox(height: 12),
                Text(metadata,
                    style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded, size: 28),
                      label: const Text('Play Season 1: Episode 1'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _ActionBtn(icon: Icons.favorite_border_rounded),
                    const SizedBox(width: 12),
                    _ActionBtn(icon: Icons.share_rounded),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  const _ActionBtn({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

class _DetailTabs extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onChanged;

  const _DetailTabs({required this.activeIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        children: [
          _TabItem(title: 'Episodes', isActive: activeIndex == 0, onTap: () => onChanged(0)),
          const SizedBox(width: 32),
          _TabItem(title: 'Details', isActive: activeIndex == 1, onTap: () => onChanged(1)),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  const _TabItem({required this.title, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(title,
              style: TextStyle(
                  color: isActive ? Colors.white : Colors.white38,
                  fontSize: 16,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600)),
          const SizedBox(height: 8),
          if (isActive)
            Container(width: 40, height: 3, decoration: BoxDecoration(color: const Color(0xFFE9B3FF), borderRadius: BorderRadius.circular(2))),
        ],
      ),
    );
  }
}

class _EpisodeBrowser extends StatelessWidget {
  final List<String> seasons;
  final String selectedSeason;
  final List<IptvMedia> episodes;
  final ValueChanged<String> onSeasonChanged;
  final ValueChanged<IptvMedia> onEpisodeTapped;

  const _EpisodeBrowser({
    required this.seasons,
    required this.selectedSeason,
    required this.episodes,
    required this.onSeasonChanged,
    required this.onEpisodeTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sidebar Season Selector
        Container(
          width: 200,
          padding: const EdgeInsets.fromLTRB(48, 24, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: seasons.map((s) {
              final isActive = s == selectedSeason;
              return GestureDetector(
                onTap: () => onSeasonChanged(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    s,
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.white24,
                      fontSize: 16,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Episode List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 24, 48, 48),
            itemCount: episodes.length,
            itemBuilder: (context, i) => _EpisodeItem(
              episode: episodes[i],
              index: i,
              onTap: () => onEpisodeTapped(episodes[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _EpisodeItem extends StatelessWidget {
  final IptvMedia episode;
  final int index;
  final VoidCallback onTap;

  const _EpisodeItem({required this.episode, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Container(
              width: 200,
              height: 112,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: episode.logo.isNotEmpty
                  ? CachedNetworkImage(imageUrl: episode.logo, fit: BoxFit.cover)
                  : const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white24, size: 40)),
            ),
            const SizedBox(width: 24),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Episode ${index + 1}',
                      style: const TextStyle(color: Color(0xFFE9B3FF), fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(episode.name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    'In this episode, the story continues as our heroes face new challenges and uncover secrets hidden for generations.',
                    style: TextStyle(color: Colors.white38, fontSize: 14, height: 1.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  const Text('March 24, 2024', style: TextStyle(color: Colors.white24, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsView extends StatelessWidget {
  final String showName;
  final List<IptvMedia> episodes;

  const _DetailsView({required this.showName, required this.episodes});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About this show',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          const Text(
            'This gripping series follows the journey of individuals caught in a web of intrigue and high stakes. With stunning visuals and a compelling narrative, it explores themes of loyalty, power, and the human spirit.',
            style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.6),
          ),
          const SizedBox(height: 32),
          _DetailRow(label: 'Cast', value: 'John Smith, Jane Doe, Mike Brown'),
          _DetailRow(label: 'Director', value: 'Sarah Johnson'),
          _DetailRow(label: 'Genre', value: episodes.isNotEmpty ? episodes.first.group : 'TV Series'),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 14))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tv_off_rounded,
              size: 64, color: Colors.white12),
          const SizedBox(height: 16),
          Text(
            'No shows found',
            style: TextStyle(
                color: Colors.white24,
                fontSize: 15,
                fontFamily: 'Manrope'),
          ),
        ],
      ),
    );
  }
}
