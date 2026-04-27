import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/music_provider.dart';
import '../../providers/media_provider.dart';
import '../../models/music_models.dart';
import '../../models/media_model.dart';
import '../../services/music/lastfm_service.dart';
import '../../services/music/cover_art_archive_service.dart';

enum MusicDetailsType { album, artist }

class MusicDetailsPage extends StatefulWidget {
  final String id;
  final MusicDetailsType type;
  final String title;
  final String? artworkUrl;

  const MusicDetailsPage({
    super.key,
    required this.id,
    required this.type,
    required this.title,
    this.artworkUrl,
  });

  @override
  State<MusicDetailsPage> createState() => _MusicDetailsPageState();
}

class _MusicDetailsPageState extends State<MusicDetailsPage> {
  MusicAlbum? _album;
  MusicArtist? _artist;
  List<MusicTrack> _tracks = [];
  List<MusicAlbum> _artistAlbums = [];
  String? _bio;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final lastFm = LastFmService(musicProvider.settings);

    try {
      if (widget.type == MusicDetailsType.album) {
        _album = await musicProvider.getAlbumDetails(widget.id);
        if (_album != null) {
          _tracks = await musicProvider.getAlbumTracks(widget.id);
        }
      } else {
        _artist = await musicProvider.getArtistDetails(widget.id);
        if (_artist != null) {
          _artistAlbums = await musicProvider.getArtistAlbums(widget.id);
          _bio = await lastFm.getArtistBio(_artist!.name);
        }
      }
    } catch (e) {
      debugPrint('Error loading details: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF131315),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                _buildAppBar(),
                if (widget.type == MusicDetailsType.artist && _bio != null)
                  SliverToBoxAdapter(child: _buildBioSection()),
                if (widget.type == MusicDetailsType.album)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildTrackTile(_tracks[index]),
                      childCount: _tracks.length,
                    ),
                  ),
                if (widget.type == MusicDetailsType.artist)
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildAlbumCard(_artistAlbums[index]),
                        childCount: _artistAlbums.length,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildAppBar() {
    final imageUrl = widget.artworkUrl?.isNotEmpty == true
        ? widget.artworkUrl
        : _artist?.imageUrl;
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: const Color(0xFF131315),
      flexibleSpace: FlexibleSpaceBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: Colors.black),
                errorWidget: (context, url, error) => Container(
                  color: const Color(0xFF1E1E22),
                  child: const Center(child: Icon(Icons.music_note_rounded, color: Colors.white10, size: 64)),
                ),
              ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xFF131315)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBioSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Biography', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _bio!,
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTrackTile(MusicTrack track) {
    final mediaProvider = Provider.of<MediaProvider>(context);
    final musicProvider = Provider.of<MusicProvider>(context);

    return FutureBuilder<MusicMatch?>(
      future: musicProvider.findAudioSource(track, mediaProvider.mediaFiles),
      builder: (context, snapshot) {
        final match = snapshot.data;
        final isAvailable = match != null;

        return ListTile(
          leading: Text('${track.trackNumber ?? ''}', style: const TextStyle(color: Colors.white38)),
          title: Text(track.title, style: const TextStyle(color: Colors.white)),
          trailing: isAvailable
              ? const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF1DB954))
              : IconButton(
                  icon: const Icon(Icons.download_rounded, color: Colors.white38, size: 20),
                  onPressed: () => _downloadTrack(context, track, mediaProvider),
                ),
          onTap: isAvailable
              ? () {
                  final file = MediaFile(
                    id: track.id,
                    filePath: match.localFilePath!,
                    fileName: track.title,
                    mediaKind: MediaKind.audio,
                    artist: track.artistName,
                    album: track.albumName,
                    metadataTitle: track.title,
                  );
                  mediaProvider.playMedia(file);
                }
              : () => _downloadTrack(context, track, mediaProvider),
        );
      },
    );
  }

  Future<void> _downloadTrack(BuildContext context, MusicTrack track, MediaProvider mediaProvider) async {
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
          content: Text(file != null ? 'Downloaded "${file.displayTitle}" to Music Library' : 'Download failed'),
          backgroundColor: file != null ? const Color(0xFF0A84FF) : Colors.red,
        ),
      );
      if (file != null) setState(() {});
    }
  }

  Widget _buildAlbumCard(MusicAlbum album) {
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
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white10,
              ),
              child: (album.artworkUrl != null && album.artworkUrl!.isNotEmpty)
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: album.artworkUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.white.withOpacity(0.05)),
                        errorWidget: (context, url, error) => 
                            const Center(child: Icon(Icons.album_rounded, color: Colors.white24)),
                      ),
                    )
                  : const Center(child: Icon(Icons.album_rounded, color: Colors.white24)),
            ),
          ),
          const SizedBox(height: 8),
          Text(album.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${album.releaseDate?.year ?? ''}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
