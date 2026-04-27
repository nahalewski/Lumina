import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/remote_media_provider.dart';
import '../providers/media_provider.dart';

enum RemoteLibrarySection { movies, tv, music, nsfw }

class RemoteLibraryScreen extends StatefulWidget {
  final RemoteLibrarySection? initialSection;
  final VoidCallback? onPlayMedia;
  final bool showTabs;
  const RemoteLibraryScreen({
    super.key,
    this.initialSection,
    this.onPlayMedia,
    this.showTabs = true,
  });

  @override
  State<RemoteLibraryScreen> createState() => _RemoteLibraryScreenState();
}

class _RemoteLibraryScreenState extends State<RemoteLibraryScreen> {
  late RemoteLibrarySection _section;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection ?? RemoteLibrarySection.movies;

    // Connect to server on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<RemoteMediaProvider>(context, listen: false)
          .connectAndFetch();
    });
  }

  @override
  void didUpdateWidget(RemoteLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSection != oldWidget.initialSection &&
        widget.initialSection != null) {
      setState(() {
        _section = widget.initialSection!;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<RemoteMediaProvider, MediaProvider>(
      builder: (context, remoteProvider, mediaProvider, _) {
        if (remoteProvider.isLoading) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFE9B3FF)));
        }

        if (remoteProvider.baseUrl == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off_rounded,
                    size: 64, color: Colors.white38),
                const SizedBox(height: 16),
                const Text('No server found',
                    style: TextStyle(color: Colors.white, fontSize: 18)),
                const SizedBox(height: 8),
                const Text(
                    'Make sure Lumina Media server is running on your network',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry Connection'),
                  onPressed: () =>
                      Provider.of<RemoteMediaProvider>(context, listen: false)
                          .connectAndFetch(),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE9B3FF)),
                ),
              ],
            ),
          );
        }

        final allMedia = remoteProvider.media;
        final query = _searchController.text.toLowerCase();
        final movies = allMedia
            .where((m) => m.mediaKind == 'movie' && m.contentType != 'adult')
            .where((m) => query.isEmpty || m.title.toLowerCase().contains(query))
            .toList();
        final tv = allMedia
            .where((m) => m.mediaKind == 'tv')
            .where((m) => query.isEmpty || m.title.toLowerCase().contains(query))
            .toList();
        final music = allMedia
            .where((m) => m.mediaKind == 'audio')
            .where((m) => query.isEmpty ||
                m.title.toLowerCase().contains(query) ||
                (m.artist?.toLowerCase().contains(query) ?? false))
            .toList();
        final nsfw = allMedia.where((m) => m.contentType == 'adult').toList();

        final hasSearch = _searchController.text.isNotEmpty;
        final ytResults = mediaProvider.youtubeSearchResults;

        return Column(
          children: [
            if (widget.showTabs) _buildTabs(remoteProvider),
            if (_section == RemoteLibrarySection.music ||
                _section == RemoteLibrarySection.movies ||
                _section == RemoteLibrarySection.tv)
              _buildSearchBar(mediaProvider),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (_section == RemoteLibrarySection.music && hasSearch) ...[
                    SliverToBoxAdapter(
                        child: _buildSectionHeader('YouTube Results')),
                    SliverToBoxAdapter(
                        child:
                            _buildYoutubeResults(ytResults, remoteProvider)),
                    const SliverToBoxAdapter(
                        child: Divider(height: 32, color: Colors.white10)),
                    SliverToBoxAdapter(
                        child: _buildSectionHeader('Library')),
                  ],
                  if (_section == RemoteLibrarySection.music)
                    ..._musicSlivers(music)
                  else if (_section == RemoteLibrarySection.tv)
                    ..._tvSlivers(tv)
                  else
                    ..._gridSlivers(_section == RemoteLibrarySection.movies
                        ? movies
                        : nsfw,
                        remoteProvider),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFAAC7FF),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSearchBar(MediaProvider mediaProvider) {
    final isMusic = _section == RemoteLibrarySection.music;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) {
            if (isMusic) mediaProvider.setSearchQuery(val);
            setState(() {});
          },
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: isMusic ? 'Search music or YouTube...' : 'Filter...',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded,
                color: Colors.white38, size: 20),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      if (isMusic) mediaProvider.setSearchQuery('');
                      setState(() {});
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildYoutubeResults(
      List<Map<String, String>> results, RemoteMediaProvider remoteProvider) {
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(
          child: Text('Searching YouTube...',
              style: TextStyle(color: Colors.white24)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: result['thumbnail'] ?? '',
              width: 56,
              height: 42,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  Container(color: Colors.white10, width: 56, height: 42),
            ),
          ),
          title: Text(result['title'] ?? 'Unknown',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(result['artist'] ?? 'Unknown Artist',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          trailing: IconButton(
            icon: const Icon(Icons.download_for_offline_rounded,
                color: Color(0xFFE9B3FF)),
            onPressed: () async {
              final success = await remoteProvider.downloadMusic(result);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Download started on server!'
                        : 'Failed to start download.'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildTabs(RemoteMediaProvider provider) {
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                onPressed: () => provider.connectAndFetch(),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: provider.isConnected
                        ? const Color(0xFF42E355)
                        : const Color(0xFFFF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          _TabButton(
            label: 'Movies',
            selected: _section == RemoteLibrarySection.movies,
            onTap: () => setState(() => _section = RemoteLibrarySection.movies),
          ),
          const SizedBox(width: 8),
          _TabButton(
            label: 'TV Shows',
            selected: _section == RemoteLibrarySection.tv,
            onTap: () => setState(() => _section = RemoteLibrarySection.tv),
          ),
          const SizedBox(width: 8),
          _TabButton(
            label: 'Music',
            selected: _section == RemoteLibrarySection.music,
            onTap: () => setState(() => _section = RemoteLibrarySection.music),
          ),
          const SizedBox(width: 8),
          _TabButton(
            label: 'NSFW',
            selected: _section == RemoteLibrarySection.nsfw,
            onTap: () => setState(() => _section = RemoteLibrarySection.nsfw),
          ),
        ],
      ),
    );
  }

  // ── Sliver builders (lazy — only visible items are constructed) ─────────

  List<Widget> _musicSlivers(List<RemoteMediaFile> items) {
    if (items.isEmpty) {
      return [
        const SliverFillRemaining(
          child: _EmptySection(
            icon: Icons.music_off_rounded,
            message: 'No music in library',
            hint: 'Add music on the Windows app',
          ),
        ),
      ];
    }

    final byAlbum = <String, List<RemoteMediaFile>>{};
    for (final track in items) {
      byAlbum.putIfAbsent(track.album ?? 'Unknown Album', () => []).add(track);
    }
    for (final list in byAlbum.values) {
      list.sort((a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0));
    }
    final albums = byAlbum.keys.toList()..sort();

    final slivers = <Widget>[];
    for (final album in albums) {
      final tracks = byAlbum[album]!;
      slivers.add(SliverToBoxAdapter(child: _buildSectionHeader(album)));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _MusicListTile(
            track: tracks[i],
            onTap: () async {
              await Provider.of<RemoteMediaProvider>(context, listen: false)
                  .playMedia(tracks[i]);
              if (!context.mounted) return;
              widget.onPlayMedia?.call();
            },
          ),
          childCount: tracks.length,
        ),
      ));
    }
    return slivers;
  }

  List<Widget> _tvSlivers(List<RemoteMediaFile> episodes) {
    if (episodes.isEmpty) {
      return [
        const SliverFillRemaining(
          child: _EmptySection(
            icon: Icons.tv_off_rounded,
            message: 'No TV shows in library',
            hint: 'Add TV shows on the Windows app',
          ),
        ),
      ];
    }

    final byShow = <String, List<RemoteMediaFile>>{};
    for (final ep in episodes) {
      final key = ep.showTitle?.isNotEmpty == true
          ? ep.showTitle!
          : _extractShowName(ep.title);
      byShow.putIfAbsent(key, () => []).add(ep);
    }
    for (final list in byShow.values) {
      list.sort((a, b) {
        final s = (a.season ?? 0).compareTo(b.season ?? 0);
        return s != 0 ? s : (a.episode ?? 0).compareTo(b.episode ?? 0);
      });
    }
    final shows = byShow.keys.toList()..sort();

    return [
      SliverToBoxAdapter(
        child: _TvShowsList(
          shows: shows,
          byShow: byShow,
          onPlayEpisode: (ep) async {
            await Provider.of<RemoteMediaProvider>(context, listen: false)
                .playMedia(ep);
            if (!context.mounted) return;
            widget.onPlayMedia?.call();
          },
        ),
      ),
    ];
  }

  List<Widget> _gridSlivers(
      List<RemoteMediaFile> items, RemoteMediaProvider remoteProvider) {
    if (items.isEmpty) {
      final authError = remoteProvider.authError;
      final serverSize = remoteProvider.remoteLibrarySize;
      return [
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    authError != null
                        ? Icons.lock_person_rounded
                        : Icons.folder_open_rounded,
                    size: 48,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    authError ??
                        (serverSize > 0
                            ? 'Loading library...'
                            : 'No media found'),
                    style: const TextStyle(color: Colors.white38),
                    textAlign: TextAlign.center,
                  ),
                  if (authError != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Approve this device on the Windows app',
                          style: TextStyle(
                              color: Color(0xFFE9B3FF), fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            childAspectRatio: 0.62,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, index) {
              final item = items[index];
              return _MediaCard(
                item: item,
                onTap: () async {
                  await Provider.of<RemoteMediaProvider>(context,
                          listen: false)
                      .playMedia(item);
                  if (!context.mounted) return;
                  widget.onPlayMedia?.call();
                },
              );
            },
            childCount: items.length,
          ),
        ),
      ),
    ];
  }

  static String _extractShowName(String title) {
    return title
        .replaceAll(RegExp(r'\bS\d{2}E\d{2}\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b\d+x\d+\b'), '')
        .replaceAll(RegExp(r'\(\d{4}\)'), '')
        .replaceAll(RegExp(r'[\._\-]+'), ' ')
        .trim();
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFE9B3FF).withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0xFFE9B3FF) : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white38,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final RemoteMediaFile item;
  final VoidCallback onTap;
  const _MediaCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final artUrl = item.posterUrl?.isNotEmpty == true
        ? item.posterUrl!
        : item.coverArtUrl;
    final subtitle = item.movieTitle?.isNotEmpty == true
        ? item.movieTitle!
        : (item.releaseDate?.length == 4 ? item.releaseDate! : '');
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: artUrl != null
                  ? CachedNetworkImage(
                      imageUrl: artUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      memCacheWidth: 320,
                      memCacheHeight: 480,
                      errorWidget: (_, __, ___) => _artPlaceholder(item),
                    )
                  : _artPlaceholder(item),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
        ],
      ),
    );
  }

  Widget _artPlaceholder(RemoteMediaFile item) => Container(
        color: const Color(0xFF1E1E22),
        child: Center(
          child: Icon(
            item.isVideo ? Icons.movie_rounded : Icons.audiotrack_rounded,
            color: Colors.white12,
            size: 32,
          ),
        ),
      );
}

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String message;
  final String hint;
  const _EmptySection(
      {required this.icon, required this.message, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white12),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(height: 6),
            Text(hint,
                style: const TextStyle(
                    color: Color(0xFFE9B3FF), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _MusicListTile extends StatelessWidget {
  final RemoteMediaFile track;
  final VoidCallback onTap;
  const _MusicListTile({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final art = track.coverArtUrl ?? track.posterUrl;
    final mins = track.duration.inMinutes;
    final secs = track.duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: art != null
            ? CachedNetworkImage(
                imageUrl: art,
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                memCacheWidth: 92,
                memCacheHeight: 92,
                errorWidget: (_, __, ___) => _musicIcon(),
              )
            : _musicIcon(),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        track.artist ?? 'Unknown Artist',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: Text(
        '$mins:$secs',
        style: const TextStyle(color: Colors.white24, fontSize: 11),
      ),
      onTap: onTap,
    );
  }

  Widget _musicIcon() => Container(
        width: 46,
        height: 46,
        color: const Color(0xFF1E1E22),
        child: const Icon(Icons.audiotrack_rounded,
            color: Colors.white24, size: 22),
      );
}

class _TvShowsList extends StatefulWidget {
  final List<String> shows;
  final Map<String, List<RemoteMediaFile>> byShow;
  final Future<void> Function(RemoteMediaFile) onPlayEpisode;

  const _TvShowsList(
      {required this.shows,
      required this.byShow,
      required this.onPlayEpisode});

  @override
  State<_TvShowsList> createState() => _TvShowsListState();
}

class _TvShowsListState extends State<_TvShowsList> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.shows.length,
      itemBuilder: (_, i) =>
          _buildShowRow(widget.shows[i], widget.byShow[widget.shows[i]]!),
    );
  }

  Widget _buildShowRow(String show, List<RemoteMediaFile> episodes) {
    final isExpanded = _expanded.contains(show);
    final art = episodes.first.posterUrl?.isNotEmpty == true
        ? episodes.first.posterUrl
        : episodes.first.coverArtUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (isExpanded) {
              _expanded.remove(show);
            } else {
              _expanded.add(show);
            }
          }),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: art != null
                      ? CachedNetworkImage(
                          imageUrl: art,
                          width: 52,
                          height: 74,
                          fit: BoxFit.cover,
                          memCacheWidth: 104,
                          memCacheHeight: 148,
                          errorWidget: (_, __, ___) => _showIcon(),
                        )
                      : _showIcon(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        show,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${episodes.length} episode${episodes.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: Colors.white38,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          for (final ep in episodes)
            _EpisodeTile(
                episode: ep,
                onTap: () => widget.onPlayEpisode(ep)),
        const Divider(height: 1, color: Colors.white10),
      ],
    );
  }

  Widget _showIcon() => Container(
        width: 52,
        height: 74,
        color: const Color(0xFF1E1E22),
        child: const Icon(Icons.tv_rounded, color: Colors.white12, size: 24),
      );
}

class _EpisodeTile extends StatelessWidget {
  final RemoteMediaFile episode;
  final VoidCallback onTap;
  const _EpisodeTile({required this.episode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = episode.season;
    final e = episode.episode;
    final label = (s != null && e != null)
        ? 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}'
        : '';
    final mins = episode.duration.inMinutes;
    final secs =
        episode.duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 32, vertical: 2),
      leading: label.isNotEmpty
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFAAC7FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(label,
                  style: const TextStyle(
                      color: Color(0xFFAAC7FF),
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            )
          : const Icon(Icons.play_circle_outline_rounded,
              color: Colors.white24, size: 20),
      title: Text(
        episode.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      trailing: Text('$mins:$secs',
          style: const TextStyle(color: Colors.white24, fontSize: 11)),
      onTap: onTap,
    );
  }
}
