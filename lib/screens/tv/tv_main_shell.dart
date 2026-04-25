import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/tv/tv_side_nav.dart';
import '../../widgets/falling_particles.dart';
import 'tv_guide_screen.dart';
import 'tv_now_playing_screen.dart';
import '../../themes/sakura_theme.dart';
import '../iptv_live_screen.dart';
import '../iptv_movies_screen.dart';
import '../iptv_series_screen.dart';

class TvMainShell extends StatefulWidget {
  const TvMainShell({super.key});

  @override
  State<TvMainShell> createState() => _TvMainShellState();
}

class _TvMainShellState extends State<TvMainShell> {
  int _selectedNavIndex = 0;

  void _navigateToSection(int index) {
    setState(() => _selectedNavIndex = index);
  }

  // Keep selectedNavIndex clamped to valid range now that we have 5 screens
  int get _clampedIndex => _selectedNavIndex.clamp(0, 4);

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
      },
      child: Theme(
        data: SakuraTheme.themeData,
        child: Scaffold(
          backgroundColor: SakuraTheme.background,
          body: Stack(
            children: [
              // 1. Falling Flowers Background
              const Positioned.fill(
                child: FallingFlowersBackground(
                  child: SizedBox.expand(),
                ),
              ),
              
              // 2. Main Content + Side Nav (Responsive)
              SafeArea(
                child: Row(
                  children: [
                    TvSideNav(
                      selectedIndex: _clampedIndex,
                      onItemSelected: _navigateToSection,
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0.8, -0.8),
                            radius: 1.5,
                            colors: [
                              SakuraTheme.sakuraPink.withValues(alpha: 0.05),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: IndexedStack(
                          index: _clampedIndex,
                          children: [
                            const IptvLiveScreen(),
                            const TvGuideScreen(),
                            const IptvMoviesScreen(),
                            const IptvSeriesScreen(),
                            TvNowPlayingScreen(onBack: () => _navigateToSection(0)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Subtle scanline vignette (drawn locally — no network fetch)
              IgnorePointer(
                child: CustomPaint(
                  painter: _ScanlinePainter(),
                  child: const SizedBox.expand(),
                ),
              ),
              
              // 4. Subtle Vignette
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.4),
                      ],
                      stops: const [0.6, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Lightweight scanline effect drawn entirely on-device — no network dependency.
class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) => false;
}
