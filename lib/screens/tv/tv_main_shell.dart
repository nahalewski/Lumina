import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../widgets/tv/tv_side_nav.dart';
import '../../widgets/falling_particles.dart';
import '../../widgets/iptv_pip_overlay.dart';
import 'tv_guide_screen.dart';
import 'tv_now_playing_screen.dart';
import '../../themes/sakura_theme.dart';
import '../iptv_live_screen.dart';
import '../iptv_movies_screen.dart';
import '../iptv_series_screen.dart';
import '../document_library_screen.dart';
import '../settings_screen.dart';
import '../../providers/media_provider.dart';
import '../../models/media_model.dart';
import '../../services/ebook_manga_metadata_service.dart';

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

  // Keep selectedNavIndex clamped to valid range now that we have 9 screens
  int get _clampedIndex => _selectedNavIndex.clamp(0, 8);

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
              Positioned.fill(
                child: FallingFlowersBackground(
                  theme: Provider.of<MediaProvider>(context).settings.particleTheme,
                  child: const SizedBox.expand(),
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
                            DocumentLibraryScreen(type: DocumentLibraryType.ebooks),
                            DocumentLibraryScreen(type: DocumentLibraryType.manga),
                            DocumentLibraryScreen(type: DocumentLibraryType.comics),
                            TvNowPlayingScreen(onBack: () => _navigateToSection(0)),
                            const SettingsScreen(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const IptvPipOverlay(),

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
              _buildPairingOverlay(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPairingOverlay(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    if (provider.pairingRequests.isEmpty) return const SizedBox.shrink();

    final request = provider.pairingRequests.first;

    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFFAAC7FF).withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phonelink_lock_rounded,
                  color: Color(0xFFAAC7FF), size: 64),
              const SizedBox(height: 24),
              const Text(
                'Pairing Request',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'A device named "${request.deviceName}" is attempting to connect.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => provider.denyPairing(request),
                    child: const Text('DENY',
                        style: TextStyle(color: Colors.redAccent, fontSize: 18)),
                  ),
                  ElevatedButton(
                    onPressed: () => provider.approvePairing(request),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFAAC7FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                    ),
                    child: const Text('APPROVE',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
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
