import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/music_provider.dart';
import '../../providers/media_provider.dart';
import '../../models/music_models.dart';
import '../../models/media_model.dart';
import 'music_details_page.dart';
import 'dart:ui';

class MusicSearchPage extends StatefulWidget {
  final VoidCallback? onPlayMedia;
  const MusicSearchPage({super.key, this.onPlayMedia});

  @override
  State<MusicSearchPage> createState() => _MusicSearchPageState();
}

class _MusicSearchPageState extends State<MusicSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val, MusicProvider provider) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      provider.search(val);
    });
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final mediaProvider = Provider.of<MediaProvider>(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildSearchHeader(musicProvider),
          Expanded(
            child: musicProvider.isSearching
                ? const Center(child: CircularProgressIndicator())
                : _buildResults(musicProvider, mediaProvider, widget.onPlayMedia),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader(MusicProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Music Library',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.sync_rounded, color: Colors.white),
                onPressed: () {
                  final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
                  mediaProvider.scanAllFolders();
                },
                tooltip: 'Refresh Library',
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _searchController,
            onChanged: (val) => _onSearchChanged(val, provider),
            style: const TextStyle(color: Colors.black),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'What do you want to listen to?',
              hintStyle: const TextStyle(color: Colors.black54),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.black),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.black),
                      onPressed: () {
                        _searchController.clear();
                        provider.search('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(MusicProvider provider, MediaProvider mediaProvider, VoidCallback? onPlayMedia) {
    if (provider.searchResults.isEmpty) {
      return _buildEmptyState();
    }

    return _Results(
      results: provider.searchResults,
      mediaProvider: mediaProvider,
      musicProvider: provider,
      onPlayMedia: onPlayMedia,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note_rounded,
            size: 80,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'Discover something new',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  final MusicSearchResults results;
  final MediaProvider mediaProvider;
  final MusicProvider musicProvider;
  final VoidCallback? onPlayMedia;

  const _Results({
    required this.results,
    required this.mediaProvider,
    required this.musicProvider,
    this.onPlayMedia,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        if (results.albums.isNotEmpty) ...[
          const Text('Albums', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: results.albums.length,
              itemBuilder: (context, index) {
                return _AlbumCard(
                  album: results.albums[index],
                  onPlayMedia: onPlayMedia,
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
        if (results.artists.isNotEmpty) ...[
          const Text('Artists', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: results.artists.length,
              itemBuilder: (context, index) {
                return _ArtistCard(
                  artist: results.artists[index],
                  onPlayMedia: onPlayMedia,
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
        if (results.tracks.isNotEmpty) ...[
          const Text('Songs', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: results.tracks.length,
            itemBuilder: (context, index) {
              return _TrackTile(
                track: results.tracks[index],
                mediaProvider: mediaProvider,
                musicProvider: musicProvider,
                onPlayMedia: onPlayMedia,
              );
            },
          ),
        ],
      ],
    );
  }
}

class _TrackTile extends StatelessWidget {
  final MusicTrack track;
  final MediaProvider mediaProvider;
  final MusicProvider musicProvider;
  final VoidCallback? onPlayMedia;

  const _TrackTile({
    required this.track,
    required this.mediaProvider,
    required this.musicProvider,
    this.onPlayMedia,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MusicMatch?>(
      future: musicProvider.findAudioSource(track, mediaProvider.mediaFiles),
      builder: (context, snapshot) {
        final match = snapshot.data;
        final isAvailable = match != null;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          leading: InkWell(
            onTap: track.albumId != null ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MusicDetailsPage(
                    id: track.albumId!,
                    type: MusicDetailsType.album,
                    title: track.albumName ?? 'Album',
                    artworkUrl: track.albumArtworkUrl,
                    onPlayMedia: onPlayMedia,
                  ),
                ),
              );
            } : null,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                image: track.albumArtworkUrl != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(track.albumArtworkUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
                color: Colors.white10,
              ),
              child: track.albumArtworkUrl == null
                  ? const Icon(Icons.music_note_rounded, color: Colors.white24)
                  : null,
            ),
          ),
          title: Text(track.title, style: TextStyle(color: isAvailable ? Colors.white : Colors.white38, fontWeight: FontWeight.bold)),
          subtitle: InkWell(
            onTap: track.artistId != null ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MusicDetailsPage(
                    id: track.artistId!,
                    type: MusicDetailsType.artist,
                    title: track.artistName ?? 'Artist',
                    onPlayMedia: onPlayMedia,
                  ),
                ),
              );
            } : null,
            child: Text(track.artistName ?? 'Unknown Artist', style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          trailing: isAvailable
              ? const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFAAC7FF))
              : const Icon(Icons.cloud_download_rounded, color: Colors.white12),
          onTap: isAvailable ? () {
            final file = mediaProvider.mediaFiles.firstWhere(
              (f) => f.filePath == match!.localFilePath,
            );
            mediaProvider.playMedia(file);
            onPlayMedia?.call();
          } : null,
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final MusicAlbum album;
  final VoidCallback? onPlayMedia;
  const _AlbumCard({required this.album, this.onPlayMedia});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MusicDetailsPage(
              id: album.id,
              type: MusicDetailsType.album,
              title: album.name,
              artworkUrl: album.artworkUrl,
              onPlayMedia: onPlayMedia,
            ),
          ),
        );
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1,
                child: album.artworkUrl != null
                    ? CachedNetworkImage(
                        imageUrl: album.artworkUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.white10),
                      )
                    : Container(color: Colors.white10, child: const Icon(Icons.album_rounded, color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 8),
            Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            Text(album.artistName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final MusicArtist artist;
  final VoidCallback? onPlayMedia;
  const _ArtistCard({required this.artist, this.onPlayMedia});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MusicDetailsPage(
              id: artist.id,
              type: MusicDetailsType.artist,
              title: artist.name,
              artworkUrl: artist.imageUrl,
              onPlayMedia: onPlayMedia,
            ),
          ),
        );
      },
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            ClipOval(
              child: SizedBox(
                width: 80,
                height: 80,
                child: artist.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: artist.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.white10),
                      )
                    : Container(color: Colors.white10, child: const Icon(Icons.person_rounded, color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 8),
            Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
