import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/media_provider.dart';
import 'providers/subtitle_provider.dart';
import 'providers/remote_media_provider.dart';
import 'providers/iptv_provider.dart';
import 'services/video_player_service.dart';
import 'widgets/side_nav_bar.dart';
import 'widgets/player_bar.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/browser_screen.dart';
import 'screens/vocabulary_screen.dart';
import 'screens/basic_player_screen.dart';
import 'screens/iptv_live_screen.dart';
import 'screens/iptv_movies_screen.dart';
import 'screens/iptv_series_screen.dart';
import 'screens/remote_library_screen.dart';
import 'screens/tv/tv_main_shell.dart';
import 'widgets/falling_particles.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize the native video player service
  VideoPlayerService().initialize();
  
  runApp(const LuminaMediaApp());
}


class LuminaMediaApp extends StatelessWidget {
  const LuminaMediaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MediaProvider()..loadLibrary()..fetchOllamaModels()),
        ChangeNotifierProvider(create: (_) => SubtitleProvider()),
        ChangeNotifierProvider(create: (_) => RemoteMediaProvider()),
        ChangeNotifierProvider(create: (_) => IptvProvider()..initialize()),
      ],
      child: Builder(
        builder: (context) {
          // Wire IPTV provider into media server so IPTV data is served via API
          final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
          final iptvProvider = Provider.of<IptvProvider>(context, listen: false);
          mediaProvider.setIptvProviderForServer(iptvProvider);
          
          return MaterialApp(
            title: 'Lumina Media',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(),
            home: _isBasicMode() 
                ? const BasicPlayerScreen() 
                : (_isTv() ? const TvMainShell() : const MainShell()),
          );
        },
      ),
    );
  }

  bool _isBasicMode() {
    return const String.fromEnvironment('BASIC_MODE') == 'true';
  }

  bool _isTv() {
    // For Tizen, Platform.isLinux is true. We can also check environment variables.
    // In a real Tizen app, we'd use a specific plugin or check for Tizen OS.
    return const String.fromEnvironment('UI_MODE') == 'tv' || 
           Platform.isLinux && !Platform.isAndroid; // Tizen often reports as Linux
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF131315),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFE9B3FF), // Vibrant Anime Pink/Purple
        secondary: Color(0xFFAAC7FF), // Soft Sky Blue
        tertiary: Color(0xFF42E355),
        surface: Color(0xFF131315),
        error: Color(0xFFFFB4AB),
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(fontSize: 16),
        bodyMedium: TextStyle(fontSize: 14),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.02,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.1),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: const Color(0xFFAAC7FF),
        inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
        thumbColor: Colors.white,
      ),
    );
  }
}

/// Main application shell with sidebar, content area, and player bar
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedNavIndex = 0;
  bool _showNowPlaying = false;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    // Phase 3: Automatically check for installed models and play menu music on launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
      mediaProvider.checkInstalledModels();
    });

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  void _navigateToNowPlaying() {
    setState(() {
      _selectedNavIndex = 4;
    });
  }

  void _navigateBack() {
    setState(() {
      _selectedNavIndex = 0; // Go back to Library
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isMobile) {
      return Scaffold(
        body: FallingFlowersBackground(
          child: SafeArea(
            child: _buildMobileContent(),
          ),
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
            canvasColor: const Color(0xFF131315).withValues(alpha: 0.95),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedNavIndex > 5 ? 0 : _selectedNavIndex, // Fallback for indices not in bottom bar
            onTap: (index) {
              setState(() {
                _selectedNavIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFFE9B3FF),
            unselectedItemColor: Colors.white38,
            backgroundColor: const Color(0xFF131315),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.library_music_rounded), label: 'Music'),
              BottomNavigationBarItem(icon: Icon(Icons.live_tv_rounded), label: 'IPTV'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: FallingFlowersBackground(
        child: Row(
          children: [
            // Sidebar
            SideNavBar(
              selectedIndex: _selectedNavIndex,
              onItemSelected: (index) {
                setState(() {
                  _selectedNavIndex = index;
                });
              },
            ),
            // Content area
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _selectedNavIndex == 6
                        ? const IptvLiveScreen()
                        : _selectedNavIndex == 7
                            ? const IptvMoviesScreen()
                            : _selectedNavIndex == 8
                                ? const IptvSeriesScreen()
                                  : IndexedStack(
                                    index: _selectedNavIndex == 9 ? 6 : _selectedNavIndex,
                                    children: [
                                      LibraryScreen(onPlayMedia: _navigateToNowPlaying), // 0 - Home
                                      const WebBrowserScreen(),                         // 1 - Web Browser
                                      LibraryScreen(onPlayMedia: _navigateToNowPlaying), // 2 - Library
                                      const SettingsScreen(),                          // 3 - Settings
                                      NowPlayingScreen(onBack: _navigateBack),          // 4 - Now Playing
                                      const VocabularyScreen(),                        // 5 - Vocabulary
                                      LibraryScreen(                                   // 6 (sidebar 9) - Music Library
                                        onPlayMedia: _navigateToNowPlaying,
                                        initialSection: LibrarySection.music,
                                      ),
                                    ],
                                  ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileContent() {
    // Map bottom bar index to main nav indices
    switch (_selectedNavIndex) {
      case 0: // Home
        return const RemoteLibraryScreen();
      case 1: // Music
        return const RemoteLibraryScreen(
          initialSection: RemoteLibrarySection.music,
        );
      case 2: // IPTV (Live)
        return const IptvLiveScreen();
      case 3: // Settings
        return const SettingsScreen();
      default:
        return const RemoteLibraryScreen();
    }
  }

  Widget _buildPage() {
    switch (_selectedNavIndex) {
      case 0: // Home
        return LibraryScreen(onPlayMedia: _navigateToNowPlaying);
      case 1: // Web Browser
        return const WebBrowserScreen();
      case 2: // Library (same as home for now)
        return LibraryScreen(onPlayMedia: _navigateToNowPlaying);
      case 3: // Settings
        return const SettingsScreen();
      case 4: // Now Playing
        return NowPlayingScreen(onBack: _navigateBack);
      case 5: // Vocabulary
        return const VocabularyScreen();
      default:
        return LibraryScreen(onPlayMedia: _navigateToNowPlaying);
    }
  }

  Widget _buildLikedScreen() {
    return Consumer<MediaProvider>(
      builder: (context, provider, _) {
        final favorites = provider.favoriteFiles;
        if (favorites.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.favorite_rounded,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 16),
                Text(
                  'No favorites yet',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the heart icon on any media to add it here',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }
        return _buildMediaList(favorites, 'Favorites');
      },
    );
  }

  Widget _buildMediaList(List<dynamic> mediaList, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            itemCount: mediaList.length,
            itemBuilder: (context, index) {
              final media = mediaList[index] as dynamic;
              return ListTile(
                leading: Icon(
                  media.isVideo ? Icons.movie_rounded : Icons.audiotrack_rounded,
                  color: Colors.white54,
                ),
                title: Text(
                  media.title,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  media.extension.toUpperCase(),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                ),
                trailing: IconButton(
                  icon: Icon(
                    media.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: media.isFavorite ? Colors.red : Colors.white38,
                  ),
                  onPressed: () => Provider.of<MediaProvider>(context, listen: false).toggleFavorite(media.id),
                ),
                onTap: () {
                  Provider.of<MediaProvider>(context, listen: false).setCurrentMedia(media);
                  _navigateToNowPlaying();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

