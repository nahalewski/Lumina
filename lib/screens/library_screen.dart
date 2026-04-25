import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media_model.dart';
import '../providers/media_provider.dart';
import '../providers/subtitle_provider.dart';

enum _LibrarySection { movies, tv }

class LibraryScreen extends StatefulWidget {
  final VoidCallback? onPlayMedia;
  const LibraryScreen({super.key, this.onPlayMedia});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _LibrarySection _section = _LibrarySection.movies;
  String? _selectedShow;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MediaProvider, SubtitleProvider>(
      builder: (context, provider, subtitleProvider, _) {
        provider.setSubtitleProvider(subtitleProvider);
        final movies = provider.movieFiles;
        final tvFiles = provider.tvFiles;
        final shows = _groupShows(tvFiles);

        if (_selectedShow != null) {
          return _ShowDetailView(
            showTitle: _selectedShow!,
            episodes: shows[_selectedShow!] ?? const [],
            onBack: () => setState(() => _selectedShow = null),
            onPlay: (episode) => _play(provider, episode),
            onQueue: (episode) => _queue(provider, episode),
            onDelete: (episode) => _confirmDelete(provider, episode),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              section: _section,
              movieCount: movies.length,
              showCount: shows.length,
              episodeCount: tvFiles.length,
              isLoading: provider.isLoading,
              onSectionChanged: (section) => setState(() {
                _section = section;
                _selectedShow = null;
              }),
              onScan: provider.scanLibraryMetadata,
              onAdd: provider.pickMediaFiles,
            ),
            _SearchAndFilters(
              controller: _searchController,
              provider: provider,
              hint: _section == _LibrarySection.movies
                  ? 'Search movies, actors, genres, files...'
                  : 'Search shows, seasons, episodes, actors...',
            ),
            Expanded(
              child: _section == _LibrarySection.movies
                    ? _MoviesGrid(
                        movies: movies,
                        onPlay: (movie) => _play(provider, movie),
                        onQueue: (movie) => _queue(provider, movie),
                        onDelete: (movie) => _confirmDelete(provider, movie),
                      )
                    : _ShowsGrid(
                        shows: shows,
                        onOpenShow: (title) =>
                            setState(() => _selectedShow = title),
                        onDelete: (media) => _confirmDelete(provider, media),
                      ),
            ),
          ],
        );
      },
    );
  }

  Map<String, List<MediaFile>> _groupShows(List<MediaFile> episodes) {
    final grouped = <String, List<MediaFile>>{};
    for (final episode in episodes) {
      final title = episode.showTitle ??
          episode.animeTitle ??
          episode.parsedShowTitle ??
          'Uncategorized';
      grouped.putIfAbsent(title, () => []).add(episode);
    }
    for (final items in grouped.values) {
      items.sort((a, b) {
        final season = (a.season ?? 0).compareTo(b.season ?? 0);
        if (season != 0) return season;
        return (a.episode ?? 0).compareTo(b.episode ?? 0);
      });
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  void _play(MediaProvider provider, MediaFile media) {
    provider.playMedia(media);
    widget.onPlayMedia?.call();
  }

  void _queue(MediaProvider provider, MediaFile media) {
    provider.addToQueue(media);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${media.displayTitle} added to queue'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF0A84FF),
      ),
    );
  }

  void _confirmDelete(MediaProvider provider, MediaFile media) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Remove from Library?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove "${media.displayTitle}"? This will not delete the actual file from your disk.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              provider.removeMediaFile(media);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Removed ${media.displayTitle}'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final _LibrarySection section;
  final int movieCount;
  final int showCount;
  final int episodeCount;
  final bool isLoading;
  final ValueChanged<_LibrarySection> onSectionChanged;
  final VoidCallback onScan;
  final VoidCallback onAdd;

  const _Header({
    required this.section,
    required this.movieCount,
    required this.showCount,
    required this.episodeCount,
    required this.isLoading,
    required this.onSectionChanged,
    required this.onScan,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Library',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                '$movieCount movies | $showCount shows | $episodeCount episodes',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          );
          final controls = Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SegmentedLibraryTabs(
                  section: section, onChanged: onSectionChanged),
              _HeaderButton(
                icon: Icons.refresh_rounded,
                label: 'Scan Metadata',
                onTap: onScan,
                loading: isLoading,
              ),
              _HeaderButton(
                icon: Icons.add_rounded,
                label: 'Add Files',
                onTap: onAdd,
                loading: false,
              ),
            ],
          );

          if (constraints.maxWidth < 940) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 12),
                controls,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              controls,
            ],
          );
        },
      ),
    );
  }
}

class _SegmentedLibraryTabs extends StatelessWidget {
  final _LibrarySection section;
  final ValueChanged<_LibrarySection> onChanged;

  const _SegmentedLibraryTabs({required this.section, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          _TabButton(
            icon: Icons.movie_rounded,
            label: 'Movies',
            selected: section == _LibrarySection.movies,
            onTap: () => onChanged(_LibrarySection.movies),
          ),
          _TabButton(
            icon: Icons.tv_rounded,
            label: 'TV Shows',
            selected: section == _LibrarySection.tv,
            onTap: () => onChanged(_LibrarySection.tv),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFAAC7FF).withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? const Color(0xFFAAC7FF) : Colors.white54,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  final TextEditingController controller;
  final MediaProvider provider;
  final String hint;

  const _SearchAndFilters({
    required this.controller,
    required this.provider,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.32),
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                        onPressed: () {
                          controller.clear();
                          provider.setSearchQuery('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 12,
                ),
                border: _inputBorder(0.1),
                enabledBorder: _inputBorder(0.1),
                focusedBorder: _inputBorder(
                  0.5,
                  color: const Color(0xFFAAC7FF),
                ),
              ),
              onChanged: provider.setSearchQuery,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: provider.currentFilter == LibraryFilter.all,
                        onSelected: () => provider.setFilter(LibraryFilter.all),
                      ),
                      _FilterChip(
                        label: 'Favorites',
                        selected:
                            provider.currentFilter == LibraryFilter.favorites,
                        onSelected: () =>
                            provider.setFilter(LibraryFilter.favorites),
                      ),
                      _FilterChip(
                        label: 'Watched',
                        selected:
                            provider.currentFilter == LibraryFilter.watched,
                        onSelected: () =>
                            provider.setFilter(LibraryFilter.watched),
                      ),
                      _FilterChip(
                        label: 'Unwatched',
                        selected:
                            provider.currentFilter == LibraryFilter.unwatched,
                        onSelected: () =>
                            provider.setFilter(LibraryFilter.unwatched),
                      ),
                      _FilterChip(
                        label: 'Processed',
                        selected:
                            provider.currentFilter == LibraryFilter.processed,
                        onSelected: () =>
                            provider.setFilter(LibraryFilter.processed),
                      ),
                      _FilterChip(
                        label: 'Anime',
                        selected: provider.currentFilter == LibraryFilter.anime,
                        onSelected: () =>
                            provider.setFilter(LibraryFilter.anime),
                      ),
                      _FilterChip(
                        label: 'Hentai',
                        selected:
                            provider.currentFilter == LibraryFilter.hentai,
                        onSelected: () =>
                            provider.setFilter(LibraryFilter.hentai),
                      ),
                      _FilterChip(
                        label: 'General',
                        selected:
                            provider.currentFilter == LibraryFilter.general,
                        onSelected: () =>
                            provider.setFilter(LibraryFilter.general),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _SortMenu(provider: provider),
            ],
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _inputBorder(double alpha, {Color color = Colors.white}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color.withValues(alpha: alpha)),
    );
  }
}

class _SortMenu extends StatelessWidget {
  final MediaProvider provider;

  const _SortMenu({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: DropdownButton<LibrarySort>(
        value: provider.currentSort,
        dropdownColor: const Color(0xFF1E1E22),
        underline: const SizedBox.shrink(),
        icon: Icon(
          Icons.sort_rounded,
          color: Colors.white.withValues(alpha: 0.5),
          size: 18,
        ),
        items: const [
          DropdownMenuItem(
            value: LibrarySort.title,
            child: Text('A-Z', style: _menuStyle),
          ),
          DropdownMenuItem(
            value: LibrarySort.titleDesc,
            child: Text('Z-A', style: _menuStyle),
          ),
          DropdownMenuItem(
            value: LibrarySort.newestRelease,
            child: Text('Newest release', style: _menuStyle),
          ),
          DropdownMenuItem(
            value: LibrarySort.oldestRelease,
            child: Text('Oldest release', style: _menuStyle),
          ),
          DropdownMenuItem(
            value: LibrarySort.highestRated,
            child: Text('Highest rated', style: _menuStyle),
          ),
          DropdownMenuItem(
            value: LibrarySort.dateAdded,
            child: Text('Recently added', style: _menuStyle),
          ),
          DropdownMenuItem(
            value: LibrarySort.mostWatched,
            child: Text('Most watched', style: _menuStyle),
          ),
        ],
        onChanged: (value) {
          if (value != null) provider.setSort(value);
        },
      ),
    );
  }
}

const _menuStyle = TextStyle(fontSize: 12, color: Colors.white);

class _MoviesGrid extends StatelessWidget {
  final List<MediaFile> movies;
  final ValueChanged<MediaFile> onPlay;
  final ValueChanged<MediaFile> onQueue;
  final ValueChanged<MediaFile> onDelete;

  const _MoviesGrid({
    required this.movies,
    required this.onPlay,
    required this.onQueue,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) {
      return const _EmptyState(
        title: 'No movies yet',
        body: 'Add movie files or scan a folder to build your poster wall.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 354,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: movies.length,
      itemBuilder: (context, index) => _PosterCard(
        media: movies[index],
        subtitle: _movieSubtitle(movies[index]),
        onTap: () => onPlay(movies[index]),
        onQueue: () => onQueue(movies[index]),
        onDelete: () => onDelete(movies[index]),
      ),
    );
  }

  String _movieSubtitle(MediaFile movie) {
    final parts = [
      if (movie.releaseYear != null) movie.releaseYear.toString(),
      if (movie.rating != null) '${movie.rating!.toStringAsFixed(1)} rating',
      if (movie.resolution != null) movie.resolution!,
      if (movie.language != null) movie.language!,
    ];
    return parts.isEmpty ? movie.durationFormatted : parts.join(' | ');
  }
}

class _ShowsGrid extends StatelessWidget {
  final Map<String, List<MediaFile>> shows;
  final ValueChanged<String> onOpenShow;
  final ValueChanged<MediaFile> onDelete;

  const _ShowsGrid({
    required this.shows,
    required this.onOpenShow,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (shows.isEmpty) {
      return const _EmptyState(
        title: 'No TV shows yet',
        body:
            'Files like Naruto.S02E04.mkv will appear as Show -> Season -> Episode.',
      );
    }
    final titles = shows.keys.toList();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 336,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: titles.length,
      itemBuilder: (context, index) {
        final title = titles[index];
        final episodes = shows[title]!;
        final seasons = episodes.map((e) => e.season ?? 1).toSet().length;
        return _ShowCard(
          title: title,
          episodes: episodes.length,
          seasons: seasons,
          coverUrl: episodes.first.posterUrl ?? episodes.first.coverArtUrl,
          onTap: () => onOpenShow(title),
          onDelete: () => onDelete(episodes.first),
        );
      },
    );
  }
}

class _ShowDetailView extends StatelessWidget {
  final String showTitle;
  final List<MediaFile> episodes;
  final VoidCallback onBack;
  final ValueChanged<MediaFile> onPlay;
  final ValueChanged<MediaFile> onQueue;
  final ValueChanged<MediaFile> onDelete;

  const _ShowDetailView({
    required this.showTitle,
    required this.episodes,
    required this.onBack,
    required this.onPlay,
    required this.onQueue,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final seasons = <int, List<MediaFile>>{};
    for (final episode in episodes) {
      seasons.putIfAbsent(episode.season ?? 1, () => []).add(episode);
    }
    final first = episodes.isEmpty ? null : episodes.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                ),
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showTitle,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${seasons.length} seasons | ${episodes.length} episodes',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (first?.rating != null)
                _MetaPill(
                  icon: Icons.star_rounded,
                  label: first!.rating!.toStringAsFixed(1),
                ),
              if (first?.releaseYear != null)
                _MetaPill(
                  icon: Icons.calendar_month_rounded,
                  label: first!.releaseYear.toString(),
                ),
            ],
          ),
        ),
        if (first?.synopsis != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
            child: Text(
              first!.synopsis!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            children: seasons.entries.map((season) {
              return _SeasonBlock(
                seasonNumber: season.key,
                episodes: season.value,
                onPlay: onPlay,
                onQueue: onQueue,
                onDelete: onDelete,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SeasonBlock extends StatelessWidget {
  final int seasonNumber;
  final List<MediaFile> episodes;
  final ValueChanged<MediaFile> onPlay;
  final ValueChanged<MediaFile> onQueue;
  final ValueChanged<MediaFile> onDelete;

  const _SeasonBlock({
    required this.seasonNumber,
    required this.episodes,
    required this.onPlay,
    required this.onQueue,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Season ${seasonNumber.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Manrope',
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ...episodes.map(
            (episode) => _EpisodeTile(
              episode: episode,
              onTap: () => onPlay(episode),
              onAddToQueue: () => onQueue(episode),
              onDelete: () => onDelete(episode),
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final MediaFile media;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onQueue;
  final VoidCallback onDelete;

  const _PosterCard({
    required this.media,
    required this.subtitle,
    required this.onTap,
    required this.onQueue,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = media.posterUrl ?? media.coverArtUrl;
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition, onDelete);
      },
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ArtworkFrame(
              imageUrl: imageUrl,
              icon: Icons.movie_creation_rounded,
              child: _CardActions(media: media, onQueue: onQueue),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            media.libraryTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          if (media.genres.isNotEmpty)
            Text(
              media.genres.take(2).join(' | '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFAAC7FF), fontSize: 11),
            ),
        ],
      ),
    ),
  );
}
}

class _ShowCard extends StatelessWidget {
  final String title;
  final int episodes;
  final int seasons;
  final String? coverUrl;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ShowCard({
    required this.title,
    required this.episodes,
    required this.seasons,
    required this.coverUrl,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition, onDelete);
      },
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ArtworkFrame(imageUrl: coverUrl, icon: Icons.tv_rounded),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
            Text(
              '$seasons seasons | $episodes episodes',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
        ],
      ),
    ),
  );
}
}

class _ArtworkFrame extends StatelessWidget {
  final String? imageUrl;
  final IconData icon;
  final Widget? child;

  const _ArtworkFrame({this.imageUrl, required this.icon, this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        image: imageUrl != null
            ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (imageUrl == null)
            Center(child: Icon(icon, size: 48, color: Colors.white10)),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _CardActions extends StatelessWidget {
  final MediaFile media;
  final VoidCallback onQueue;

  const _CardActions({required this.media, required this.onQueue});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (media.isWatched)
                const _MetaPill(
                  icon: Icons.check_circle_rounded,
                  label: 'Watched',
                ),
              const Spacer(),
              Row(
                children: [
                  if (media.isFavorite)
                    const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFFE9B3FF),
                      size: 18,
                    ),
                  const Spacer(),
                  IconButton(
                    onPressed: onQueue,
                    icon: const Icon(Icons.queue_rounded, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final MediaFile episode;
  final VoidCallback onTap;
  final VoidCallback onAddToQueue;
  final VoidCallback onDelete;

  const _EpisodeTile({
    required this.episode,
    required this.onTap,
    required this.onAddToQueue,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final season = episode.season ?? episode.parsedSeason ?? 1;
    final ep = episode.episode ?? episode.parsedEpisode ?? 0;
    final code =
        'S${season.toString().padLeft(2, '0')}E${ep.toString().padLeft(2, '0')}';
    final title =
        episode.episodeTitle ?? episode.parsedEpisodeTitle ?? episode.fileName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          _showContextMenu(context, details.globalPosition, onDelete);
        },
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              _EpisodeThumb(episode: episode, code: code),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$code - $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        if (episode.airDate != null) episode.airDate!,
                        episode.durationFormatted,
                        if (episode.rating != null)
                          '${episode.rating!.toStringAsFixed(1)} rating',
                        if (episode.resolution != null) episode.resolution!,
                        if (episode.language != null) episode.language!,
                      ].join(' | '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    if (episode.synopsis != null)
                      Text(
                        episode.synopsis!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onAddToQueue,
                icon: Icon(
                  Icons.queue_rounded,
                  color: Colors.white.withValues(alpha: 0.45),
                  size: 20,
                ),
              ),
              const Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white24,
                size: 32,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

class _EpisodeThumb extends StatelessWidget {
  final MediaFile episode;
  final String code;

  const _EpisodeThumb({required this.episode, required this.code});

  @override
  Widget build(BuildContext context) {
    final imageUrl = episode.thumbnailUrl ?? episode.backdropUrl;
    return Container(
      width: 92,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFE9B3FF).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        image: imageUrl != null
            ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
            : null,
      ),
      child: imageUrl == null
          ? Center(
              child: Text(
                code,
                style: const TextStyle(
                  color: Color(0xFFE9B3FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : null,
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else
              Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onSelected,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFAAC7FF).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFFAAC7FF).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFFAAC7FF)
                  : Colors.white.withValues(alpha: 0.62),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFFAAC7FF)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String body;

  const _EmptyState({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_rounded,
            size: 64,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

void _showContextMenu(BuildContext context, Offset position, VoidCallback onDelete) {
  showMenu(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    color: const Color(0xFF1E1E22),
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    items: [
      PopupMenuItem(
        onTap: onDelete,
        child: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
            SizedBox(width: 10),
            Text('Remove from Library', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
        ),
      ),
    ],
  );
}
