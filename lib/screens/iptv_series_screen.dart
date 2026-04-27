import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/iptv_provider.dart';
import '../services/iptv_service.dart';
import '../themes/sakura_theme.dart';
import 'iptv_player_screen.dart';

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
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: _selectedShow == null
                    ? const Offset(-0.04, 0)
                    : const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: _selectedShow == null
              ? _ShowGrid(
                  key: const ValueKey('grid'),
                  grouped: grouped,
                  searchQuery: _searchQuery,
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  onShowTapped: _selectShow,
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

// ─── Show Poster Grid ────────────────────────────────────────────────────────

class _ShowGrid extends StatefulWidget {
  final Map<String, Map<String, List<IptvMedia>>> grouped;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final void Function(String, Map<String, List<IptvMedia>>) onShowTapped;

  const _ShowGrid({
    super.key,
    required this.grouped,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onShowTapped,
  });

  @override
  State<_ShowGrid> createState() => _ShowGridState();
}

class _ShowGridState extends State<_ShowGrid> {
  String? _selectedGenre;

  @override
  Widget build(BuildContext context) {
    final genreMap = _buildGenreMap(widget.grouped);
    final genres = ['All', ...genreMap.keys.toList()..sort()];
    final selectedGenre = _selectedGenre ?? 'All';
    final visibleGenres = selectedGenre == 'All'
        ? genres.where((g) => g != 'All').toList()
        : [selectedGenre];

    final filteredShows = widget.grouped.keys
        .where((name) =>
            name.toLowerCase().contains(widget.searchQuery.toLowerCase()))
        .where((name) {
      if (selectedGenre == 'All') return true;
      final genre = _genreForShow(name, widget.grouped);
      return genre == selectedGenre;
    }).toList()
      ..sort();

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyHeaderDelegate(
            minExtent: 120,
            maxExtent: 144,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _Header(
                    showCount: filteredShows.length,
                    onSearchChanged: widget.onSearchChanged),
                const SizedBox(height: 8),
                _GenreBar(
                  genres: genres,
                  selectedGenre: selectedGenre,
                  onGenreSelected: (genre) =>
                      setState(() => _selectedGenre = genre),
                ),
              ],
            ),
          ),
        ),
        if (filteredShows.isEmpty)
          const SliverFillRemaining(child: _EmptyState())
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final genre = visibleGenres[index];
                final genreShows = genreMap[genre]!
                    .where((name) => name
                        .toLowerCase()
                        .contains(widget.searchQuery.toLowerCase()))
                    .toList()
                  ..sort();
                if (genreShows.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: _GenreSection(
                    genre: genre,
                    showNames: genreShows,
                    grouped: widget.grouped,
                    onShowTapped: widget.onShowTapped,
                  ),
                );
              },
              childCount: visibleGenres.length,
            ),
          ),
      ],
    );
  }

  Map<String, List<String>> _buildGenreMap(
      Map<String, Map<String, List<IptvMedia>>> grouped) {
    final map = <String, List<String>>{};
    for (final showName in grouped.keys) {
      final genre = _genreForShow(showName, grouped);
      map.putIfAbsent(genre, () => []).add(showName);
    }
    return map;
  }

  String _genreForShow(
      String showName, Map<String, Map<String, List<IptvMedia>>> grouped) {
    final seasons = grouped[showName];
    if (seasons == null || seasons.isEmpty) return 'Other';
    for (final episodeList in seasons.values) {
      for (final episode in episodeList) {
        if (episode.group.isNotEmpty) return episode.group;
      }
    }
    return 'Other';
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minExtent;
  final double maxExtent;
  final Widget child;

  _StickyHeaderDelegate(
      {required this.minExtent, required this.maxExtent, required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: SakuraTheme.background,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 12),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
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
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 0),
        itemCount: genres.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final genre = genres[index];
          final isActive = genre == selectedGenre;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onGenreSelected(genre),
              borderRadius: BorderRadius.circular(15),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: isActive
                      ? SakuraTheme.sakuraPink.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                      color: isActive
                          ? SakuraTheme.sakuraPink.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.08)),
                ),
                child: Text(
                  genre,
                  style: TextStyle(
                    color: isActive
                        ? SakuraTheme.sakuraPink
                        : Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GenreSection extends StatelessWidget {
  final String genre;
  final List<String> showNames;
  final Map<String, Map<String, List<IptvMedia>>> grouped;
  final void Function(String, Map<String, List<IptvMedia>>) onShowTapped;

  const _GenreSection({
    required this.genre,
    required this.showNames,
    required this.grouped,
    required this.onShowTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            genre,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 292,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            itemCount: showNames.length,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (context, index) {
              final name = showNames[index];
              final seasons = grouped[name]!;
              final seasonCount = seasons.length;
              return SizedBox(
                width: 174,
                child: _PosterCard(
                  name: name,
                  logo: _showLogo(seasons),
                  seasonCount: seasonCount,
                  onTap: () => onShowTapped(name, seasons),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _showLogo(Map<String, List<IptvMedia>> seasons) {
    for (final episodeList in seasons.values) {
      for (final episode in episodeList) {
        if (episode.logo.isNotEmpty) return episode.logo;
      }
    }
    return '';
  }
}

class _Header extends StatelessWidget {
  final int showCount;
  final ValueChanged<String> onSearchChanged;

  const _Header({required this.showCount, required this.onSearchChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  SakuraTheme.sakuraPink.withValues(alpha: 0.25),
                  SakuraTheme.sakuraPink.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: SakuraTheme.sakuraPink.withValues(alpha: 0.3),
                  width: 1),
            ),
            child: const Icon(Icons.live_tv_rounded,
                color: SakuraTheme.sakuraPink, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TV Shows',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                '$showCount series',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          // Search
          SizedBox(
            width: 280,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search shows…',
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.3), size: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onChanged: onSearchChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterCard extends StatefulWidget {
  final String name;
  final String logo;
  final int seasonCount;
  final VoidCallback onTap;

  const _PosterCard(
      {required this.name,
      required this.logo,
      required this.seasonCount,
      required this.onTap});

  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.diagonal3Values(
              _hovered ? 1.04 : 1.0, _hovered ? 1.04 : 1.0, 1.0),
          transformAlignment: Alignment.center,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _hovered
                          ? SakuraTheme.sakuraPink.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.07),
                      width: _hovered ? 1.5 : 1,
                    ),
                    boxShadow: _hovered
                        ? [
                            BoxShadow(
                                color: SakuraTheme.sakuraPink
                                    .withValues(alpha: 0.18),
                                blurRadius: 18,
                                spreadRadius: 2)
                          ]
                        : [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.logo.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: widget.logo,
                            fit: BoxFit.cover,
                            errorWidget: (ctx, url, err) => _posterFallback(),
                          )
                        else
                          _posterFallback(),
                        // Bottom gradient
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 60,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.75),
                                  Colors.transparent
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Season badge
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            child: Text(
                              '${widget.seasonCount} ${widget.seasonCount == 1 ? 'Season' : 'Seasons'}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Manrope',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _posterFallback() {
    return Container(
      color: SakuraTheme.sakuraPink.withValues(alpha: 0.05),
      child: Center(
        child: Icon(Icons.live_tv_rounded,
            color: SakuraTheme.sakuraPink.withValues(alpha: 0.2), size: 40),
      ),
    );
  }
}

// ─── Show Detail ─────────────────────────────────────────────────────────────

class _ShowDetail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final sortedSeasons = seasons.keys.toList()..sort();
    final episodes = seasons[selectedSeason] ?? [];

    // Pick hero image from the first episode with a logo, or fallback to the first episode.
    final heroLogo = episodes.isNotEmpty
        ? episodes
            .firstWhere((e) => e.logo.isNotEmpty, orElse: () => episodes.first)
            .logo
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Hero banner ──────────────────────────────────────────
        _HeroBanner(showName: showName, heroLogo: heroLogo, onBack: onBack),

        _ShowInfoPanel(showName: showName, episodes: episodes),

        // ── Season selector ──────────────────────────────────────
        _SeasonSelector(
          seasons: sortedSeasons,
          selected: selectedSeason,
          onChanged: onSeasonChanged,
        ),

        // ── Episode list ─────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
            itemCount: episodes.length,
            itemBuilder: (context, i) => _EpisodeRow(
              episode: episodes[i],
              showName: showName,
              index: i,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color.withValues(alpha: 0.95),
            fontSize: 11,
            fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 12,
            fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _ShowInfoPanel extends StatelessWidget {
  final String showName;
  final List<IptvMedia> episodes;

  const _ShowInfoPanel({required this.showName, required this.episodes});

  @override
  Widget build(BuildContext context) {
    final channelLabel = episodes.isNotEmpty ? episodes.first.group : 'TV Show';
    return Consumer<IptvProvider>(
      builder: (context, provider, _) {
        final epgEntries = episodes.isNotEmpty
            ? provider.getEpgForChannel(episodes.first.tvgId)
            : <EpgEntry>[];
        final summary =
            _extractSummary(epgEntries) ?? _defaultSummary(channelLabel);
        final rating = _extractRating(summary);
        final actors = _extractActors(summary);

        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Center(
                          child: Text(
                            showName
                                .split(' ')
                                .map((w) => w.isNotEmpty ? w[0] : '')
                                .take(2)
                                .join(),
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 28,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              showName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              children: [
                                _InfoChip(label: channelLabel),
                                if (rating != null)
                                  _InfoChip(label: 'Rating $rating'),
                                _InfoChip(label: '${episodes.length} Episodes'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    summary,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13,
                        height: 1.6),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (actors != null) ...[
                    const SizedBox(height: 14),
                    Text('Starring: $actors',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _extractSummary(List<EpgEntry> entries) {
    final text = entries.isNotEmpty ? entries.first.description : '';
    if (text.trim().isEmpty) return null;
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  String? _extractRating(String text) {
    final match = RegExp(
            r'([0-9](?:\.[0-9])?)\s*/\s*10|rating[:\s]+([0-9](?:\.[0-9])?)',
            caseSensitive: false)
        .firstMatch(text);
    return match == null ? null : (match.group(1) ?? match.group(2));
  }

  String? _extractActors(String text) {
    final match = RegExp(r'(?:Starring|Cast|Actors?)[:\-]\s*([^\n\.]+)',
            caseSensitive: false)
        .firstMatch(text);
    return match?.group(1)?.trim();
  }

  String _defaultSummary(String channelLabel) {
    return 'Browse episodes for $showName on $channelLabel. Tap any episode to watch it instantly and see more show details.';
  }
}

class _HeroBanner extends StatelessWidget {
  final String showName;
  final String heroLogo;
  final VoidCallback onBack;

  const _HeroBanner(
      {required this.showName, required this.heroLogo, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred backdrop
          if (heroLogo.isNotEmpty)
            ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: CachedNetworkImage(
                  imageUrl: heroLogo,
                  fit: BoxFit.cover,
                  color: Colors.black.withValues(alpha: 0.55),
                  colorBlendMode: BlendMode.darken,
                  errorWidget: (ctx, url, err) => const SizedBox.shrink(),
                ),
              ),
            ),
          // Dark overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  SakuraTheme.background.withValues(alpha: 0.3),
                  SakuraTheme.background,
                ],
              ),
            ),
          ),
          // Left pink accent line
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: SakuraTheme.sakuraPink),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(42, 28, 32, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: onBack,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Row(
                          children: [
                            Icon(Icons.chevron_left_rounded,
                                color: SakuraTheme.sakuraPink
                                    .withValues(alpha: 0.8),
                                size: 20),
                            Text(
                              'TV Shows',
                              style: TextStyle(
                                  color: SakuraTheme.sakuraPink
                                      .withValues(alpha: 0.8),
                                  fontSize: 13,
                                  fontFamily: 'Manrope'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  showName,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonSelector extends StatelessWidget {
  final List<String> seasons;
  final String selected;
  final ValueChanged<String> onChanged;

  const _SeasonSelector(
      {required this.seasons, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
        itemCount: seasons.length,
        separatorBuilder: (ctx, i) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final season = seasons[i];
          final isActive = season == selected;
          return GestureDetector(
            onTap: () => onChanged(season),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? SakuraTheme.sakuraPink.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? SakuraTheme.sakuraPink.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  season,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    color: isActive
                        ? SakuraTheme.sakuraPink
                        : Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EpisodeRow extends StatefulWidget {
  final IptvMedia episode;
  final String showName;
  final int index;

  const _EpisodeRow(
      {required this.episode, required this.showName, required this.index});

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  bool _hovered = false;

  String get _episodeLabel {
    // Strip show name prefix from episode name for clean display
    final stripped = widget.episode.name
        .replaceFirst(widget.showName, '')
        .trim()
        .replaceFirst(RegExp(r'^[-–\s]+'), '');
    return stripped.isEmpty ? widget.episode.name : stripped;
  }

  String _cleanSubtitle(String text) {
    final cleaned = text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    if (cleaned.isEmpty) return '';
    if (_looksLikeUrl(cleaned)) return '';
    return cleaned.length > 80 ? '${cleaned.substring(0, 80)}…' : cleaned;
  }

  String get _episodeNumber {
    final m = RegExp(r'S(\d+)\s*E(\d+)', caseSensitive: false)
        .firstMatch(widget.episode.name);
    if (m != null) {
      return 'S${m.group(1)!.padLeft(2, '0')}E${m.group(2)!.padLeft(2, '0')}';
    }
    return 'EP ${widget.index + 1}';
  }

  bool _looksLikeUrl(String text) {
    return RegExp(
            r'^(https?:\/\/|www\.|ftp:\/\/|[A-Za-z0-9._%-]+\.[A-Za-z]{2,}\/)',
            caseSensitive: false)
        .hasMatch(text);
  }

  String _cleanTitle(String raw, String? signal) {
    final candidate = raw.trim();
    if (candidate.isEmpty || _looksLikeUrl(candidate)) {
      final fallback = signal?.trim();
      if (fallback != null && fallback.isNotEmpty && !_looksLikeUrl(fallback)) {
        return fallback;
      }
      return widget.episode.name.contains('/')
          ? 'Episode ${widget.index + 1}'
          : 'Episode';
    }
    return candidate;
  }

  String _buildEpisodeTitle(String? epgTitle) {
    final raw = _episodeLabel;
    final title = _cleanTitle(epgTitle ?? raw, widget.episode.tvgName);
    return title;
  }

  String? _parseActors(String text) {
    final match = RegExp(r'(?:Starring|Cast|Actors?)[:\-]\s*([^\n\.]+)',
            caseSensitive: false)
        .firstMatch(text);
    return match?.group(1)?.trim();
  }

  String? _parseRating(String text) {
    final match = RegExp(
            r'([0-9](?:\.[0-9])?)\s*/\s*10|rating[:\s]+([0-9](?:\.[0-9])?)',
            caseSensitive: false)
        .firstMatch(text);
    return match == null ? null : (match.group(1) ?? match.group(2));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => IptvPlayerScreen(media: widget.episode)),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: _hovered
                  ? SakuraTheme.sakuraPink.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovered
                    ? SakuraTheme.sakuraPink.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: Consumer<IptvProvider>(
              builder: (context, provider, _) {
                final epgEntries =
                    provider.getEpgForChannel(widget.episode.tvgId);
                final epgTitle =
                    epgEntries.isNotEmpty ? epgEntries.first.title : null;
                final epgDescription =
                    epgEntries.isNotEmpty ? epgEntries.first.description : '';
                final title = _buildEpisodeTitle(epgTitle);
                final subtitle = _cleanSubtitle(epgDescription);
                final rating = _parseRating(epgDescription);
                final actors = _parseActors(epgDescription);

                return Row(
                  children: [
                    // Thumbnail
                    _EpisodeThumbnail(logo: widget.episode.logo),
                    const SizedBox(width: 16),
                    // Episode number badge
                    Container(
                      width: 70,
                      alignment: Alignment.center,
                      child: Text(
                        _episodeNumber,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: SakuraTheme.sakuraPink.withValues(alpha: 0.8),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Title and metadata
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Manrope',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle.isNotEmpty
                                ? subtitle
                                : widget.episode.group,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12,
                                height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (rating != null)
                                _MiniChip(
                                    label: '$rating / 10',
                                    color: SakuraTheme.sakuraPink),
                              if (actors != null) ...[
                                const SizedBox(width: 6),
                                _MiniChip(
                                    label: 'Cast',
                                    color: const Color(0xFF7F5EFF)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Play button
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _hovered ? 1.0 : 0.3,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                SakuraTheme.sakuraPink.withValues(alpha: 0.15),
                            border: Border.all(
                                color: SakuraTheme.sakuraPink
                                    .withValues(alpha: 0.4)),
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: SakuraTheme.sakuraPink, size: 20),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeThumbnail extends StatelessWidget {
  final String logo;

  const _EpisodeThumbnail({required this.logo});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(11),
        bottomLeft: Radius.circular(11),
      ),
      child: SizedBox(
        width: 142,
        height: 80,
        child: logo.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: logo,
                fit: BoxFit.cover,
                errorWidget: (ctx, url, err) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: SakuraTheme.sakuraPink.withValues(alpha: 0.06),
      child: Center(
        child: Icon(Icons.play_circle_outline_rounded,
            color: SakuraTheme.sakuraPink.withValues(alpha: 0.25), size: 28),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tv_off_rounded,
              size: 64, color: SakuraTheme.sakuraPink.withValues(alpha: 0.12)),
          const SizedBox(height: 16),
          Text(
            'No shows found',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 15,
                fontFamily: 'Manrope'),
          ),
        ],
      ),
    );
  }
}
