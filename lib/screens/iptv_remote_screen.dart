import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/remote_media_provider.dart';
import 'iptv_player_screen.dart';
import '../services/iptv_service.dart';

class IptvRemoteScreen extends StatefulWidget {
  final int initialTabIndex;
  const IptvRemoteScreen({super.key, this.initialTabIndex = 0});

  @override
  State<IptvRemoteScreen> createState() => _IptvRemoteScreenState();
}

class _IptvRemoteScreenState extends State<IptvRemoteScreen> {
  late int _selectedTabIndex;
  
  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTabIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RemoteMediaProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            _buildTabs(),
            Expanded(
              child: _buildContent(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabs() {
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        children: [
          _TabButton(
            label: 'Guide',
            selected: _selectedTabIndex == 0,
            onTap: () => setState(() => _selectedTabIndex = 0),
          ),
          const SizedBox(width: 8),
          _TabButton(
            label: 'Live',
            selected: _selectedTabIndex == 1,
            onTap: () => setState(() => _selectedTabIndex = 1),
          ),
          const SizedBox(width: 8),
          _TabButton(
            label: 'Movies',
            selected: _selectedTabIndex == 2,
            onTap: () => setState(() => _selectedTabIndex = 2),
          ),
          const SizedBox(width: 8),
          _TabButton(
            label: 'Series',
            selected: _selectedTabIndex == 3,
            onTap: () => setState(() => _selectedTabIndex = 3),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(RemoteMediaProvider provider) {
    List<dynamic> items;
    if (_selectedTabIndex == 0) {
      return _buildGuide(provider);
    } else if (_selectedTabIndex == 1) {
      items = provider.remoteLiveChannels;
    } else if (_selectedTabIndex == 2) {
      items = provider.remoteIptvMovies;
    } else {
      items = provider.remoteIptvSeries;
    }

    if (items.isEmpty) {
      return const Center(
        child: Text('No IPTV media found',
            style: TextStyle(color: Colors.white38)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        // Create an IptvMedia object from the JSON data
        final media = IptvMedia(
          name: item['name'] ?? 'Unknown',
          logo: item['logo'] ?? '',
          url: item['url'] ?? '',
          group: item['group'] ?? '',
          type: _selectedTabIndex == 1
              ? IptvType.live
              : (_selectedTabIndex == 2 ? IptvType.movie : IptvType.series),
          tvgId: item['tvgId'],
          tvgName: item['tvgName'],
        );

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: media)),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: media.logo.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: media.logo,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _PlaceholderIcon(isLive: media.isLive))
                      : _PlaceholderIcon(isLive: media.isLive),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                media.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGuide(RemoteMediaProvider provider) {
    final channels = provider.remoteLiveChannels;
    if (channels.isEmpty) {
      return const Center(
        child: Text('No guide data found',
            style: TextStyle(color: Colors.white38)),
      );
    }

    final now = DateTime.now();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: channels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = channels[index];
        final channelId = item['tvgId'] as String?;
        final media = IptvMedia(
          name: item['name'] ?? 'Unknown',
          logo: item['logo'] ?? '',
          url: item['url'] ?? '',
          group: item['group'] ?? '',
          type: IptvType.live,
          tvgId: channelId,
          tvgName: item['tvgName'],
        );
        final current = provider.remoteEpgEntries
            .where((entry) {
              return entry.channelId == channelId &&
                  entry.start.isBefore(now) &&
                  entry.end.isAfter(now);
            })
            .cast<EpgEntry?>()
            .firstWhere((entry) => entry != null, orElse: () => null);

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          tileColor: Colors.white.withValues(alpha: 0.04),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: media.logo.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: media.logo, fit: BoxFit.contain)
                  : const Icon(Icons.live_tv_rounded, color: Colors.white24),
            ),
          ),
          title: Text(media.name,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          subtitle: Text(
            current == null
                ? 'No guide data'
                : '${current.title}  •  ${DateFormat('h:mm a').format(current.start)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: media)),
          ),
        );
      },
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  final bool isLive;
  const _PlaceholderIcon({required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white10,
      child: Center(
        child: Icon(
          isLive ? Icons.live_tv_rounded : Icons.movie_filter_rounded,
          color: Colors.white24,
        ),
      ),
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
