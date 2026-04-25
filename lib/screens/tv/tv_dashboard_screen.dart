import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/tv/tv_hero_section.dart';
import '../../themes/sakura_theme.dart';
import '../../providers/iptv_provider.dart';
import '../../providers/remote_media_provider.dart';

class TvDashboardScreen extends StatefulWidget {
  const TvDashboardScreen({super.key});

  @override
  State<TvDashboardScreen> createState() => _TvDashboardScreenState();
}

class _TvDashboardScreenState extends State<TvDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      Provider.of<IptvProvider>(context, listen: false).loadMedia();
      Provider.of<RemoteMediaProvider>(context, listen: false).connectAndFetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TvHeroSection(),
          
          // Section 1: Live TV Channels
          _buildMediaSection(
            title: 'Live TV Channels',
            icon: Icons.live_tv_rounded,
            mediaType: 'live',
          ),
          
          // Section 2: Movies (IPTV)
          _buildMediaSection(
            title: 'Movies',
            icon: Icons.movie_rounded,
            mediaType: 'movies',
          ),
          
          // Section 3: TV Shows (IPTV)
          _buildMediaSection(
            title: 'TV Shows',
            icon: Icons.tv_rounded,
            mediaType: 'shows',
          ),
          
          // Section 4: Lumina Vault (App Server)
          _buildVaultSection(),
          
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildMediaSection({required String title, required IconData icon, required String mediaType}) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double sectionHeight = isMobile ? 260 : 360;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title, icon),
        const SizedBox(height: 12),
        SizedBox(
          height: sectionHeight,
          child: Consumer<IptvProvider>(
            builder: (context, provider, _) {
              final media = mediaType == 'live' ? provider.liveChannels : 
                            mediaType == 'movies' ? provider.movies : 
                            provider.tvShows;
                            
              if (provider.isLoading && media.isEmpty) {
                return const Center(child: CircularProgressIndicator(color: SakuraTheme.sakuraPink));
              }
              if (media.isEmpty) {
                return const Center(child: Text('No content found', style: TextStyle(color: Colors.white38)));
              }
              return ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32),
                scrollDirection: Axis.horizontal,
                itemCount: media.length,
                itemBuilder: (context, index) => _buildMediaCard(media[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVaultSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Lumina Vault', Icons.cloud_done_rounded),
        const SizedBox(height: 24),
        SizedBox(
          height: 360,
          child: Consumer<RemoteMediaProvider>(
            builder: (context, provider, _) {
              final mediaList = provider.media;
              if (provider.isLoading && mediaList.isEmpty) {
                return const Center(child: CircularProgressIndicator(color: SakuraTheme.sakuraPink));
              }
              if (mediaList.isEmpty) {
                return const Center(child: Text('Vault is empty or server unreachable', style: TextStyle(color: Colors.white38)));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                scrollDirection: Axis.horizontal,
                itemCount: mediaList.length,
                itemBuilder: (context, index) {
                  final media = mediaList[index];
                  return _buildMediaCard(media, isVault: true);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: isMobile ? 12 : 24),
      child: Row(
        children: [
          Icon(icon, color: SakuraTheme.sakuraPink, size: isMobile ? 24 : 32),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(color: Colors.white, fontSize: isMobile ? 20 : 32, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaCard(dynamic media, {bool isVault = false}) {
    final String title = isVault ? media.title : media.name;
    final String? logo = isVault ? media.coverArtUrl : media.logo;
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double cardWidth = isMobile ? 160 : 240;
    final double cardHeight = isMobile ? 220 : 320;

    return Focus(
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          final transform = isFocused
              ? (Matrix4.identity()..translate(0.0, -10.0))
              : Matrix4.identity();
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: cardWidth,
            margin: EdgeInsets.only(right: isMobile ? 16 : 24),
            transform: transform,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: cardHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
                    border: Border.all(
                      color: isFocused ? SakuraTheme.sakuraPink : Colors.white.withValues(alpha: 0.1),
                      width: 2,
                    ),
                    boxShadow: isFocused ? [
                      BoxShadow(color: SakuraTheme.sakuraPink.withValues(alpha: 0.3), blurRadius: 30)
                    ] : [],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      if (logo != null && logo.isNotEmpty)
                        Image.network(
                          logo, 
                          fit: BoxFit.cover, 
                          height: double.infinity, 
                          width: double.infinity, 
                          errorBuilder: (c, e, s) => _buildPlaceholder(),
                        )
                      else
                        _buildPlaceholder(),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                            ),
                          ),
                          child: Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 12 : 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(color: SakuraTheme.surfaceContainer, child: const Center(child: Icon(Icons.movie_rounded, color: SakuraTheme.sakuraPink, size: 48)));
  }
}
