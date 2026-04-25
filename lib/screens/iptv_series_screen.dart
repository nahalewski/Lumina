import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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

  void _back() => setState(() { _selectedShow = null; _selectedSeason = null; });

  @override
  Widget build(BuildContext context) {
    return Consumer<IptvProvider>(
      builder: (context, provider, child) {
        final grouped = provider.groupedSeries;

        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator(color: SakuraTheme.sakuraPink));
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: _selectedShow == null ? const Offset(-0.04, 0) : const Offset(0.04, 0),
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

class _ShowGrid extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final shows = grouped.keys
        .where((n) => n.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList()
      ..sort();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Header(showCount: shows.length, onSearchChanged: onSearchChanged)),
        if (shows.isEmpty)
          const SliverFillRemaining(child: _EmptyState())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.65,
                crossAxisSpacing: 18,
                mainAxisSpacing: 24,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final name = shows[i];
                  final seasons = grouped[name]!;
                  final logo = seasons.values.first.first.logo;
                  final seasonCount = seasons.length;
                  return _PosterCard(
                    name: name,
                    logo: logo,
                    seasonCount: seasonCount,
                    onTap: () => onShowTapped(name, seasons),
                  );
                },
                childCount: shows.length,
              ),
            ),
          ),
      ],
    );
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
              border: Border.all(color: SakuraTheme.sakuraPink.withValues(alpha: 0.3), width: 1),
            ),
            child: const Icon(Icons.live_tv_rounded, color: SakuraTheme.sakuraPink, size: 22),
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
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
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
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.3), size: 18),
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

  const _PosterCard({required this.name, required this.logo, required this.seasonCount, required this.onTap});

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
          transform: Matrix4.diagonal3Values(_hovered ? 1.04 : 1.0, _hovered ? 1.04 : 1.0, 1.0),
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
                        ? [BoxShadow(color: SakuraTheme.sakuraPink.withValues(alpha: 0.18), blurRadius: 18, spreadRadius: 2)]
                        : [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.logo.isNotEmpty)
                          Image.network(
                            widget.logo,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, st) => _posterFallback(),
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
                                colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
                              ),
                            ),
                          ),
                        ),
                        // Season badge
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            child: Text(
                              '${widget.seasonCount} ${widget.seasonCount == 1 ? 'Season' : 'Seasons'}',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
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
        child: Icon(Icons.live_tv_rounded, color: SakuraTheme.sakuraPink.withValues(alpha: 0.2), size: 40),
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

    // Pick hero image from first episode of selected season
    final heroLogo = episodes.isNotEmpty ? episodes.first.logo : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Hero banner ──────────────────────────────────────────
        _HeroBanner(showName: showName, heroLogo: heroLogo, onBack: onBack),

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

class _HeroBanner extends StatelessWidget {
  final String showName;
  final String heroLogo;
  final VoidCallback onBack;

  const _HeroBanner({required this.showName, required this.heroLogo, required this.onBack});

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
                child: Image.network(
                  heroLogo,
                  fit: BoxFit.cover,
                  color: Colors.black.withValues(alpha: 0.55),
                  colorBlendMode: BlendMode.darken,
                  errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
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
                            Icon(Icons.chevron_left_rounded, color: SakuraTheme.sakuraPink.withValues(alpha: 0.8), size: 20),
                            Text(
                              'TV Shows',
                              style: TextStyle(color: SakuraTheme.sakuraPink.withValues(alpha: 0.8), fontSize: 13, fontFamily: 'Manrope'),
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

  const _SeasonSelector({required this.seasons, required this.selected, required this.onChanged});

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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                    color: isActive ? SakuraTheme.sakuraPink : Colors.white.withValues(alpha: 0.6),
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

  const _EpisodeRow({required this.episode, required this.showName, required this.index});

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

  String get _episodeNumber {
    final m = RegExp(r'S(\d+)\s*E(\d+)', caseSensitive: false).firstMatch(widget.episode.name);
    if (m != null) {
      return 'S${m.group(1)!.padLeft(2, '0')}E${m.group(2)!.padLeft(2, '0')}';
    }
    return 'EP ${widget.index + 1}';
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
            MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: widget.episode)),
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
            child: Row(
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
                // Title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _episodeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Manrope',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                        color: SakuraTheme.sakuraPink.withValues(alpha: 0.15),
                        border: Border.all(color: SakuraTheme.sakuraPink.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: SakuraTheme.sakuraPink, size: 20),
                    ),
                  ),
                ),
              ],
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
            ? Image.network(
                logo,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, st) => _fallback(),
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
          Icon(Icons.tv_off_rounded, size: 64, color: SakuraTheme.sakuraPink.withValues(alpha: 0.12)),
          const SizedBox(height: 16),
          Text(
            'No shows found',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 15, fontFamily: 'Manrope'),
          ),
        ],
      ),
    );
  }
}
