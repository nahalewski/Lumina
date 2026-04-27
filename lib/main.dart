import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'providers/media_provider.dart';
import 'providers/subtitle_provider.dart';
import 'providers/remote_media_provider.dart';
import 'providers/iptv_provider.dart';
import 'providers/iptv_pip_provider.dart';
import 'providers/music_provider.dart';
import 'services/video_player_service.dart';
import 'widgets/side_nav_bar.dart';
import 'widgets/player_bar.dart';
import 'widgets/queue_drawer.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/music/music_search_page.dart';
import 'screens/settings_screen.dart';
import 'screens/browser_screen.dart';
import 'screens/basic_player_screen.dart';
import 'screens/iptv_live_screen.dart';
import 'screens/iptv_movies_screen.dart';
import 'screens/iptv_series_screen.dart';
import 'screens/iptv_remote_screen.dart';
import 'screens/remote_library_screen.dart';
import 'screens/remote_now_playing_screen.dart';
import 'screens/document_library_screen.dart';
import 'services/ebook_manga_metadata_service.dart';
import 'screens/user_management_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/tv/tv_main_shell.dart';
import 'widgets/iptv_pip_overlay.dart';
import 'widgets/falling_particles.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('Error loading .env file: $e');
  }

  try {
    if (Platform.isWindows) {
      fvp.registerWith();
    }
  } catch (_) {
    // Ignore platform registration failures.
  }

  // Initialize the native video player service
  VideoPlayerService().initialize();

  // Add debug logging to file
  try {
    final logFile = File('lumina_debug.log');
    await logFile.writeAsString(
        'Lumina Media app starting at ${DateTime.now()}\n',
        mode: FileMode.append);
  } catch (e) {
    // Ignore file write errors
  }

  runApp(const LuminaMediaApp());
}

class LuminaMediaApp extends StatelessWidget {
  const LuminaMediaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Log that build was called
    try {
      final logFile = File('lumina_debug.log');
      logFile.writeAsString(
          'LuminaMediaApp build called at ${DateTime.now()}\n',
          mode: FileMode.append);
    } catch (e) {
      // Ignore file write errors
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => MediaProvider()
              ..loadLibrary()
              ..fetchOllamaModels()),
        ChangeNotifierProvider(create: (_) => SubtitleProvider()),
        ChangeNotifierProvider(create: (_) => RemoteMediaProvider()),
        ChangeNotifierProvider(create: (_) => IptvProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => IptvPipProvider()),
        ChangeNotifierProvider(create: (_) => MusicProvider()),
      ],
      child: Builder(
        builder: (context) {
          // Wire IPTV provider into media server so IPTV data is served via API
          final mediaProvider =
              Provider.of<MediaProvider>(context, listen: false);
          final iptvProvider =
              Provider.of<IptvProvider>(context, listen: false);
          mediaProvider.setIptvProviderForServer(iptvProvider);

          return MaterialApp(
            title: 'Lumina Media',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(),
            home: _isBasicMode()
                ? const BasicPlayerScreen()
                : (_isTv()
                    ? (Platform.isAndroid
                        ? const AndroidTvRemoteShell()
                        : const TvMainShell())
                    : const MainShell()),
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
        const String.fromEnvironment('TIZEN') == 'true';
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
  int _selectedNavIndex = Platform.isAndroid || Platform.isIOS ? 0 : 2;
  bool _showQueue = false;
  bool _isNsfwUnlocked = false;

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
      _selectedNavIndex = _isMobile ? 5 : 4;
    });
  }

  void _navigateBack() {
    setState(() {
      _selectedNavIndex = _isMobile ? 0 : 2; // Go back to Library
    });
  }

  void _showNsfwPinDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Enter PIN', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the security PIN to unlock NSFW content.',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, letterSpacing: 8),
              textAlign: TextAlign.center,
              maxLength: 6,
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onSubmitted: (value) => _verifyPin(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => _verifyPin(controller.text),
            child: const Text('Unlock',
                style: TextStyle(color: Color(0xFFE9B3FF))),
          ),
        ],
      ),
    );
  }

  void _verifyPin(String pin) {
    if (pin == '897888') {
      setState(() => _isNsfwUnlocked = true);
      Navigator.pop(context);
      _selectMobileDrawerItem(context, 6); // Navigate to NSFW
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Incorrect PIN'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isMobile) {
      return Scaffold(
        backgroundColor: const Color(0xFF131315),
        appBar: AppBar(
          backgroundColor: const Color(0xFF131315),
          foregroundColor: Colors.white,
          title: Text(_mobileTitle),
          centerTitle: false,
        ),
        drawer: _buildMobileDrawer(context),
        body: FallingFlowersBackground(
          theme: Provider.of<MediaProvider>(context).settings.particleTheme,
          child: Stack(
            children: [
              _buildMobileContent(),
              _buildPairingOverlay(context),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          FallingFlowersBackground(
            theme: Provider.of<MediaProvider>(context).settings.particleTheme,
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
                        child: IndexedStack(
                          index: _selectedNavIndex,
                          children: [
                            LibraryScreen(
                                onPlayMedia:
                                    _navigateToNowPlaying), // 0 - Home (Library)
                            const WebBrowserScreen(), // 1 - Web Browser
                            LibraryScreen(
                                onPlayMedia:
                                    _navigateToNowPlaying), // 2 - Library
                            const SettingsScreen(), // 3 - Settings
                            NowPlayingScreen(
                                onBack: _navigateBack), // 4 - Now Playing
                            const SizedBox.shrink(), // 5 - retired nav slot
                            const IptvLiveScreen(), // 6 - Live TV
                            const IptvMoviesScreen(), // 7 - Movies (IPTV)
                            const IptvSeriesScreen(), // 8 - TV Shows (IPTV)
                            const MusicSearchPage(), // 9 - Music Library
                            const UserManagementScreen(), // 10 - User Management
                            LibraryScreen(
                              // 11 - NSFW
                              onPlayMedia: _navigateToNowPlaying,
                              initialSection: LibrarySection.nsfw,
                            ),
                            DocumentLibraryScreen(
                              type: DocumentLibraryType.ebooks,
                            ), // 12 - E-books
                            DocumentLibraryScreen(
                              type: DocumentLibraryType.manga,
                            ), // 13 - Manga
                            DocumentLibraryScreen(
                              type: DocumentLibraryType.comics,
                            ), // 14 - Comics
                            const DownloadsScreen(), // 15 - Downloads
                          ],
                        ),
                      ),
                      if (_selectedNavIndex != 4) const PlayerBar(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_showQueue)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showQueue = false),
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
              ),
            ),
          if (_showQueue)
            Align(
              alignment: Alignment.centerRight,
              child: QueueDrawer(onPlayMedia: _navigateToNowPlaying),
            ),
          // Picture-in-Picture overlay (always on top)
          const IptvPipOverlay(),
          _buildPairingOverlay(context),
          Positioned(
            right: 24,
            bottom: 124,
            child: FloatingActionButton.small(
              heroTag: 'queue-drawer',
              backgroundColor: const Color(0xFF1E1E22),
              foregroundColor: const Color(0xFFAAC7FF),
              onPressed: () => setState(() => _showQueue = !_showQueue),
              child: const Icon(Icons.queue_music_rounded),
            ),
          ),
        ],
      ),
    );
  }

  String get _mobileTitle {
    switch (_selectedNavIndex) {
      case 1:
        return 'Music';
      case 2:
        return 'E-books';
      case 3:
        return 'Manga';
      case 4:
        return 'Comics';
      case 5:
        return 'IPTV';
      case 6:
        return 'Now Playing';
      case 7:
        return 'Not Safe for Work';
      case 8:
        return 'Settings';
      default:
        return 'Library';
    }
  }

  Widget _buildMobileDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1C),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Text(
                'Lumina',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Manrope',
                ),
              ),
            ),
            _MobileDrawerItem(
              icon: Icons.folder_rounded,
              label: 'Library',
              selected: _selectedNavIndex == 0,
              onTap: () => _selectMobileDrawerItem(context, 0),
            ),
            _MobileDrawerItem(
              icon: Icons.music_note_rounded,
              label: 'Music',
              selected: _selectedNavIndex == 1,
              onTap: () => _selectMobileDrawerItem(context, 1),
            ),
            _MobileDrawerItem(
              icon: Icons.menu_book_rounded,
              label: 'E-books',
              selected: _selectedNavIndex == 2,
              onTap: () => _selectMobileDrawerItem(context, 2),
            ),
            _MobileDrawerItem(
              icon: Icons.auto_stories_rounded,
              label: 'Manga',
              selected: _selectedNavIndex == 3,
              onTap: () => _selectMobileDrawerItem(context, 3),
            ),
            _MobileDrawerItem(
              icon: Icons.collections_bookmark_rounded,
              label: 'Comics',
              selected: _selectedNavIndex == 4,
              onTap: () => _selectMobileDrawerItem(context, 4),
            ),
            _MobileDrawerItem(
              icon: Icons.live_tv_rounded,
              label: 'IPTV',
              selected: _selectedNavIndex == 5,
              onTap: () => _selectMobileDrawerItem(context, 5),
            ),
            _MobileDrawerItem(
              icon: Icons.play_circle_outline_rounded,
              label: 'Now Playing',
              selected: _selectedNavIndex == 6,
              onTap: () => _selectMobileDrawerItem(context, 6),
            ),
            if (_isNsfwUnlocked)
              _MobileDrawerItem(
                icon: Icons.lock_open_rounded,
                label: 'Not Safe for Work',
                selected: _selectedNavIndex == 7,
                onTap: () => _selectMobileDrawerItem(context, 7),
              )
            else
              _MobileDrawerItem(
                icon: Icons.lock_rounded,
                label: 'Unlock NSFW',
                selected: false,
                onTap: () {
                  Navigator.pop(context);
                  _showNsfwPinDialog();
                },
              ),
            _MobileDrawerItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              selected: _selectedNavIndex == 8,
              onTap: () => _selectMobileDrawerItem(context, 8),
            ),
          ],
        ),
      ),
    );
  }

  void _selectMobileDrawerItem(BuildContext context, int index) {
    Navigator.of(context).pop();
    setState(() => _selectedNavIndex = index);
  }

  Widget _buildPairingOverlay(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    if (provider.pairingRequests.isEmpty) return const SizedBox.shrink();

    final request = provider.pairingRequests.first;

    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(24),
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
                  color: Color(0xFFAAC7FF), size: 48),
              const SizedBox(height: 16),
              const Text(
                'Pairing Request',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'A device named "${request.deviceName}" is attempting to connect.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => provider.denyPairing(request),
                    child: const Text('DENY',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                  ElevatedButton(
                    onPressed: () => provider.approvePairing(request),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFAAC7FF),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('APPROVE'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileContent() {
    return IndexedStack(
      index: _selectedNavIndex,
      children: [
        RemoteLibraryScreen(onPlayMedia: _navigateToNowPlaying), // 0: Library
        const MusicSearchPage(), // 1: Music
        DocumentLibraryScreen(
            type: DocumentLibraryType.ebooks), // 2: E-books
        DocumentLibraryScreen(
            type: DocumentLibraryType.manga), // 3: Manga
        DocumentLibraryScreen(
            type: DocumentLibraryType.comics), // 4: Comics
        const IptvRemoteScreen(), // 5: IPTV
        RemoteNowPlayingScreen(onBack: _navigateBack), // 6: Now Playing
        RemoteLibraryScreen(
          // 7: NSFW
          initialSection: RemoteLibrarySection.nsfw,
          onPlayMedia: _navigateToNowPlaying,
        ),
        const SettingsScreen(), // 8: Settings
      ],
    );
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
                  media.isVideo
                      ? Icons.movie_rounded
                      : Icons.audiotrack_rounded,
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
                    media.isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: media.isFavorite ? Colors.red : Colors.white38,
                  ),
                  onPressed: () =>
                      Provider.of<MediaProvider>(context, listen: false)
                          .toggleFavorite(media.id),
                ),
                onTap: () {
                  Provider.of<MediaProvider>(context, listen: false)
                      .setCurrentMedia(media);
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

class AndroidTvRemoteShell extends StatefulWidget {
  const AndroidTvRemoteShell({super.key});

  @override
  State<AndroidTvRemoteShell> createState() => _AndroidTvRemoteShellState();
}

class _AndroidTvRemoteShellState extends State<AndroidTvRemoteShell> {
  int _selectedIndex = 0;
  bool _isNsfwUnlocked = false;

  void _select(int index) {
    if (index == 6 && !_isNsfwUnlocked) {
      _showNsfwPinDialog();
    } else {
      setState(() => _selectedIndex = index);
    }
  }

  void _showNsfwPinDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Enter PIN', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the security PIN to unlock NSFW content.',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, letterSpacing: 8),
              textAlign: TextAlign.center,
              maxLength: 6,
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onSubmitted: (value) => _verifyPin(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => _verifyPin(controller.text),
            child: const Text('Unlock',
                style: TextStyle(color: Color(0xFFE9B3FF))),
          ),
        ],
      ),
    );
  }

  void _verifyPin(String pin) {
    if (pin == '897888') {
      setState(() {
        _isNsfwUnlocked = true;
        _selectedIndex = 6;
      });
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Incorrect PIN'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 960;
    final navWidth = (size.width * 0.18).clamp(112.0, 220.0);

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => null,
          ),
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF131315),
          body: FallingFlowersBackground(
            theme: Provider.of<MediaProvider>(context).settings.particleTheme,
            child: SafeArea(
              child: Row(
                children: [
                  SizedBox(
                    width: isCompact ? 96 : navWidth,
                    child: _AndroidTvNav(
                      selectedIndex: _selectedIndex,
                      expanded: !isCompact,
                      nsfwUnlocked: _isNsfwUnlocked,
                      onSelected: _select,
                    ),
                  ),
                  Expanded(
                    child: FocusTraversalGroup(
                      policy: ReadingOrderTraversalPolicy(),
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          RemoteLibraryScreen(
                            onPlayMedia: () => _select(5),
                          ),
                          DocumentLibraryScreen(
                            type: DocumentLibraryType.ebooks,
                          ),
                          DocumentLibraryScreen(
                            type: DocumentLibraryType.manga,
                          ),
                          DocumentLibraryScreen(
                            type: DocumentLibraryType.comics,
                          ),
                          const IptvRemoteScreen(),
                          RemoteNowPlayingScreen(onBack: () => _select(0)),
                          RemoteLibraryScreen(
                            initialSection: RemoteLibrarySection.nsfw,
                            onPlayMedia: () => _select(5),
                          ),
                          const SettingsScreen(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AndroidTvNav extends StatelessWidget {
  final int selectedIndex;
  final bool expanded;
  final bool nsfwUnlocked;
  final ValueChanged<int> onSelected;

  const _AndroidTvNav({
    required this.selectedIndex,
    required this.expanded,
    required this.nsfwUnlocked,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF131315).withValues(alpha: 0.92),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 10),
        children: [
          _AndroidTvNavItem(
            icon: Icons.folder_rounded,
            label: 'Library',
            selected: selectedIndex == 0,
            expanded: expanded,
            onTap: () => onSelected(0),
          ),
          _AndroidTvNavItem(
            icon: Icons.menu_book_rounded,
            label: 'E-books',
            selected: selectedIndex == 1,
            expanded: expanded,
            onTap: () => onSelected(1),
          ),
          _AndroidTvNavItem(
            icon: Icons.auto_stories_rounded,
            label: 'Manga',
            selected: selectedIndex == 2,
            expanded: expanded,
            onTap: () => onSelected(2),
          ),
          _AndroidTvNavItem(
            icon: Icons.collections_bookmark_rounded,
            label: 'Comics',
            selected: selectedIndex == 3,
            expanded: expanded,
            onTap: () => onSelected(3),
          ),
          _AndroidTvNavItem(
            icon: Icons.live_tv_rounded,
            label: 'IPTV',
            selected: selectedIndex == 4,
            expanded: expanded,
            onTap: () => onSelected(4),
          ),
          _AndroidTvNavItem(
            icon: Icons.play_circle_outline_rounded,
            label: 'Playing',
            selected: selectedIndex == 5,
            expanded: expanded,
            onTap: () => onSelected(5),
          ),
          _AndroidTvNavItem(
            icon: nsfwUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
            label: nsfwUnlocked ? 'NSFW' : 'Unlock NSFW',
            selected: selectedIndex == 6,
            expanded: expanded,
            onTap: () => onSelected(6),
          ),
          _AndroidTvNavItem(
            icon: Icons.settings_rounded,
            label: 'Settings',
            selected: selectedIndex == 7,
            expanded: expanded,
            onTap: () => onSelected(7),
          ),
        ],
      ),
    );
  }
}

class _AndroidTvNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _AndroidTvNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  State<_AndroidTvNavItem> createState() => _AndroidTvNavItemState();
}

class _AndroidTvNavItemState extends State<_AndroidTvNavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: InkWell(
          autofocus: widget.selected,
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFFE9B3FF).withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? const Color(0xFFE9B3FF)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisAlignment: widget.expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  color: active ? const Color(0xFFE9B3FF) : Colors.white54,
                  size: 30,
                ),
                if (widget.expanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileDrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MobileDrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? const Color(0xFFE9B3FF) : Colors.white54,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: selected,
      selectedTileColor: const Color(0xFFE9B3FF).withValues(alpha: 0.12),
      onTap: onTap,
    );
  }
}
