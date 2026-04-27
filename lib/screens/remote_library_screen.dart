import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/remote_media_provider.dart';
import '../providers/media_provider.dart';

enum RemoteLibrarySection { movies, tv, music, nsfw }

class RemoteLibraryScreen extends StatefulWidget {
  final RemoteLibrarySection? initialSection;
  final VoidCallback? onPlayMedia;
  const RemoteLibraryScreen({super.key, this.initialSection, this.onPlayMedia});

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
        final movies = allMedia.where((m) => m.mediaKind == 'movie').toList();
        final tv = allMedia.where((m) => m.mediaKind == 'tv').toList();
        final music = allMedia.where((m) => m.mediaKind == 'audio').toList();
        final nsfw = allMedia.where((m) => m.contentType == 'adult').toList();

        final hasSearch = _searchController.text.isNotEmpty;
        final ytResults = mediaProvider.youtubeSearchResults;

        return Column(
          children: [
            _buildTabs(remoteProvider),
            if (_section == RemoteLibrarySection.music)
              _buildSearchBar(mediaProvider),
            Expanded(
              child: ListView(
                children: [
                  if (_section == RemoteLibrarySection.music && hasSearch) ...[
                    _buildSectionHeader('YouTube Results'),
                    _buildYoutubeResults(ytResults, remoteProvider),
                    const Divider(height: 32),
                    _buildSectionHeader('Remote Library'),
                  ],
                  _buildGrid(_section == RemoteLibrarySection.movies
                      ? movies
                      : (_section == RemoteLibrarySection.tv
                          ? tv
                          : (_section == RemoteLibrarySection.nsfw
                              ? nsfw
                              : music))),
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
          onChanged: (val) => mediaProvider.setSearchQuery(val),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search music on YouTube...',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded,
                color: Colors.white38, size: 20),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      mediaProvider.setSearchQuery('');
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

  Widget _buildGrid(List<RemoteMediaFile> items) {
    if (items.isEmpty) {
      final authError = Provider.of<RemoteMediaProvider>(context).authError;
      final serverSize =
          Provider.of<RemoteMediaProvider>(context).remoteLibrarySize;

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 64.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                  authError != null
                      ? Icons.lock_person_rounded
                      : Icons.folder_open_rounded,
                  size: 48,
                  color: Colors.white24),
              const SizedBox(height: 16),
              Text(
                authError ??
                    (serverSize > 0 ? 'Syncing library...' : 'No media found'),
                style: const TextStyle(color: Colors.white38),
              ),
              if (authError != null)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text('Approve this device on the Windows app',
                      style: TextStyle(color: Color(0xFFE9B3FF), fontSize: 12)),
                ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.7,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _MediaCard(
          item: item,
          onTap: () async {
            await Provider.of<RemoteMediaProvider>(context, listen: false)
                .playMedia(item);
            if (!context.mounted) return;
            widget.onPlayMedia?.call();
          },
        );
      },
    );
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.coverArtUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.coverArtUrl!, fit: BoxFit.cover)
                  : Container(
                      color: Colors.white10,
                      child: Center(
                        child: Icon(
                          item.isVideo
                              ? Icons.movie_rounded
                              : Icons.audiotrack_rounded,
                          color: Colors.white24,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (item.artist != null)
            Text(
              item.artist!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
