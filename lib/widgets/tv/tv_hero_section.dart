import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../themes/sakura_theme.dart';

class TvHeroSection extends StatelessWidget {
  const TvHeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 800;
        
        if (isMobile) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                _buildMainCard(isMobile: true, height: 350),
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  child: _buildComingUpNext(isMobile: true),
                ),
              ],
            ),
          );
        }

        return Container(
          height: 400,
          margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main Featured Card
              Expanded(
                flex: 8,
                child: _buildMainCard(isMobile: false),
              ),
              const SizedBox(width: 32),
              // Side Widgets
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    Expanded(child: _buildComingUpNext(isMobile: false)),
                    const SizedBox(height: 32),
                    Expanded(child: _buildWeatherCard(isMobile: false)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainCard({required bool isMobile, double? height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: const DecorationImage(
          image: CachedNetworkImageProvider('https://images.unsplash.com/photo-1536440136628-849c177e76a1?auto=format&fit=crop&w=1200'),
          fit: BoxFit.cover,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [
                  SakuraTheme.background.withValues(alpha: 0.9),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Content
          Padding(
            padding: EdgeInsets.all(isMobile ? 24 : 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: SakuraTheme.sakuraPink.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SakuraTheme.sakuraPink.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'PREMIERE LIVE',
                    style: TextStyle(
                      color: SakuraTheme.sakuraPink,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Neon Nights: The Eternal Bloom',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 24 : 48,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                if (!isMobile) ...[
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 600,
                    child: Text(
                      'Experience the masterpiece of modern cinematography in ultra high definition. Streaming live now on Sakura Cinema One.',
                      style: TextStyle(
                        color: SakuraTheme.onSurfaceVariant,
                        fontSize: 18,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Focus(
                  child: Builder(
                    builder: (context) {
                      final isFocused = Focus.of(context).hasFocus;
                      return Transform.scale(
                        scale: isFocused ? 1.05 : 1.0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: SakuraTheme.sakuraPink,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isFocused ? [
                              BoxShadow(
                                color: SakuraTheme.sakuraPink.withValues(alpha: 0.4),
                                blurRadius: 30,
                              )
                            ] : [],
                          ),
                          padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 40, vertical: isMobile ? 12 : 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded, color: SakuraTheme.onPrimary, size: isMobile ? 24 : 32),
                              const SizedBox(width: 12),
                              Text(
                                'WATCH NOW',
                                style: TextStyle(
                                  color: SakuraTheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: isMobile ? 14 : 18,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComingUpNext({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 32),
      decoration: BoxDecoration(
        color: SakuraTheme.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'COMING UP NEXT',
            style: TextStyle(
              color: SakuraTheme.sakuraPink,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Midnight Jazz',
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 20 : 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '22:00 - 23:30 • Live Concert',
            style: TextStyle(
              color: Colors.white38,
              fontSize: isMobile ? 12 : 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherCard({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SakuraTheme.sakuraPink.withValues(alpha: 0.1),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: SakuraTheme.sakuraPink.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'WEATHER TODAY',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.cloudy_snowing, color: SakuraTheme.sakuraPink, size: isMobile ? 32 : 48),
              const SizedBox(width: 16),
              Text(
                '14°C',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 28 : 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
