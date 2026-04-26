import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/remote_media_provider.dart';

enum RemoteLibrarySection { movies, tv, music }

class RemoteLibraryScreen extends StatefulWidget {
  final RemoteLibrarySection? initialSection;
  const RemoteLibraryScreen({super.key, this.initialSection});

  @override
  State<RemoteLibraryScreen> createState() => _RemoteLibraryScreenState();
}

class _RemoteLibraryScreenState extends State<RemoteLibraryScreen> {
  late RemoteLibrarySection _section;
  
  @override
  void initState() {
    super.initState();
    _section = widget.initialSection ?? RemoteLibrarySection.movies;
    
    // Connect to server on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<RemoteMediaProvider>(context, listen: false).connectAndFetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RemoteMediaProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final allMedia = provider.media;
        final movies = allMedia.where((m) => m.isVideo && !m.fileName.toLowerCase().contains('s0')).toList();
        final tv = allMedia.where((m) => m.isVideo && m.fileName.toLowerCase().contains('s0')).toList();
        final music = allMedia.where((m) => m.isAudio).toList();

        return Column(
          children: [
            _buildTabs(),
            Expanded(
              child: _buildGrid(_section == RemoteLibrarySection.movies 
                  ? movies 
                  : (_section == RemoteLibrarySection.tv ? tv : music)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _TabButton(
            label: 'Movies',
            selected: _section == RemoteLibrarySection.movies,
            onTap: () => setState(() => _section = RemoteLibrarySection.movies),
          ),
          _TabButton(
            label: 'TV',
            selected: _section == RemoteLibrarySection.tv,
            onTap: () => setState(() => _section = RemoteLibrarySection.tv),
          ),
          _TabButton(
            label: 'Music',
            selected: _section == RemoteLibrarySection.music,
            onTap: () => setState(() => _section = RemoteLibrarySection.music),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<RemoteMediaFile> items) {
    if (items.isEmpty) {
      return const Center(child: Text('No media found', style: TextStyle(color: Colors.white38)));
    }

    return GridView.builder(
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
        return _MediaCard(item: item);
      },
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE9B3FF).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? const Color(0xFFE9B3FF) : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white38,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final RemoteMediaFile item;
  const _MediaCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Provider.of<RemoteMediaProvider>(context, listen: false).playMedia(item);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.coverArtUrl != null
                  ? Image.network(item.coverArtUrl!, fit: BoxFit.cover)
                  : Container(
                      color: Colors.white10,
                      child: Center(
                        child: Icon(
                          item.isVideo ? Icons.movie_rounded : Icons.audiotrack_rounded,
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
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
