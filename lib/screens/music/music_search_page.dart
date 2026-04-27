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
  const MusicSearchPage({super.key});

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
                : _buildResults(musicProvider, mediaProvider),
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
          const Text(
            'Search',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(MusicProvider musicProvider, MediaProvider mediaProvider) {
    final results = musicProvider.searchResults;
    if (musicProvider.isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1DB954)),
      );
    }

    if (results.isEmpty) {
      return const Center(
        child: Text(
          'Browse your favorite music',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final track = results[index];
        return _TrackTile(track: track, mediaProvider: mediaProvider, musicProvider: musicProvider);
      },
    );
  }
}

class _TrackTile extends StatelessWidget {
  final MusicTrack track;
  final MediaProvider mediaProvider;
  final MusicProvider musicProvider;

  const _TrackTile({
    required this.track,
    required this.mediaProvider,
    required this.musicProvider,
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
                        image: NetworkImage(track.albumArtworkUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
                color: Colors.white10,
              ),
              child: (track.albumArtworkUrl != null && track.albumArtworkUrl!.isNotEmpty)
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: track.albumArtworkUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.white.withOpacity(0.05)),
                        errorWidget: (context, url, error) => 
                            const Icon(Icons.music_note_rounded, color: Colors.white24),
                        fadeInDuration: const Duration(milliseconds: 300),
                      ),
                    )
                  : const Icon(Icons.music_note_rounded, color: Colors.white24),
            ),
          ),
          title: Text(
            track.title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              if (isAvailable)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1DB954),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'LY',
                    style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              Expanded(
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MusicDetailsPage(
                          id: track.artistId,
                          type: MusicDetailsType.artist,
                          title: track.artistName,
                          artworkUrl: null, // Artist image will be loaded in details
                        ),
                      ),
                    );
                  },
                  child: Text(
                    '${track.artistName} • ${track.albumName ?? 'Single'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          trailing: isAvailable
              ? const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF1DB954))
              : const Icon(Icons.info_outline_rounded, color: Colors.white24),
          onTap: () {
            if (isAvailable) {
              final file = MediaFile(
                id: track.id,
                filePath: match.localFilePath!,
                fileName: track.title,
                mediaKind: MediaKind.audio,
                artist: track.artistName,
                album: track.albumName,
                metadataTitle: track.title,
                thumbnailUrl: track.albumArtworkUrl,
              );
              mediaProvider.playMedia(file);
              musicProvider.notifyListeners();
            } else {
              _showDownloadDialog(context);
            }
          },
        );
      },
    );
  }

  void _showDownloadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Download track?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Download "${track.title}" by ${track.artistName}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _downloadTrack(context);
            },
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('DOWNLOAD'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A84FF),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadTrack(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading "${track.title}"...')),
    );
    final query = '${track.title} ${track.artistName}';
    final ytResults = await mediaProvider.searchYoutubeDiscovery('$query music');
    MediaFile? file;
    if (ytResults.isNotEmpty) {
      file = await mediaProvider.downloadAndAddMusic(ytResults.first, artworkUrl: track.albumArtworkUrl);
    } else {
      file = await mediaProvider.downloadAndAddMusic(
        {'title': track.title, 'url': 'ytsearch:$query'},
        artworkUrl: track.albumArtworkUrl,
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(file != null
              ? 'Downloaded "${file.displayTitle}" to Music Library'
              : 'Download failed — try again'),
          backgroundColor: file != null ? const Color(0xFF0A84FF) : Colors.red,
        ),
      );
    }
  }
}
