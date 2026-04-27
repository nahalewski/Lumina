import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../models/media_model.dart';
import 'subtitle_provider.dart';
import '../services/ollama_service.dart';
import '../services/model_downloader_service.dart';
import '../services/metadata_service.dart';
import '../services/artwork_scraper_service.dart';
import '../services/media_server_service.dart';
import '../services/cloudflare_tunnel_service.dart';
import 'iptv_provider.dart';
import '../services/spotify_service.dart';
import '../services/ytdlp_service.dart';
import '../services/media_scraper_service.dart';
import '../services/subtitle_scraper_service.dart';
import '../services/actor_metadata_service.dart';
import '../services/epg_weather_service.dart';
import '../services/cache_service.dart';
import '../services/user_account_service.dart';
import '../services/pia_vpn_service.dart';
import '../services/ebook_manga_metadata_service.dart';
import '../services/sync_service.dart';
import '../services/db_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:lumina_media/services/download_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:watcher/watcher.dart';

/// Sort options for the library
enum LibrarySort {
  title,
  titleDesc,
  dateAdded,
  duration,
  episode,
  newestRelease,
  oldestRelease,
  highestRated,
  mostWatched,
}

/// Filter options for the library
enum LibraryFilter {
  all,
  favorites,
  unplayed,
  inProgress,
  recent,
  fourK,
  noArtwork,
  noMetadata,
  anime,
  hentai,
}

/// Manages the media library state
class MediaProvider extends ChangeNotifier {
  List<MediaFile> _mediaFiles = [];
  MediaFile? _currentMedia;
  PlaybackState _playbackState = PlaybackState.idle;
  final PlaybackSettings _settings = PlaybackSettings();
  final ValueNotifier<Duration> _currentPosition = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<Duration> _totalDuration = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<bool> _isPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<double> _volume = ValueNotifier<double>(1.0);
  List<String> _ollamaModels = [];
  bool _isLoading = false;
  bool _playerError = false;
  String _errorMessage = '';
  bool _isIntroPlaying = false;
  VideoPlayerController? _musicController;
  Timer? _saveDebounce; // BUG-03: debounce library saves
  Timer? _searchDebounce;
  Timer? _storageScanTimer; // Periodic storage scan
  final List<StreamSubscription> _watchers = [];

  // Track background processing for new library items
  final Map<String, String> _processingStatus = {};
  final Map<String, double> _processingProgress = {};

  SubtitleProvider? _subtitleProvider;
  final ModelDownloaderService _downloader = ModelDownloaderService();
  final Map<String, bool> _installedModels = {};
  final Map<String, double> _downloadProgress = {};
  final MetadataService _metadataService = MetadataService();
  final ArtworkScraperService _artworkScraper = ArtworkScraperService();
  final SpotifyService _spotifyService = SpotifyService();
  final YtDlpService _ytdlpService = YtDlpService();
  final MediaScraperService _mediaScraperService = MediaScraperService();
  final SubtitleScraperService _subtitleScraperService =
      SubtitleScraperService();
  final ActorMetadataService _actorMetadataService = ActorMetadataService();
  final EpgWeatherService _epgWeatherService = EpgWeatherService();
  final CacheService _cacheService = CacheService.instance;
  final UserAccountService userAccounts = UserAccountService();
  final PiaVpnService piaVpnService = PiaVpnService();
  DownloadService? _downloadService;

  // ─── Media Server (Remote Access) ─────────────────────────────────────

  final MediaServerService mediaServer = MediaServerService();
  final CloudflareTunnelService cloudflareTunnel = CloudflareTunnelService();
  StreamSubscription<PairingRequest>? _pairingSubscription;

  Future<void> startMediaServer({int port = 8080}) async {
    if (_settings.mediaServerToken.isEmpty) {
      _settings.mediaServerToken = _generateServerToken();
      await _saveSettings();
    }
    await userAccounts.load();
    mediaServer.setUserAccountService(userAccounts);
    mediaServer.setPairedDevices(
      userAccounts.pairedDevices.map((d) => d.id).toList(),
      deniedDeviceIds: userAccounts.deniedDeviceIds,
    );
    mediaServer.setSettings(_settings);
    mediaServer.setAuthToken(_settings.mediaServerToken);
    mediaServer.setDocumentFolders(
      ebookPath: _settings.ebookStoragePath,
      mangaPath: _settings.mangaStoragePath,
      comicsPath: _settings.comicsStoragePath,
    );
    mediaServer.updateLibrary(_mediaFiles);
    await mediaServer.start(port: port);
    mediaServer.getUpdateFolder().ignore(); // eagerly resolve folder path for UI
    if (_settings.enableRemoteTunnel) {
      await cloudflareTunnel.start();
    }

    // Listen for pairing requests
    await _pairingSubscription?.cancel();
    _pairingSubscription = mediaServer.pairingRequests.listen((request) {
      _showPairingRequest(request);
    });

    notifyListeners();
  }

  void _showPairingRequest(PairingRequest request) {
    // This will be handled by the UI listening to a Stream or ValueNotifier
    // For now, we'll store them in a list
    if (!_pairingRequests.contains(request)) {
      _pairingRequests.add(request);
      notifyListeners();
    }
  }

  final List<PairingRequest> _pairingRequests = [];
  List<PairingRequest> get pairingRequests =>
      List.unmodifiable(_pairingRequests);

  Future<void> approvePairing(PairingRequest request) async {
    if (!_settings.pairedDeviceIds.contains(request.deviceId)) {
      _settings.pairedDeviceIds.add(request.deviceId);
      _settings.pairedDevices[request.deviceId] = request.deviceName;
      _settings.deniedDeviceIds.remove(request.deviceId);
      await _saveSettings();
      mediaServer.approvePairing(
        request.deviceId,
        name: request.deviceName,
        ip: request.ipAddress,
      );
    }
    _pairingRequests.remove(request);
    notifyListeners();
  }

  Future<void> denyPairing(PairingRequest request) async {
    _settings.pairedDeviceIds.remove(request.deviceId);
    if (!_settings.deniedDeviceIds.contains(request.deviceId)) {
      _settings.deniedDeviceIds.add(request.deviceId);
      await _saveSettings();
    }
    mediaServer.denyPairing(request.deviceId);
    _pairingRequests.remove(request);
    notifyListeners();
  }

  void revokePairing(String deviceId) {
    _settings.pairedDeviceIds.remove(deviceId);
    _settings.pairedDevices.remove(deviceId);
    _saveSettings();
    mediaServer.revokePairing(deviceId);
    notifyListeners();
  }

  Future<void> startRemoteTunnel() async {
    _settings.enableRemoteTunnel = true;
    await _saveSettings();
    try {
      if (!isMediaServerRunning) {
        await startMediaServer();
      } else {
        await cloudflareTunnel.start();
      }
    } catch (e) {
      debugPrint('[MediaProvider] startRemoteTunnel error: $e');
      _settings.enableRemoteTunnel = false;
      await _saveSettings();
    }
    notifyListeners();
  }

  Future<void> stopRemoteTunnel() async {
    _settings.enableRemoteTunnel = false;
    await _saveSettings();
    await cloudflareTunnel.stop();
    notifyListeners();
  }

  Future<void> syncLibrary() async {
    if (!Platform.isAndroid) return;
    
    final serverUrl = mediaServerRemoteUrl.isNotEmpty 
        ? mediaServerRemoteUrl 
        : mediaServerLocalUrl;
        
    if (serverUrl.isEmpty) return;
    
    final packageInfo = await PackageInfo.fromPlatform();
    final deviceId = packageInfo.packageName + (Platform.isAndroid ? '_android' : '_ios');

    await SyncService.instance.performSync(
      serverUrl: serverUrl,
      token: _settings.mediaServerToken,
      deviceId: deviceId,
    );
    
    // Reload library after sync
    await loadLibrary();
  }

  void toggleAutoStartServer(bool value) {
    _settings.autoStartServer = value;
    _saveSettings();
    notifyListeners();
  }

  Future<void> stopMediaServer() async {
    await cloudflareTunnel.stop();
    await mediaServer.stop();
    notifyListeners();
  }

  bool get isMediaServerRunning => mediaServer.isRunning.value;
  bool get isTunnelRunning => cloudflareTunnel.isRunning.value;
  String get tunnelStatus => cloudflareTunnel.status.value;
  String get tunnelUrl => cloudflareTunnel.publicUrl;
  List<String> get tunnelLogs => cloudflareTunnel.logs.value;
  String get mediaServerLocalUrl => mediaServer.localAddress.value;
  String get mediaServerRemoteUrl => mediaServer.remoteAddress.value;
  String get mediaServerRemoteDomain => mediaServer.remoteDomain;
  String? get mediaServerError => mediaServer.lastError.value;
  List<String> get mediaServerLogs => mediaServer.logs.value;
  String get mediaServerToken => _settings.mediaServerToken;
  String get mediaServerUpdateFolder => mediaServer.updateFolderPath.value;
  bool get enablePiaVpn => _settings.enablePiaVpn;

  void togglePiaVpn(bool value) {
    _settings.enablePiaVpn = value;
    _saveSettings();
    if (value) {
      piaVpnService.connect(
        region: _settings.piaVpnRegion,
        customPath: _settings.piaVpnCustomPath,
      );
    } else {
      piaVpnService.disconnect();
    }

    // Auto-restart tunnel if it's running so it picks up the new network route
    if (isTunnelRunning) {
      debugPrint('[MediaProvider] Restarting tunnel due to VPN change...');
      startRemoteTunnel();
    }

    notifyListeners();
  }

  void setPiaVpnRegion(String region) {
    _settings.piaVpnRegion = region;
    _saveSettings();
    if (_settings.enablePiaVpn) {
      piaVpnService.connect(
        region: region,
        customPath: _settings.piaVpnCustomPath,
      );
    }
    notifyListeners();
  }

  void setPiaVpnCustomPath(String path) {
    _settings.piaVpnCustomPath = path;
    _saveSettings();
    if (_settings.enablePiaVpn && _settings.piaVpnRegion == 'custom') {
      piaVpnService.connect(region: 'custom', customPath: path);
    }
    notifyListeners();
  }

  void setMediaServerRemoteDomain(String domain) {
    mediaServer.setRemoteDomain(domain);
    notifyListeners();
  }

  Future<void> regenerateMediaServerToken() async {
    _settings.mediaServerToken = _generateServerToken();
    mediaServer.setAuthToken(_settings.mediaServerToken);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> clearApiAndArtworkCaches() async {
    await _cacheService.clearAll();
    await _artworkScraper.clearCache();
    notifyListeners();
  }

  Future<int> cacheSizeBytes() => _cacheService.totalSizeBytes();

  void setScraperEnabled(String key, bool enabled) {
    _settings.scraperToggles[key] = enabled;
    _subtitleScraperService.toggleScraper(key, enabled);
    _saveSettings();
    notifyListeners();
  }

  bool isScraperEnabled(String key) => _settings.scraperToggles[key] ?? false;

  void setDocumentMetadataProviderEnabled(String key, bool enabled) {
    _settings.documentMetadataToggles[key] = enabled;
    _saveSettings();
    notifyListeners();
  }

  bool isDocumentMetadataProviderEnabled(String key) =>
      _settings.documentMetadataToggles[key] ?? false;

  List<UserAccount> get users => userAccounts.users;

  String generateUserPassword() => userAccounts.generatePassword();

  Future<UserAccount> createUserAccount({
    required String username,
    required String displayName,
    required String password,
  }) async {
    final user = await userAccounts.createUser(
      username: username,
      displayName: displayName,
      password: password,
    );
    notifyListeners();
    return user;
  }

  Future<void> setUserEnabled(String id, bool enabled) async {
    await userAccounts.setUserEnabled(id, enabled);
    notifyListeners();
  }

  Future<void> resetUserPassword(String id, String password) async {
    await userAccounts.resetPassword(id, password);
    notifyListeners();
  }

  Future<void> deleteUserAccount(String id) async {
    await userAccounts.deleteUser(id);
    notifyListeners();
  }

  // ─── IPTV Proxy Settings ──────────────────────────────────────────────

  void setIptvMaxConnections(int value) {
    _settings.iptvMaxConnections = value;
    _saveSettings();
    mediaServer.setSettings(_settings);
    notifyListeners();
  }

  void setIptvUserAgent(String value) {
    _settings.iptvUserAgent = value;
    _saveSettings();
    mediaServer.setSettings(_settings);
    notifyListeners();
  }

  /// Wire the IPTV provider into the media server so IPTV data is served via API
  void setIptvProviderForServer(IptvProvider iptvProvider) {
    mediaServer.setIptvProvider(iptvProvider);
    mediaServer.setUserAccountService(userAccounts);
    mediaServer.setMusicDownloadCallback((ytResult) async {
      await downloadAndAddMusic(ytResult);
    });
  }

  void setDownloadService(DownloadService downloadService) {
    _downloadService = downloadService;
  }

  // ─── Smart Filters (#10) ──────────────────────────────────────────────

  LibrarySort _currentSort = LibrarySort.title;
  LibraryFilter _currentFilter = LibraryFilter.all;
  String _searchQuery = '';

  // ─── Playlist / Queue (#3) ────────────────────────────────────────────
  final List<MediaFile> _playbackQueue = [];

  // ─── Multiple Library Folders (#13) ────────────────────────────────────
  List<String> _libraryFolders = [];

  ModelDownloaderService get downloader => _downloader;
  Map<String, bool> get installedModels => _installedModels;
  Map<String, double> get downloadProgress => _downloadProgress;

  VideoPlayerController? _videoController;
  VideoPlayerController? get videoController => _videoController;
  bool get isIntroPlaying => _isIntroPlaying;

  VoidCallback? _lastListener;
  VoidCallback? _playbackListener;
  Duration _lastSyncedPosition =
      Duration.zero; // Jitter fix: skip trivial updates

  List<Map<String, String>> _youtubeSearchResults = [];
  List<Map<String, String>> get youtubeSearchResults => _youtubeSearchResults;
  bool _isSearchingYoutube = false;
  bool get isSearchingYoutube => _isSearchingYoutube;
  int _youtubeSearchId = 0;

  List<Map<String, dynamic>> _searchSuggestions = [];
  List<Map<String, dynamic>> get searchSuggestions => _searchSuggestions;

  // ─── Smart Filters Getters (#10) ──────────────────────────────────────
  LibrarySort get currentSort => _currentSort;
  LibraryFilter get currentFilter => _currentFilter;
  String get searchQuery => _searchQuery;

  List<MediaFile> get movieFiles => filteredAndSortedVideos
      .where((m) => m.mediaKind == MediaKind.movie)
      .toList();
  List<MediaFile> get tvFiles => filteredAndSortedVideos
      .where((m) => m.mediaKind == MediaKind.tv)
      .toList();
  List<MediaFile> get audioFiles => filteredAndSortedVideos
      .where((m) => m.mediaKind == MediaKind.audio)
      .toList();
  List<MediaFile> get nsfwFiles => filteredAndSortedVideos
      .where((m) => m.contentType == ContentType.adult)
      .toList();
  List<MediaFile> get favoriteFiles =>
      _mediaFiles.where((m) => m.isFavorite).toList();
  List<MediaFile> get videoFiles =>
      _mediaFiles.where((m) => m.isVideo).toList();
  EpgWeatherService get epgWeatherService => _epgWeatherService;

  String _generateServerToken() {
    final random = math.Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  void _syncServerLibrary() {
    if (isMediaServerRunning) {
      mediaServer.updateLibrary(_mediaFiles);
    }
  }

  void setSort(LibrarySort sort) {
    _currentSort = sort;
    notifyListeners();
  }

  void setFilter(LibraryFilter filter) {
    _currentFilter = filter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _searchDebounce?.cancel();

    if (_searchQuery.length > 1) {
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        _fetchSuggestions(_searchQuery);
        _searchYoutube(_searchQuery);
      });
    } else {
      _youtubeSearchResults = [];
      _searchSuggestions = [];
    }
    notifyListeners();
  }

  Future<void> _fetchSuggestions(String query) async {
    _searchSuggestions = await _spotifyService.getSearchSuggestions(query);
    notifyListeners();
  }

  Future<void> _searchYoutube(String query) async {
    final myId = ++_youtubeSearchId;
    try {
      _isSearchingYoutube = true;
      _youtubeSearchResults = [];
      notifyListeners();

      String musicQuery = "$query music";
      var results = await _ytdlpService.searchYouTube(musicQuery);
      if (results.isEmpty) {
        results = await _ytdlpService.searchYouTube(query);
      }

      if (myId != _youtubeSearchId) return; // Newer search started — abandon

      if (results.isNotEmpty) {
        _youtubeSearchResults = List.from(results);
        notifyListeners();

        final enriched = await _withSpotifyArtwork(results);
        if (myId != _youtubeSearchId) return;

        _youtubeSearchResults = enriched;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('YouTube search error: $e');
    } finally {
      if (myId == _youtubeSearchId) {
        _isSearchingYoutube = false;
        notifyListeners();
      }
    }
  }

  Future<List<Map<String, String>>> searchYoutubeDiscovery(String query) async {
    return await _withSpotifyArtwork(await _ytdlpService.searchYouTube(query));
  }

  Future<List<Map<String, String>>> _withSpotifyArtwork(
    List<Map<String, String>> results,
  ) async {
    final futures = results.map((result) async {
      String rawTitle = result['title'] ?? '';
      // Clean title for better Spotify matching
      String searchTitle = rawTitle
          .replaceAll(RegExp(r'\[.*?\]'), '')
          .replaceAll(RegExp(r'official (video|audio|music|lyric video|music video)', caseSensitive: false), '')
          .replaceAll(RegExp(r'\(official.*?\)', caseSensitive: false), '')
          .replaceAll(RegExp(r'ft\.|feat\.', caseSensitive: false), '')
          .trim();

      try {
        final metadata = await _spotifyService.getTrackMetadata(searchTitle);
        final artwork = _spotifyArtworkUrl(metadata);
        final title = metadata?['name']?.toString();
        final artists = (metadata?['artists'] as List?)
            ?.whereType<Map>()
            .map((artist) => artist['name']?.toString())
            .whereType<String>()
            .join(', ');

        return {
          ...result,
          if (artwork != null) 'spotifyArtwork': artwork,
          if (title != null && title.isNotEmpty) 'spotifyTitle': title,
          if (artists != null && artists.isNotEmpty) 'spotifyArtist': artists,
          'spotifyMetadata': jsonEncode(metadata),
        };
      } catch (e) {
        debugPrint('Spotify enrich error for $searchTitle: $e');
        return result; // Return raw result if Spotify fails
      }
    });

    return await Future.wait(futures);
  }

  Future<MediaFile?> downloadAndAddMusic(Map<String, String> ytResult,
      {String? artworkUrl}) async {
    String? saveDir = _settings.musicSavePath;
    if (saveDir == null) {
      final appDir = await getApplicationDocumentsDirectory();
      saveDir = '${appDir.path}/Music';
      final dir = Directory(saveDir);
      if (!await dir.exists()) await dir.create(recursive: true);
    }

    Map<String, dynamic>? spotifyMetadata;
    if (ytResult['spotifyMetadata'] != null) {
      try {
        spotifyMetadata = jsonDecode(ytResult['spotifyMetadata']!) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (spotifyMetadata == null) {
      String rawTitle = ytResult['title'] ?? '';
      String searchTitle = rawTitle
          .replaceAll(RegExp(r'\[.*?\]'), '')
          .replaceAll(RegExp(r'official (video|audio|music|lyric video|music video)', caseSensitive: false), '')
          .replaceAll(RegExp(r'\(official.*?\)', caseSensitive: false), '')
          .replaceAll(RegExp(r'ft\.|feat\.', caseSensitive: false), '')
          .trim();
      spotifyMetadata = await _spotifyService.getTrackMetadata(searchTitle);
    }

    final spotifyArtwork = _spotifyArtworkUrl(spotifyMetadata);
    
    // Register task in Downloads tab
    final taskId = '${DateTime.now().millisecondsSinceEpoch}_music';
    if (_downloadService != null) {
      _downloadService!.addManualTask(DownloadTask(
        id: taskId,
        url: ytResult['url']!,
        fileName: ytResult['title'] ?? 'Music Download',
        savePath: saveDir,
        status: DownloadStatus.downloading,
      ));
    }

    final filePath = await _ytdlpService.downloadMusic(
      ytResult['url']!,
      saveDir,
      spotifyMetadata: spotifyMetadata,
    );
    
    if (filePath != null) {
      if (_downloadService != null) {
        _downloadService!.updateTask(taskId, status: DownloadStatus.completed, progress: 1.0);
      }
      final fileName = p.basename(filePath);
      return await _addMediaFile(
        filePath,
        fileName,
        artworkUrl: spotifyArtwork ?? artworkUrl,
        spotifyMetadata: spotifyMetadata,
        mediaKind: MediaKind.audio,
      );
    }
    
    if (_downloadService != null) {
      _downloadService!.updateTask(taskId, status: DownloadStatus.failed, errorMessage: 'Download failed');
    }
    return null;
  }

  Future<void> downloadAlbum(Map<String, dynamic> album) async {
    final tracks = await getAlbumTracks(album['id']);
    for (var track in tracks) {
      final query = "${track['name']} ${album['name']}";
      final ytResults = await _ytdlpService.searchYouTube("$query music");
      if (ytResults.isNotEmpty) {
        await downloadAndAddMusic(ytResults.first,
            artworkUrl: album['imageUrl']);
      }
    }
  }

  Future<void> installYtDlp() async {
    await _ytdlpService.install();
    notifyListeners();
  }

  Future<bool> isYtDlpInstalled() => _ytdlpService.isInstalled();

  Future<void> installFfmpeg() async {
    await _ytdlpService.installFfmpeg();
    notifyListeners();
  }

  Future<bool> isFfmpegInstalled() => _ytdlpService.isFfmpegInstalled();

  void setMusicSavePath(String path) {
    _settings.musicSavePath = path;
    _saveSettings();
    scanFolder(path, mediaKind: MediaKind.audio);
    notifyListeners();
  }

  void setMovieStoragePath(String path) {
    _settings.movieStoragePath = path;
    _saveSettings();
    scanFolder(path, mediaKind: MediaKind.movie);
    notifyListeners();
  }

  void setTvShowStoragePath(String path) {
    _settings.tvShowStoragePath = path;
    _saveSettings();
    scanFolder(path, mediaKind: MediaKind.tv);
    notifyListeners();
  }

  void setNsfwStoragePath(String path) {
    _settings.nsfwStoragePath = path;
    _saveSettings();
    scanFolder(path, mediaKind: MediaKind.nsfw);
    notifyListeners();
  }

  void setEbookStoragePath(String path) {
    _settings.ebookStoragePath = path;
    _saveSettings();
    scanFolder(path);
    mediaServer.setDocumentFolders(
      ebookPath: _settings.ebookStoragePath,
      mangaPath: _settings.mangaStoragePath,
      comicsPath: _settings.comicsStoragePath,
    );
    notifyListeners();
  }

  void setMangaStoragePath(String path) {
    _settings.mangaStoragePath = path;
    _saveSettings();
    scanFolder(path);
    mediaServer.setDocumentFolders(
      ebookPath: _settings.ebookStoragePath,
      mangaPath: _settings.mangaStoragePath,
      comicsPath: _settings.comicsStoragePath,
    );
    notifyListeners();
  }

  void setComicsStoragePath(String path) {
    _settings.comicsStoragePath = path;
    _saveSettings();
    scanFolder(path);
    mediaServer.setDocumentFolders(
      ebookPath: _settings.ebookStoragePath,
      mangaPath: _settings.mangaStoragePath,
      comicsPath: _settings.comicsStoragePath,
    );
    notifyListeners();
  }

  bool unlockSecretMenu(String passcode) {
    if (passcode.trim() != '8978888') return false;
    _settings.showNsfwTab = true;
    _saveSettings();
    notifyListeners();
    return true;
  }

  Future<List<Map<String, dynamic>>> getArtistAlbums(String artistName) =>
      _spotifyService.getArtistAlbums(artistName);
  Future<List<Map<String, dynamic>>> getAlbumTracks(String albumId) =>
      _spotifyService.getAlbumTracks(albumId);

  Future<void> _ensureSpotifyCredentials() async {
    if (_spotifyService.clientId.isNotEmpty) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/music_settings.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final id = data['spotifyClientId'] as String? ?? '';
        final secret = data['spotifyClientSecret'] as String? ?? '';
        if (id.isNotEmpty && secret.isNotEmpty) {
          _spotifyService.setCredentials(id, secret);
        }
      }
    } catch (e) {
      debugPrint('Error loading Spotify credentials: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getDiscoveryArtists() async {
    await _ensureSpotifyCredentials();
    return _spotifyService.getDiscoveryArtists();
  }

  Future<List<Map<String, dynamic>>> getDiscoveryAlbums() async {
    await _ensureSpotifyCredentials();
    return _spotifyService.getDiscoveryAlbums();
  }

  /// Computed list of videos with filter + sort + search applied
  List<MediaFile> get filteredAndSortedVideos {
    var videos = _mediaFiles;

    // Apply filter
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    switch (_currentFilter) {
      case LibraryFilter.all:
        break;
      case LibraryFilter.favorites:
        videos = videos.where((m) => m.isFavorite).toList();
        break;
      case LibraryFilter.unplayed:
        videos = videos.where((m) => !m.isWatched && m.watchProgress < 0.01).toList();
        break;
      case LibraryFilter.inProgress:
        videos = videos.where((m) => m.watchProgress > 0.01 && m.watchProgress < 0.90).toList();
        break;
      case LibraryFilter.recent:
        videos = videos.where((m) => m.addedAt.isAfter(thirtyDaysAgo)).toList();
        break;
      case LibraryFilter.fourK:
        videos = videos.where((m) {
          final r = m.resolution?.toLowerCase() ?? '';
          return r.contains('4k') || r.contains('2160') || r.contains('uhd');
        }).toList();
        break;
      case LibraryFilter.noArtwork:
        videos = videos.where((m) => m.posterUrl == null && m.coverArtUrl == null).toList();
        break;
      case LibraryFilter.noMetadata:
        videos = videos.where((m) => m.isAudio
            ? (m.artist == null || m.album == null)
            : (m.synopsis == null && m.description == null)).toList();
        break;
      case LibraryFilter.anime:
        videos = videos.where((m) => m.contentType == ContentType.anime).toList();
        break;
      case LibraryFilter.hentai:
        videos = videos.where((m) => m.contentType == ContentType.adult).toList();
        break;
    }

    // Apply search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      videos = videos
          .where(
            (m) =>
                m.title.toLowerCase().contains(query) ||
                m.libraryTitle.toLowerCase().contains(query) ||
                (m.episodeTitle?.toLowerCase().contains(query) ?? false) ||
                (m.synopsis?.toLowerCase().contains(query) ?? false) ||
                m.genres.any((genre) => genre.toLowerCase().contains(query)) ||
                m.cast.any((actor) => actor.toLowerCase().contains(query)) ||
                m.directors.any(
                  (director) => director.toLowerCase().contains(query),
                ) ||
                (m.animeTitle?.toLowerCase().contains(query) ?? false) ||
                (m.artist?.toLowerCase().contains(query) ?? false) ||
                (m.album?.toLowerCase().contains(query) ?? false) ||
                (m.metadataTitle?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    }

    // Apply sort
    switch (_currentSort) {
      case LibrarySort.title:
        videos.sort((a, b) => a.libraryTitle.compareTo(b.libraryTitle));
        break;
      case LibrarySort.titleDesc:
        videos.sort((a, b) => b.libraryTitle.compareTo(a.libraryTitle));
        break;
      case LibrarySort.dateAdded:
        videos.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
      case LibrarySort.duration:
        videos.sort((a, b) => b.duration.compareTo(a.duration));
        break;
      case LibrarySort.episode:
        videos.sort((a, b) {
          if (a.season != b.season)
            return (a.season ?? 0).compareTo(b.season ?? 0);
          return (a.episode ?? 0).compareTo(b.episode ?? 0);
        });
        break;
      case LibrarySort.newestRelease:
        videos.sort(
          (a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''),
        );
        break;
      case LibrarySort.oldestRelease:
        videos.sort(
          (a, b) => (a.releaseDate ?? '').compareTo(b.releaseDate ?? ''),
        );
        break;
      case LibrarySort.highestRated:
        videos.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
        break;
      case LibrarySort.mostWatched:
        videos.sort((a, b) => b.playCount.compareTo(a.playCount));
        break;
    }

    return videos;
  }

  // ─── Playlist / Queue Getters (#3) ────────────────────────────────────
  List<MediaFile> get playbackQueue => List.unmodifiable(_playbackQueue);
  bool get hasQueue => _playbackQueue.isNotEmpty;

  void addToQueue(MediaFile media) {
    if (!_playbackQueue.any((m) => m.id == media.id)) {
      _playbackQueue.add(media);
      notifyListeners();
    }
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _playbackQueue.length) {
      _playbackQueue.removeAt(index);
      notifyListeners();
    }
  }

  void clearQueue() {
    _playbackQueue.clear();
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = _playbackQueue.removeAt(oldIndex);
    _playbackQueue.insert(newIndex, item);
    notifyListeners();
  }

  Future<void> playNextInQueue() async {
    if (_playbackQueue.isEmpty) {
      final next = findNextMedia(_currentMedia);
      if (next != null) {
        await playMedia(next);
      }
      return;
    }
    final next = _playbackQueue.removeAt(0);
    notifyListeners();
    await playMedia(next);
  }

  /// Find the logical "next" media for a given file (next episode/track)
  MediaFile? findNextMedia(MediaFile? current) {
    if (current == null) return null;

    // 1. If it's a TV Show or Anime, look for next episode
    if (current.mediaKind == MediaKind.tv || current.animeId != null) {
      final siblings = _mediaFiles.where((m) => 
        (m.showTitle != null && m.showTitle == current.showTitle) || 
        (m.animeId != null && m.animeId == current.animeId)
      ).toList();

      // Sort by season then episode
      siblings.sort((a, b) {
        final sA = a.season ?? 1;
        final sB = b.season ?? 1;
        if (sA != sB) return sA.compareTo(sB);
        return (a.episode ?? 0).compareTo(b.episode ?? 0);
      });

      final currentIndex = siblings.indexWhere((m) => m.id == current.id);
      if (currentIndex != -1 && currentIndex < siblings.length - 1) {
        return siblings[currentIndex + 1];
      }
    }

    // 2. If it's music, look for next track in album
    if (current.mediaKind == MediaKind.audio && current.album != null) {
      final albumTracks = _mediaFiles.where((m) => 
        m.mediaKind == MediaKind.audio && m.album == current.album
      ).toList();

      albumTracks.sort((a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0));
      
      final currentIndex = albumTracks.indexWhere((m) => m.id == current.id);
      if (currentIndex != -1 && currentIndex < albumTracks.length - 1) {
        return albumTracks[currentIndex + 1];
      }
    }

    return null;
  }


  // ─── Library Folders Getters (#13) ────────────────────────────────────
  List<String> get libraryFolders => List.unmodifiable(_libraryFolders);
  List<MediaFolder> get storageFolders =>
      List.unmodifiable(_settings.mediaFolders);
  List<MediaFolder> get movieStorageFolders =>
      _settings.mediaFolders.where((f) => f.type == MediaKind.movie).toList();
  List<MediaFolder> get tvStorageFolders =>
      _settings.mediaFolders.where((f) => f.type == MediaKind.tv).toList();

  /// Public getter for the _LibraryFoldersTile widget
  Future<List<String>> getLibraryFolders() async {
    return List.unmodifiable(_libraryFolders);
  }

  /// Public scan method for the _LibraryFoldersTile widget
  Future<void> scanLibraryFolders() async {
    await scanAllFolders();
  }

  Future<void> addLibraryFolder(String path) async {
    if (_libraryFolders.contains(path)) return;
    _libraryFolders.add(path);
    _saveLibraryFolders();
    await scanFolder(path);
    notifyListeners();
  }

  void removeLibraryFolder(String path) {
    _libraryFolders.remove(path);
    _mediaFiles.removeWhere((m) => m.filePath.startsWith(path));
    _saveLibraryFolders();
    _saveLibrary();
    _syncServerLibrary();
    notifyListeners();
  }

  Future<void> addStorageFolder(MediaKind type, String path) async {
    if (_settings.mediaFolders.any((f) => f.path == path && f.type == type))
      return;
    _settings.mediaFolders.add(MediaFolder(path: path, type: type));
    await _saveSettings();
    await scanFolder(path);
    notifyListeners();
  }

  void removeStorageFolder(MediaKind type, String path) {
    _settings.mediaFolders.removeWhere((f) => f.path == path && f.type == type);
    _mediaFiles.removeWhere((m) => m.filePath.startsWith(path));
    _saveSettings();
    _saveLibrary();
    _syncServerLibrary();
    notifyListeners();
  }

  Future<void> scanAllFolders() async {
    _isLoading = true;
    notifyListeners();

    for (final folder in _libraryFolders) {
      await scanFolder(folder);
    }
    for (final folder in _settings.mediaFolders) {
      await scanFolder(folder.path);
    }
    await _scanMusicFolder();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> scanStorageFolders() async {
    _isLoading = true;
    notifyListeners();

    for (final storage in _settings.mediaFolders) {
      await scanFolder(storage.path, mediaKind: storage.type);
    }
    await _scanMusicFolder();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _scanMusicFolder() async {
    List<String> scanDirs = [];
    
    // 1. User-defined music save path
    if (_settings.musicSavePath != null) {
      scanDirs.add(_settings.musicSavePath!);
    }
    
    // 2. Default App Music folder
    final appDir = await getApplicationDocumentsDirectory();
    scanDirs.add(p.join(appDir.path, 'Music'));
    
    // 3. System Music folder
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        scanDirs.add(p.join(userProfile, 'Music'));
      }
    } else if (Platform.isAndroid) {
      // Common Android music path
      scanDirs.add('/storage/emulated/0/Music');
    }

    for (final dirPath in scanDirs) {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        debugPrint('MediaProvider: Scanning music folder: $dirPath');
        await scanFolder(dirPath, mediaKind: MediaKind.audio);
      }
    }
  }

  // Watch folders feature REMOVED

  void _startStorageScanTimer() {
    _storageScanTimer?.cancel();
    _storageScanTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      scanStorageFolders();
    });
  }

  void _cancelStorageScanTimer() {
    _storageScanTimer?.cancel();
    _storageScanTimer = null;
  }

  bool get showThemeParticles => _settings.showThemeParticles;
  void setShowThemeParticles(bool value) {
    _settings.showThemeParticles = value;
    _saveSettings();
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelStorageScanTimer();
    _saveDebounce?.cancel();
    _searchDebounce?.cancel();
    _pairingSubscription?.cancel();
    cloudflareTunnel.isRunning.removeListener(_onTunnelStateChanged);
    cloudflareTunnel.dispose();
    mediaServer.stop();
    super.dispose();
  }

  Future<void> scanFolder(String path, {MediaKind? mediaKind}) async {
    final dir = Directory(path);
    if (!await dir.exists()) return;

    final supportedExtensions = [
      '.mp4', '.mkv', '.mov', '.avi', '.webm', '.wmv', '.flv', '.ts', '.m4v', '.3gp', '.mpg', '.mpeg', '.vob', // Video
      '.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.opus', '.wma', // Audio
    ];

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final ext = entity.path.toLowerCase();
        if (supportedExtensions.any((e) => ext.endsWith(e))) {
          await _addMediaFile(entity.path, p.basename(entity.path),
              mediaKind: mediaKind);
        }
      }
    }
  }

  void setSubtitleProvider(SubtitleProvider provider) {
    _subtitleProvider = provider;
  }

  bool get playerError => _playerError;
  String get errorMessage => _errorMessage;

  List<MediaFile> get mediaFiles => _mediaFiles;
  MediaFile? get currentMedia => _currentMedia;
  PlaybackState get playbackState => _playbackState;
  PlaybackSettings get settings => _settings;
  ValueNotifier<Duration> get currentPosition => _currentPosition;
  ValueNotifier<Duration> get totalDuration => _totalDuration;
  ValueNotifier<bool> get isPlaying => _isPlaying;
  ValueNotifier<double> get volume => _volume;
  List<String> get ollamaModels => _ollamaModels;
  bool get isLoading => _isLoading;
  Map<String, String> get processingStatus => _processingStatus;
  Map<String, double> get processingProgress => _processingProgress;

  Future<List<Map<String, dynamic>>> searchSubtitles(String query,
      {String? imdbId}) {
    return _subtitleScraperService.searchAll(query, imdbId: imdbId);
  }

  Future<List<String>> weatherPlaylist({
    required String apiKey,
    required double latitude,
    required double longitude,
  }) async {
    if (!isScraperEnabled('openweather')) return [];
    final weather =
        await _epgWeatherService.getCurrentWeather(apiKey, latitude, longitude);
    return weather == null
        ? []
        : _epgWeatherService.getWeatherPlaylist(weather);
  }

  /// Pick and load media files
  Future<void> pickMediaFiles() async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4', 'mkv', 'mov', 'avi', 'webm',
          'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a',
        ],
        allowMultiple: true,
      );

      if (result != null) {
        for (final file in result.files) {
          if (file.path != null) {
            await _addMediaFile(file.path!, file.name);
          }
        }
        _saveLibrary();
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pick an external subtitle file (.srt) for the current media
  Future<void> pickSubtitleFile() async {
    if (_currentMedia == null || _subtitleProvider == null) return;

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        await _subtitleProvider!.loadExternalSrt(result.files.single.path!);
      }
    } catch (e) {
      debugPrint('Error picking subtitle file: $e');
    }
  }

  /// Pick a folder and load all media files from it
  Future<void> pickMediaFolder() async {
    _isLoading = true;
    notifyListeners();

    try {
      final selectedDirectory = await FilePicker.getDirectoryPath();

      if (selectedDirectory != null) {
        // Add to persistent library folders
        if (!_libraryFolders.contains(selectedDirectory)) {
          _libraryFolders.add(selectedDirectory);
          _saveLibraryFolders();
        }

        final dir = Directory(selectedDirectory);
        if (await dir.exists()) {
          final supportedExtensions = [
            '.mp4', '.mkv', '.mov', '.avi', '.webm',
            '.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a',
          ];

          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              final ext = entity.path.toLowerCase();
              if (supportedExtensions.any((e) => ext.endsWith(e))) {
                await _addMediaFile(entity.path, p.basename(entity.path));
              }
            }
          }
          _saveLibrary();
        }
      }
    } catch (e) {
      debugPrint('Error picking folder: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add a media file to the library
  Future<MediaFile?> _addMediaFile(
    String filePath,
    String fileName, {
    String? artworkUrl,
    Map<String, dynamic>? spotifyMetadata,
    MediaKind? mediaKind,
  }) async {
    debugPrint('MediaProvider: Attempting to add file: $filePath (Kind: $mediaKind)');
    
    for (final existing in _mediaFiles) {
      if (existing.filePath == filePath) {
        debugPrint('MediaProvider: File already exists in library: $filePath');
        return existing;
      }
    }

    var mediaFile = MediaFile(
      id: DateTime.now().millisecondsSinceEpoch.toString() +
          _mediaFiles.length.toString(),
      filePath: filePath,
      fileName: fileName,
      mediaKind: mediaKind,
      updatedAt: DateTime.now(),
    );

    _mediaFiles.add(mediaFile);
    _syncServerLibrary();
    notifyListeners(); // Immediate feedback

    // Phase 4: Fetch Metadata (Async background enrichment)
    try {
      MediaFile enriched;
      if (mediaFile.isAudio) {
        enriched = await _enrichAudioMetadata(
          mediaFile,
          spotifyMetadata: spotifyMetadata,
        );
      } else {
        enriched = await _enrichVideoMetadata(mediaFile);
      }

      // If we have a specific artwork from Spotify (discovery), override
      final finalFile = artworkUrl != null
          ? enriched.copyWith(posterUrl: artworkUrl, coverArtUrl: artworkUrl, updatedAt: DateTime.now())
          : enriched.copyWith(updatedAt: DateTime.now());

      // Update the file in the list with enriched metadata
      final index = _mediaFiles.indexWhere((m) => m.filePath == filePath);
      if (index != -1) {
        _mediaFiles[index] = finalFile;
        
        // Automatically start processing for videos only if enabled
        if (finalFile.isVideo && _settings.autoProcessNewMedia) {
          autoProcessMedia(finalFile);
        }
        
        _saveLibrary();
        notifyListeners();
      }
      return finalFile;
    } catch (e) {
      debugPrint('Error enriching metadata for $filePath: $e');
      _saveLibrary();
      return mediaFile;
    }
  }

  /// Refresh library state
  Future<void> scanLibrary() async {
    _isLoading = true;
    notifyListeners();
    // Simulate re-scan or load from disk
    await loadLibrary();
    _isLoading = false;
    notifyListeners();
  }

  /// Scan entire library for metadata (Plex-style)
  Future<void> scanLibraryMetadata() async {
    _isLoading = true;
    notifyListeners();

    await scanStorageFolders();

    if (_settings.autoOrganizeManga) {
      await organizeMangaLibrary();
    }
    if (_settings.autoOrganizeComics) {
      await organizeComicsLibrary();
    }
    if (_settings.autoOrganizeEbooks) {
      await organizeEbooksLibrary();
    }

    // Enrich missing metadata — notify listeners every 10 files instead of
    // per-file to avoid thousands of unnecessary UI rebuilds.
    int enriched = 0;
    for (int i = 0; i < _mediaFiles.length; i++) {
      bool changed = false;
      if (_mediaFiles[i].isAudio && _mediaFiles[i].artist == null) {
        _mediaFiles[i] = await _enrichAudioMetadata(_mediaFiles[i]);
        changed = true;
      } else if (_mediaFiles[i].mediaKind != MediaKind.audio) {
        if (_mediaFiles[i].posterUrl == null || _mediaFiles[i].synopsis == null) {
          _mediaFiles[i] = await _enrichVideoMetadata(_mediaFiles[i]);
          changed = true;
        }
      }
      if (changed) {
        enriched++;
        if (enriched % 10 == 0) notifyListeners();
      }
    }
    if (enriched > 0) notifyListeners();

    _isLoading = false;
    _saveLibrary();
    _syncServerLibrary();
    notifyListeners();
  }

  /// Search TMDB for Fix Match dialog
  Future<List<Map<String, dynamic>>> searchTmdbForMatch(String query, {String type = 'movie'}) async {
    final key = dotenv.env['TMDB_API_KEY'] ?? const String.fromEnvironment('TMDB_API_KEY');
    if (key.isEmpty) return [];
    return _mediaScraperService.searchTmdbMulti(query, key, type: type);
  }

  /// Manually refresh metadata for a specific media file
  Future<void> refreshMetadata(MediaFile media) async {
    final index = _mediaFiles.indexWhere((m) => m.id == media.id);
    if (index == -1) return;

    // Reset poster and synopsis to force a clean fetch if desired, 
    // or just pass force: true to the enrichers.
    final target = media.copyWith(
      posterUrl: null,
      coverArtUrl: null,
      synopsis: null,
      description: null,
      updatedAt: DateTime.now(),
    );

    MediaFile enriched;
    if (target.isAudio) {
      enriched = await _enrichAudioMetadata(target);
    } else {
      enriched = await _enrichVideoMetadata(target, force: true);
    }

    _mediaFiles[index] = enriched;
    _saveLibrary();
    _syncServerLibrary();
    notifyListeners();
  }

  /// Apply a manually-chosen TMDB result to a media file (or all episodes of a TV show).
  /// [showGroupKey] is the exact key used by the UI to group episodes — pass it for TV
  /// so we match every episode regardless of which metadata field the title lives in.
  Future<void> applyManualMatch(MediaFile media, Map<String, dynamic> tmdbResult,
      {String? showGroupKey}) async {
    final tmdbApiKey = dotenv.env['TMDB_API_KEY'] ?? const String.fromEnvironment('TMDB_API_KEY');
    final type = tmdbResult['type'] as String? ?? 'movie';
    final id = tmdbResult['id'];

    // Fetch full details from TMDB using the selected id
    Map<String, dynamic>? details;
    if (tmdbApiKey.isNotEmpty && id != null) {
      details = await _mediaScraperService.fetchTmdbDetails(id as int, tmdbApiKey, type: type);
    }

    final title = (details?['title'] ?? details?['name'] ?? tmdbResult['title'] ?? '') as String;
    final posterPath = details?['poster_path'] as String?;
    final posterUrl = posterPath != null
        ? 'https://image.tmdb.org/t/p/original$posterPath'
        : tmdbResult['posterUrl'] as String?;
    final synopsis = (details?['overview'] ?? tmdbResult['overview'] ?? '') as String;
    final releaseDate = (details?['release_date'] ?? details?['first_air_date'] ?? tmdbResult['releaseDate'] ?? '') as String;
    final rating = (details?['vote_average'] as num?)?.toDouble() ?? tmdbResult['rating'] as double?;
    final genres = ((details?['genres'] as List?) ?? [])
        .map<String>((g) => g['name'] as String? ?? '')
        .where((g) => g.isNotEmpty)
        .toList();

    void patchFile(int index) {
      final f = _mediaFiles[index];
      _mediaFiles[index] = f.copyWith(
        movieTitle: type == 'movie' ? title : f.movieTitle,
        showTitle: type == 'tv' ? title : f.showTitle,
        posterUrl: posterUrl,
        synopsis: synopsis.isNotEmpty ? synopsis : f.synopsis,
        releaseDate: releaseDate.isNotEmpty ? releaseDate : f.releaseDate,
        rating: rating ?? f.rating,
        genres: genres.isNotEmpty ? genres : f.genres,
        updatedAt: DateTime.now(),
      );
    }

    if (type == 'tv') {
      // Use showGroupKey (the exact key the UI groups by) when provided;
      // otherwise derive from the same priority chain as _groupShows.
      final groupKey = showGroupKey ?? media.showTitle ?? media.animeTitle ?? media.parsedShowTitle ?? media.libraryTitle;
      for (int i = 0; i < _mediaFiles.length; i++) {
        final m = _mediaFiles[i];
        if (m.mediaKind == MediaKind.tv) {
          final mKey = m.showTitle ?? m.animeTitle ?? m.parsedShowTitle ?? m.libraryTitle;
          if (mKey == groupKey) patchFile(i);
        }
      }
    } else {
      final index = _mediaFiles.indexWhere((m) => m.id == media.id);
      if (index != -1) patchFile(index);
    }

    _saveLibrary();
    _syncServerLibrary();
    notifyListeners();
  }

  Future<MediaFile> _enrichVideoMetadata(MediaFile file, {bool force = false}) async {
    // If it's already fully enriched, we might want to skip or just do a quick check
    var enriched = await _metadataService.enrichMediaFile(file);
    final tmdbApiKey = dotenv.env['TMDB_API_KEY'] ?? const String.fromEnvironment('TMDB_API_KEY');
    
    // Use the best available title for search
    final searchTitle = enriched.movieTitle ?? enriched.showTitle ?? enriched.animeTitle ?? enriched.libraryTitle;

    // 1. Try TMDB (Movies & TV) - Primary high-quality source
    if (_settings.scraperToggles['tmdb'] == true &&
        tmdbApiKey.isNotEmpty &&
        (force || enriched.posterUrl == null || enriched.synopsis == null)) {
      final type = enriched.mediaKind == MediaKind.tv ? 'tv' : 'movie';
      final data =
          await _mediaScraperService.searchTmdb(searchTitle, tmdbApiKey, type: type);
      if (data != null) {
        enriched = enriched.copyWith(
          movieTitle: enriched.mediaKind == MediaKind.movie
              ? (data['title'] as String?)
              : enriched.movieTitle,
          showTitle: enriched.mediaKind == MediaKind.tv
              ? (data['title'] as String?)
              : enriched.showTitle,
          posterUrl: enriched.posterUrl ?? (data['posterUrl'] as String?),
          backdropUrl: enriched.backdropUrl ?? (data['backdropUrl'] as String?),
          synopsis: enriched.synopsis ?? (data['description'] as String?),
          rating: enriched.rating ?? (data['rating'] as num?)?.toDouble(),
          releaseDate: enriched.releaseDate ?? (data['releaseDate'] as String?),
          updatedAt: DateTime.now(),
        );
      }
    }

    // 2. Try Jikan (Anime)
    if (_settings.scraperToggles['jikan'] == true &&
        enriched.contentType == ContentType.anime &&
        enriched.posterUrl == null) {
      final data = await _mediaScraperService.searchJikan(searchTitle);
      if (data != null) {
        enriched = enriched.copyWith(
          animeTitle: data['title'] as String?,
          posterUrl: enriched.posterUrl ?? (data['posterUrl'] as String?),
          synopsis: enriched.synopsis ?? (data['description'] as String?),
          rating: enriched.rating ?? (data['score'] as num?)?.toDouble(),
          updatedAt: DateTime.now(),
        );
      }
    }

    // 3. Try TVMaze (TV Shows secondary fallback)
    if (_settings.scraperToggles['tvmaze'] == true &&
        enriched.mediaKind == MediaKind.tv &&
        enriched.posterUrl == null) {
      final data = await _mediaScraperService.searchTvMaze(searchTitle);
      if (data != null) {
        enriched = enriched.copyWith(
          showTitle: data['title'] as String?,
          posterUrl: data['posterUrl'] as String?,
          synopsis: data['description'] as String?,
          rating: enriched.rating ?? (data['rating'] as num?)?.toDouble(),
          genres: enriched.genres.isNotEmpty
              ? enriched.genres
              : (data['genres'] as List?)?.cast<String>(),
          updatedAt: DateTime.now(),
        );
      }
    }

    // 4. Wikidata for Cast (if missing)
    if (_settings.scraperToggles['wikidata'] == true && enriched.cast.isEmpty) {
      final cast = await _actorMetadataService.getMovieCast(searchTitle);
      if (cast.isNotEmpty) {
        enriched = enriched.copyWith(
          cast: cast
              .map((e) => e['name'] as String? ?? '')
              .where((e) => e.isNotEmpty)
              .toList(),
          castPhotoUrls: cast
              .map((e) => e['imageUrl'] as String? ?? '')
              .where((e) => e.isNotEmpty)
              .toList(),
          updatedAt: DateTime.now(),
        );
      }
    }

    // 5. Final Fallback: ArtworkScraper (iTunes/ScrapeItunesMovie/TMDB Demo)
    if ((enriched.posterUrl == null && enriched.coverArtUrl == null) ||
        (enriched.synopsis == null && enriched.description == null)) {
      final artwork = await _artworkScraper.getArtwork(enriched);
      if (artwork != null) {
        final genres = enriched.genres.isNotEmpty
            ? enriched.genres
            : (artwork.genre == null
                ? const <String>[]
                : artwork.genre!
                    .split(',')
                    .map((genre) => genre.trim())
                    .where((genre) => genre.isNotEmpty)
                    .toList());
        enriched = enriched.copyWith(
          posterUrl: enriched.posterUrl ?? artwork.coverArtUrl,
          coverArtUrl: enriched.coverArtUrl ?? artwork.coverArtUrl,
          backdropUrl: enriched.backdropUrl ?? artwork.backdropUrl,
          movieTitle: enriched.movieTitle ??
              (enriched.mediaKind == MediaKind.movie ? artwork.title : null),
          showTitle: enriched.showTitle ??
              (enriched.mediaKind == MediaKind.tv ? artwork.title : null),
          synopsis: enriched.synopsis ?? artwork.description,
          rating: enriched.rating ?? artwork.rating,
          genres: genres,
          updatedAt: DateTime.now(),
        );
      }
    }

    return enriched;
  }

  Future<MediaFile> _enrichAudioMetadata(
    MediaFile file, {
    Map<String, dynamic>? spotifyMetadata,
    bool force = false,
  }) async {
    // 1. Try local tags first (more accurate for the specific file)
    final localTags = await _ytdlpService.getMediaMetadata(file.filePath);
    String? title = localTags['title'];
    String? artist = localTags['artist'];
    String? album = localTags['album'];
    int? trackNum = int.tryParse(localTags['track']?.split('/').first ?? '');

    // 2. If local tags are mostly empty (or force), fallback to Spotify search by filename
    if (((title == null || title.isEmpty) || force) && spotifyMetadata == null) {
      final metadata = await _spotifyService.getTrackMetadata(file.fileName);
      if (metadata != null) {
        title = metadata['name']?.toString();
        artist = (metadata['artists'] as List).map((a) => a['name']).join(', ');
        album = metadata['album']['name'];
        trackNum = metadata['track_number'];
        final artwork = _spotifyArtworkUrl(metadata);
            
        return file.copyWith(
          metadataTitle: title,
          artist: artist,
          album: album,
          posterUrl: artwork,
          coverArtUrl: artwork,
          releaseDate: metadata['album']['release_date'],
          trackNumber: trackNum,
          updatedAt: DateTime.now(),
        );
      }
    }

    // 2.5 If we have tags but NO artwork (or force), still try Spotify search
    if (file.posterUrl == null || file.posterUrl!.isEmpty || force) {
      final query = (artist != null && title != null) ? '$artist $title' : file.fileName;
      final metadata = await _spotifyService.getTrackMetadata(query);
      if (metadata != null) {
        final artwork = _spotifyArtworkUrl(metadata);
        if (artwork != null) {
          return file.copyWith(
            metadataTitle: title ?? metadata['name']?.toString(),
            artist: artist ?? (metadata['artists'] as List).map((a) => a['name']).join(', '),
            album: album ?? metadata['album']['name'],
            posterUrl: artwork,
            coverArtUrl: artwork,
            updatedAt: DateTime.now(),
          );
        }
      }
    }

    // 3. If we have Spotify metadata passed in (e.g. from a download), use it to fill gaps
    if (spotifyMetadata != null) {
      title ??= spotifyMetadata['name']?.toString();
      artist ??= (spotifyMetadata['artists'] as List).map((a) => a['name']).join(', ');
      album ??= spotifyMetadata['album']['name'];
      trackNum ??= spotifyMetadata['track_number'];
      final artwork = _spotifyArtworkUrl(spotifyMetadata);
          
      return file.copyWith(
        metadataTitle: title,
        artist: artist,
        album: album,
        posterUrl: file.posterUrl ?? artwork,
        coverArtUrl: file.coverArtUrl ?? artwork,
        releaseDate: file.releaseDate ?? spotifyMetadata['album']['release_date'],
        trackNumber: trackNum,
        updatedAt: DateTime.now(),
      );
    }

    // Return what we found from local tags or original file
    return file.copyWith(
      metadataTitle: title?.isNotEmpty == true ? title : null,
      artist: artist?.isNotEmpty == true ? artist : null,
      album: album?.isNotEmpty == true ? album : null,
      trackNumber: trackNum,
      updatedAt: DateTime.now(),
    );
  }

  String? _spotifyArtworkUrl(Map<String, dynamic>? metadata) {
    final album = metadata?['album'] as Map<String, dynamic>?;
    final images = album?['images'] as List?;
    if (images == null || images.isEmpty) return null;
    final first = images.first;
    if (first is! Map) return null;
    return first['url']?.toString();
  }

  /// Remove a media file from the library
  void removeMediaFile(MediaFile file) {
    _mediaFiles.removeWhere((m) => m.id == file.id);
    _playbackQueue.removeWhere((m) => m.id == file.id);
    _processingStatus.remove(file.filePath);
    _processingProgress.remove(file.filePath);
    _subtitleProvider?.engine.cancelTranscription(file.filePath);
    _saveLibrary();
    _syncServerLibrary();
    notifyListeners();
  }

  /// Automatically process a media file (audio extraction -> transcription)
  Future<void> autoProcessMedia(
    MediaFile file, {
    SubtitleProvider? subtitleProvider,
  }) async {
    // BUG-04: Allow retry if previously errored; block only active/done states
    final existingStatus = _processingStatus[file.filePath];
    if (existingStatus != null && existingStatus != 'Error') return;

    // BUG-07: Skip if an SRT file already exists next to the video
    final srtPath = '${file.filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.srt';
    if (await File(srtPath).exists()) {
      _processingStatus[file.filePath] = 'Done (cached SRT)';
      notifyListeners();
      return;
    }

    _processingStatus[file.filePath] = 'Starting...';
    _processingProgress[file.filePath] = 0.1;
    notifyListeners();

    if (_subtitleProvider == null) {
      _processingStatus[file.filePath] = 'Error: No Provider';
      return;
    }

    final subscription = _subtitleProvider!.engine.transcriptionProgress.listen(
      (status) {
        _processingStatus[file.filePath] = status;
        notifyListeners();
      },
    );

    try {
      await _subtitleProvider!.processInBackground(
        file.filePath,
        useOllama: _settings.useOllamaTranslation,
        ollamaModel: _settings.ollamaModel,
        translationProfile: _settings.translationProfile,
      );
      _processingStatus[file.filePath] = 'Done';
      _processingProgress[file.filePath] = 1.0;
    } catch (e) {
      _processingStatus[file.filePath] = 'Error';
    } finally {
      subscription.cancel();
      notifyListeners();
    }
  }

  /// Set the currently playing media
  Future<void> setCurrentMedia(MediaFile media,
      {bool skipIntro = false}) async {
    // If intro is enabled and not skipped, play intro first
    if (_settings.enableIntro && !skipIntro && media.isVideo) {
      _currentMedia = media; // Keep track of what to play after intro
      _isIntroPlaying = true;
      _playbackState = PlaybackState.loading;
      notifyListeners();

      // Stop menu music if playing
      stopMenuMusic();

      await initController("assets/video/intro.mp4", isAsset: true);

      // Hardened completion check: Listen specifically for the end of the intro
      void introListener() {
        if (_videoController != null && _videoController!.value.isCompleted) {
          _videoController!.removeListener(introListener);
          _isIntroPlaying = false;
          if (_currentMedia != null) {
            setCurrentMedia(_currentMedia!, skipIntro: true);
          }
        }
      }

      _videoController?.addListener(introListener);
      return;
    }

    _isIntroPlaying = false;
    final index = _mediaFiles.indexWhere((m) => m.id == media.id);
    if (index != -1) {
      _mediaFiles[index] = _mediaFiles[index].copyWith(
        playCount: _mediaFiles[index].playCount + 1,
        isWatched: true,
        updatedAt: DateTime.now(),
      );
      media = _mediaFiles[index];
      _saveLibrary();
    }
    _currentMedia = media;
    _playbackState = PlaybackState.loading;
    // ARCH-04: Reset subtitle provider state on media switch
    _subtitleProvider?.resetForNewMedia();
    notifyListeners();

    await initController(media.filePath);
  }

  /// Alias for setCurrentMedia
  Future<void> playMedia(MediaFile media) => setCurrentMedia(media);

  /// Initialize video controller
  /// Sync a subtitle provider with the active controller
  void syncSubtitleProvider(SubtitleProvider provider) {
    if (_videoController == null) return;

    if (_lastListener != null) {
      _videoController!.removeListener(_lastListener!);
    }

    _lastListener = () => _globalListener(provider);
    _videoController!.addListener(_lastListener!);
    debugPrint(
      'Subtitles: Synced provider to active controller',
    ); // ARCH-02: use debugPrint
  }

  Future<void> initController(
    String filePath, {
    SubtitleProvider? subtitleProvider,
    bool isAsset = false,
  }) async {
    if (_videoController != null) {
      if (_lastListener != null)
        _videoController!.removeListener(_lastListener!);
      if (_playbackListener != null)
        _videoController!.removeListener(_playbackListener!);
      await _videoController!.dispose();
    }

    if (isAsset) {
      _videoController = VideoPlayerController.asset(filePath);
    } else {
      final uri = Uri.tryParse(filePath);
      final bool isNetwork = uri != null && 
          uri.hasScheme && 
          (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme.length > 1 && !filePath.contains(':\\'));

      if (isNetwork) {
        _videoController = VideoPlayerController.networkUrl(uri!);
      } else if (Platform.isWindows) {
        // Use file controller for local files on Windows (fvp/mdk handles this well)
        _videoController = VideoPlayerController.file(File(filePath));
      } else {
        _videoController = VideoPlayerController.file(File(filePath));
      }
    }

    try {
      await _videoController!.initialize();
      _playbackState = PlaybackState.playing;
      _totalDuration.value = _videoController!.value.duration;

      // Update isPlaying state
      _isPlaying.value = _videoController!.value.isPlaying;
      _playbackListener = () {
        if (_isPlaying.value != _videoController!.value.isPlaying) {
          _isPlaying.value = _videoController!.value.isPlaying;
        }
      };
      _videoController!.addListener(_playbackListener!);

      if (subtitleProvider != null) {
        syncSubtitleProvider(subtitleProvider);
      }

      await _videoController!.setVolume(_volume.value);
      await _videoController!.play();
      _playerError = false;
    } catch (e) {
      _playbackState = PlaybackState.error;
      _playerError = true;
      _errorMessage = e.toString();
      debugPrint('Video init error: $e');
    } finally {
      notifyListeners();
    }
  }

  void _globalListener(SubtitleProvider? subtitleProvider) {
    if (_videoController == null) return;

    final value = _videoController!.value;
    _currentPosition.value = value.position;

    if (value.duration > Duration.zero &&
        value.duration != _totalDuration.value) {
      _totalDuration.value = value.duration;
    }

    final pos = value.position;
    if ((pos - _lastSyncedPosition).abs() > const Duration(milliseconds: 200)) {
      _lastSyncedPosition = pos;
      subtitleProvider?.updateSubtitleForPosition(pos);

      // Phase 3: A-B Repeat Logic
      if (subtitleProvider != null && subtitleProvider.isABRepeatEnabled) {
        final start = subtitleProvider.loopStart;
        final end = subtitleProvider.loopEnd;
        if (start != null && end != null) {
          // If we passed the end of the segment, loop back to start
          if (pos >= end || pos < start - const Duration(milliseconds: 500)) {
            _videoController!.seekTo(start);
            // Ensure we keep playing if it was playing
            if (value.isPlaying) _videoController!.play();
          }
        }
      }
    }

    // Playlist / Queue (#3): Auto-play next when video completes
    if (value.isCompleted) {
      _playbackState = PlaybackState.stopped;
      notifyListeners();

      // If we were playing the intro, now play the actual media
      if (_isIntroPlaying) {
        // This is now also handled by the dedicated listener above for robustness
        return;
      }

      // Resume menu music if no queue
      if (_playbackQueue.isEmpty) {
        playMenuMusic();
      }

      if (_playbackQueue.isNotEmpty) {
        playNextInQueue();
      }
    }
  }

  /// Dispose controller
  Future<void> disposeController() async {
    if (_videoController != null) {
      if (_lastListener != null) {
        _videoController!.removeListener(_lastListener!);
      }
      await _videoController!.dispose();
      _videoController = null;
      notifyListeners();
    }
  }

  /// Update playback state
  void setPlaybackState(PlaybackState state) {
    _playbackState = state;
    notifyListeners();
  }

  /// Update current position
  void setCurrentPosition(Duration position) {
    _currentPosition.value = position;
    // Don't notify listeners here to avoid global rebuilds
  }

  /// Update total duration
  void setTotalDuration(Duration duration) {
    _totalDuration.value = duration;
    // Don't notify listeners here to avoid global rebuilds
  }

  /// Toggle favorite for a media file
  void toggleFavorite(String mediaId) {
     final index = _mediaFiles.indexWhere((m) => m.id == mediaId);
     if (index != -1) {
       _mediaFiles[index] = _mediaFiles[index].copyWith(
         isFavorite: !_mediaFiles[index].isFavorite,
         updatedAt: DateTime.now(),
       );
      _saveLibrary(); // BUG-03: already debounced
      notifyListeners();
    }
  }

  /// Update volume
  void setVolume(double volume) {
    _settings.volume = volume.clamp(0.0, 1.0);
    _volume.value = _settings.volume;
    if (_videoController != null) {
      _videoController!.setVolume(_settings.volume);
    }
    _saveSettings();
    notifyListeners();
  }

  /// Toggle library intro video
  void setEnableIntro(bool enabled) {
    _settings.enableIntro = enabled;
    _saveSettings();
    notifyListeners();
  }

  /// Toggle background menu music
  void setEnableMenuMusic(bool enabled) {
    _settings.enableMenuMusic = enabled;
    _saveSettings();
    if (enabled) {
      playMenuMusic();
    } else {
      stopMenuMusic();
    }
    notifyListeners();
  }

  void setKeepScreenOn(bool value) {
    _settings.keepScreenOn = value;
    _saveSettings();
    notifyListeners();
  }

  Future<void> playMenuMusic() async {
    if (!_settings.enableMenuMusic) return;
    if (_videoController != null && _videoController!.value.isPlaying) return;
    if (_musicController != null && _musicController!.value.isPlaying) return;

    try {
      if (_musicController != null) await _musicController!.dispose();
      _musicController =
          VideoPlayerController.asset("assets/audio/menu_music.mp4");
      await _musicController!.initialize();
      await _musicController!.setLooping(true);
      await _musicController!.setVolume(0.5);
      await _musicController!.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Menu music error: $e');
    }
  }

  Future<void> stopMenuMusic() async {
    if (_musicController != null) {
      await _musicController!.pause();
      await _musicController!.dispose();
      _musicController = null;
      notifyListeners();
    }
  }

  /// Toggle Ollama translation
  void toggleOllamaTranslation(bool value) {
    _settings.useOllamaTranslation = value;
    _saveSettings();
    notifyListeners();
  }

  /// Set Ollama model
  void setOllamaModel(String model) {
    _settings.ollamaModel = model;
    _saveSettings();
    notifyListeners();
  }

  /// Set translation profile
  void setTranslationProfile(TranslationProfile profile) {
    _settings.translationProfile = profile;
    _saveSettings();
    notifyListeners();
  }

  Future<void> organizeMangaLibrary() async {
    final path = _settings.mangaStoragePath;
    if (path == null || path.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      await EbookMangaMetadataService.instance.organizeDocumentFiles(
        path,
        _settings.documentMetadataToggles,
        DocumentLibraryType.manga,
      );
    } catch (e) {
      debugPrint('[Organizer] Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> organizeComicsLibrary() async {
    final path = _settings.comicsStoragePath;
    if (path == null || path.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      await EbookMangaMetadataService.instance.organizeDocumentFiles(
        path,
        _settings.documentMetadataToggles,
        DocumentLibraryType.comics,
      );
    } catch (e) {
      debugPrint('[Organizer] Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> organizeEbooksLibrary() async {
    final path = _settings.ebookStoragePath;
    if (path == null || path.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      await EbookMangaMetadataService.instance.organizeDocumentFiles(
        path,
        _settings.documentMetadataToggles,
        DocumentLibraryType.ebooks,
      );
    } catch (e) {
      debugPrint('[Organizer] Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setAutoOrganizeManga(bool value) {
    _settings.autoOrganizeManga = value;
    _saveSettings();
    notifyListeners();
  }

  void setAutoOrganizeComics(bool value) {
    _settings.autoOrganizeComics = value;
    _saveSettings();
    notifyListeners();
  }

  void setAutoOrganizeEbooks(bool value) {
    _settings.autoOrganizeEbooks = value;
    _saveSettings();
    notifyListeners();
  }

  void setParticleTheme(ParticleTheme theme) {
    _settings.particleTheme = theme;
    _saveSettings();
    notifyListeners();
  }

  /// Toggle automatic background processing for new media
  void toggleAutoProcess(bool value) {
    _settings.autoProcessNewMedia = value;
    _saveSettings();
    notifyListeners();
  }

  /// Fetch available Ollama models
  Future<void> fetchOllamaModels() async {
    final service = OllamaService();
    _ollamaModels = await service.getModels();
    if (_ollamaModels.isNotEmpty) {
      // Prefer Qwen instruct models for Japanese translation quality
      const preferred = [
        'qwen2.5:14b-instruct',
        'qwen2.5:7b-instruct',
        'qwen2.5:14b',
        'qwen2.5:7b',
      ];
      final match = preferred.firstWhere(
        (m) => _ollamaModels.contains(m),
        orElse: () => '',
      );
      if (match.isNotEmpty) {
        _settings.ollamaModel = match;
      } else if (!_ollamaModels.contains(_settings.ollamaModel)) {
        _settings.ollamaModel = _ollamaModels.first;
      }
    }
    notifyListeners();
  }

  /// Toggle mute
  void toggleMute() {
    _settings.isMuted = !_settings.isMuted;
    _saveSettings();
    notifyListeners();
  }

  /// Set playback speed
  void setPlaybackSpeed(double speed) {
    _settings.playbackSpeed = speed.clamp(0.25, 2.0);
    if (_videoController != null) {
      _videoController!.setPlaybackSpeed(_settings.playbackSpeed);
    }
    notifyListeners();
  }

  void toggleFullscreen() {
    _settings.isFullscreen = !_settings.isFullscreen;
    _saveSettings();
    notifyListeners();
  }

  // ─── Playback Controls ────────────────────────────────────────────────

  void pause() {
    _videoController?.pause();
    notifyListeners();
  }

  void resume() {
    _videoController?.play();
    notifyListeners();
  }

  void togglePlay() {
    if (_videoController?.value.isPlaying ?? false) {
      pause();
    } else {
      resume();
    }
  }

  void seek(Duration position) {
    _videoController?.seekTo(position);
  }

  void next() {
    playNextInQueue();
  }

  void previous() {
    // Basic previous: just restart current if no history implemented yet
    _videoController?.seekTo(Duration.zero);
  }

  // ─── Artwork Scraper ──────────────────────────────────────────────────
  bool _isScanningArtwork = false;
  int _artworkScanned = 0;
  int _artworkTotal = 0;

  bool get isScanningArtwork => _isScanningArtwork;
  int get artworkScanned => _artworkScanned;
  int get artworkTotal => _artworkTotal;

  /// Scan all media files for artwork (Plex-style metadata scraping)
  Future<void> scanArtwork() async {
    if (_isScanningArtwork) return;
    _isScanningArtwork = true;
    _artworkScanned = 0;
    _artworkTotal = _mediaFiles.length;
    notifyListeners();

    for (int i = 0; i < _mediaFiles.length; i++) {
      final file = _mediaFiles[i];
      if (file.contentType == ContentType.adult) {
        _artworkScanned++;
        continue; // Skip adult content
      }

      final artwork = await _artworkScraper.getArtwork(file);
      if (artwork != null) {
        // Update the media file with artwork info
        _mediaFiles[i] = file.copyWith(
          coverArtUrl: artwork.coverArtUrl,
          description: artwork.description,
          animeTitle: artwork.title ?? file.animeTitle,
          updatedAt: DateTime.now(),
        );
      }
      _artworkScanned++;
      notifyListeners();
    }

    _isScanningArtwork = false;
    _saveLibrary();
    notifyListeners();
  }

  Future<void> updateMusicArtwork() async {
    if (_isScanningArtwork) return;
    _isScanningArtwork = true;
    final musicFiles = _mediaFiles.where((m) => m.isAudio).toList();
    _artworkScanned = 0;
    _artworkTotal = musicFiles.length;
    notifyListeners();

    for (int i = 0; i < _mediaFiles.length; i++) {
      if (_mediaFiles[i].isAudio) {
        // Force refresh by clearing existing artwork first if missing or force
        if (_mediaFiles[i].posterUrl == null || _mediaFiles[i].posterUrl!.isEmpty) {
          _mediaFiles[i] = await _enrichAudioMetadata(_mediaFiles[i]);
        }
        _artworkScanned++;
        notifyListeners();
      }
    }

    _isScanningArtwork = false;
    _saveLibrary();
    _syncServerLibrary();
    notifyListeners();
  }

  /// Force-process every music track through Spotify: update both artwork and title.
  Future<void> processAllMusicViaSpotify() async {
    if (_isScanningArtwork) return;
    _isScanningArtwork = true;
    _artworkScanned = 0;
    _artworkTotal = _mediaFiles.where((m) => m.isAudio).length;
    notifyListeners();

    for (int i = 0; i < _mediaFiles.length; i++) {
      if (_mediaFiles[i].isAudio) {
        _mediaFiles[i] = await _enrichAudioMetadata(
          _mediaFiles[i],
          force: true,
        );
        _artworkScanned++;
        notifyListeners();
      }
    }

    _isScanningArtwork = false;
    _saveLibrary();
    _syncServerLibrary();
    notifyListeners();
  }

  /// Enrich all music via Spotify, then move files on disk into
  /// {libraryRoot}/{Artist}/{Album}/{TrackNum - Title.ext} folder structure.
  Future<void> organizeMusicToFolders() async {
    if (_isScanningArtwork) return;

    _isScanningArtwork = true;
    _artworkScanned = 0;
    notifyListeners();

    final audioIndices = <int>[];
    for (int i = 0; i < _mediaFiles.length; i++) {
      if (_mediaFiles[i].isAudio) audioIndices.add(i);
    }
    _artworkTotal = audioIndices.length * 2; // phase 1 enrich + phase 2 move
    notifyListeners();

    // Phase 1 — Spotify enrichment (force re-fetch metadata for every track)
    for (final i in audioIndices) {
      _mediaFiles[i] = await _enrichAudioMetadata(_mediaFiles[i], force: true);
      _artworkScanned++;
      if (_artworkScanned % 5 == 0) notifyListeners();
    }

    // Phase 2 — Move files on disk into Artist/Album folders
    int moved = 0;
    for (final i in audioIndices) {
      final m = _mediaFiles[i];

      final artist = m.artist?.trim().isNotEmpty == true ? m.artist! : 'Unknown Artist';
      final album = m.album?.trim().isNotEmpty == true ? m.album! : 'Unknown Album';
      final title = (m.metadataTitle?.trim().isNotEmpty == true
          ? m.metadataTitle!
          : p.basenameWithoutExtension(m.filePath));
      final ext = p.extension(m.filePath).toLowerCase();
      final trackNum = m.trackNumber;

      // Find the library root that contains this file
      String rootDir = p.dirname(m.filePath);
      for (final folder in _libraryFolders) {
        if (m.filePath.startsWith(folder)) {
          rootDir = folder;
          break;
        }
      }

      final safeArtist = _toSafePathSegment(artist);
      final safeAlbum = _toSafePathSegment(album);
      final trackPrefix = trackNum != null
          ? '${trackNum.toString().padLeft(2, '0')} - '
          : '';
      final safeTitle = _toSafePathSegment(title);

      final targetDir = p.join(rootDir, safeArtist, safeAlbum);
      final targetPath = p.join(targetDir, '$trackPrefix$safeTitle$ext');

      if (m.filePath != targetPath) {
        try {
          await Directory(targetDir).create(recursive: true);
          final srcFile = File(m.filePath);
          if (await srcFile.exists()) {
            // rename works cross-directory on same drive; copy+delete for different drive
            try {
              await srcFile.rename(targetPath);
            } on FileSystemException {
              await srcFile.copy(targetPath);
              await srcFile.delete();
            }
            _mediaFiles[i] = m.copyWith(
              filePath: targetPath,
              fileName: p.basename(targetPath),
            );
            moved++;
          }
        } catch (e) {
          print('Music organize: failed to move ${m.filePath}: $e');
        }
      }

      _artworkScanned++;
      if (_artworkScanned % 5 == 0) notifyListeners();
    }

    _isScanningArtwork = false;
    _saveLibrary();
    _syncServerLibrary();
    notifyListeners();
  }

  String _toSafePathSegment(String name) {
    // Remove characters invalid in Windows/macOS/Linux file names
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .trim()
        .replaceAll(RegExp(r'[\s.]+$'), ''); // no trailing spaces or dots
  }

  /// Get the ArtworkScraperService instance
  ArtworkScraperService get artworkScraper => _artworkScraper;

  // MARK: - Persistence

  /// BUG-03: Debounced save — waits 500ms after last call before writing to disk

  Future<void> _saveLibrary() async {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        // Save to JSON (Desktop and Backup)
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/media_library.json');
        final json = _mediaFiles.map((m) => m.toJson()).toList();
        await file.writeAsString(jsonEncode(json));

        // Save to SQLite on Android
        if (Platform.isAndroid) {
          final db = await DBService.instance.database;
          await db.transaction((txn) async {
            for (final media in _mediaFiles) {
              final row = {
                'id': media.id,
                'file_path': media.filePath,
                'file_name': media.fileName,
                'thumbnail_path': media.thumbnailPath,
                'duration': media.duration.inMilliseconds,
                'added_at': media.addedAt.toIso8601String(),
                'updated_at': media.updatedAt.toIso8601String(),
                'is_favorite': media.isFavorite ? 1 : 0,
                'content_type': media.contentType.index,
                'media_kind': media.mediaKind.index,
                'is_watched': media.isWatched ? 1 : 0,
                'play_count': media.playCount,
                'resolution': media.resolution,
                'language': media.language,
                'metadata_id': media.metadataId,
                'movie_title': media.movieTitle,
                'show_title': media.showTitle,
                'episode_title': media.episodeTitle,
                'synopsis': media.synopsis,
                'poster_url': media.posterUrl,
                'backdrop_url': media.backdropUrl,
                'thumbnail_url': media.thumbnailUrl,
                'season_poster_url': media.seasonPosterUrl,
                'trailer_url': media.trailerUrl,
                'release_date': media.releaseDate,
                'release_year': media.releaseYear,
                'rating': media.rating,
                'genres': jsonEncode(media.genres),
                'cast_list': jsonEncode(media.cast),
                'directors': jsonEncode(media.directors),
                'writers': jsonEncode(media.writers),
                'artist': media.artist,
                'album': media.album,
                'track_number': media.trackNumber,
                'watch_progress': media.watchProgress,
                'last_played': media.lastPlayed?.toIso8601String(),
                'is_deleted': media.isDeleted ? 1 : 0,
              };
              await txn.insert('media_library', row,
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
          });
        }
      } catch (e) {
        debugPrint('Error saving library: $e');
      }
    });
  }

  Future<void> loadLibrary() async {
    try {
      if (Platform.isAndroid) {
        _mediaFiles = await SyncService.instance.loadCachedLibrary();
        if (_mediaFiles.isNotEmpty) {
          notifyListeners();
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/media_library.json');
      if (await file.exists() && _mediaFiles.isEmpty) {
        final json = jsonDecode(await file.readAsString()) as List;
        _mediaFiles = json
            .map((j) => MediaFile.fromJson(j as Map<String, dynamic>))
            .toList();

        // REPAIR: Re-classify existing files based on updated logic
        bool changed = false;
        for (int i = 0; i < _mediaFiles.length; i++) {
          final oldKind = _mediaFiles[i].mediaKind;
          final newKind = MediaFile.detectMediaKind(_mediaFiles[i].fileName);
          if (oldKind != newKind) {
            _mediaFiles[i] = _mediaFiles[i].copyWith(mediaKind: newKind);
            changed = true;
          }

          final oldType = _mediaFiles[i].contentType;
          final newType = MediaFile.detectContentType(_mediaFiles[i].fileName);
          if (oldType != newType) {
            _mediaFiles[i] = _mediaFiles[i].copyWith(contentType: newType);
            changed = true;
          }
        }
        if (changed) _saveLibrary();

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading library: $e');
    }
    // ARCH-03: Also restore persisted settings
    await _loadSettings();
    if (Platform.isAndroid && _settings.enableMenuMusic) {
      _settings.enableMenuMusic = false;
      await _saveSettings();
      await stopMenuMusic();
    }
    if (_settings.enablePiaVpn && Platform.isWindows) {
      piaVpnService.connect(region: _settings.piaVpnRegion);
    }
    await userAccounts.load();
    mediaServer.setUserAccountService(userAccounts);
    _syncServerLibrary();
    notifyListeners();
    await _loadLibraryFolders();
    _startStorageScanTimer();

    // Play menu music only if enabled in loaded settings
    await playMenuMusic();

    // Trigger background scan on startup to ensure library (including music) is fresh
    _scanStartup();

    // Auto-start server if enabled
    if (!Platform.isAndroid && _settings.autoStartServer) {
      startMediaServer();
    }

    // Keep provider in sync when tunnel state changes outside our control
    cloudflareTunnel.isRunning.addListener(_onTunnelStateChanged);
  }

  void _onTunnelStateChanged() {
    // If tunnel died unexpectedly while setting said it should be on, sync the flag
    if (!cloudflareTunnel.isRunning.value && _settings.enableRemoteTunnel) {
      // Only clear the flag if this wasn't triggered by a user stop
      // (user stops go through stopRemoteTunnel which sets the flag to false first)
      // We detect "unexpected" by checking the status string set by the reconnect logic
      final s = cloudflareTunnel.status.value;
      final isReconnecting = s.contains('Reconnecting') || s.contains('reconnect');
      if (!isReconnecting) {
        _settings.enableRemoteTunnel = false;
        _saveSettings();
      }
    }
    notifyListeners();
  }

  Future<void> _scanStartup() async {
    await scanStorageFolders();
    // Also perform auto-organization if enabled
    if (_settings.autoOrganizeManga) await organizeMangaLibrary();
    if (_settings.autoOrganizeComics) await organizeComicsLibrary();
    if (_settings.autoOrganizeEbooks) await organizeEbooksLibrary();
  }

  // ARCH-03: Save playback settings to disk
  Future<void> _saveSettings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/playback_settings.json');
      await file.writeAsString(jsonEncode(_settings.toJson()));
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  // ARCH-03: Load playback settings from disk
  Future<void> _loadSettings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/playback_settings.json');
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final loaded = PlaybackSettings.fromJson(json);

        // Sync all settings
        _settings.volume = loaded.volume;
        _settings.playbackSpeed = loaded.playbackSpeed;
        _settings.isMuted = loaded.isMuted;
        _settings.useOllamaTranslation = loaded.useOllamaTranslation;
        _settings.autoProcessNewMedia = loaded.autoProcessNewMedia;
        _settings.enableIntro = loaded.enableIntro;
        _settings.enableMenuMusic = loaded.enableMenuMusic;
        _settings.showNsfwTab = loaded.showNsfwTab;
        _settings.movieStoragePath = loaded.movieStoragePath;
        _settings.tvShowStoragePath = loaded.tvShowStoragePath;
        _settings.nsfwStoragePath = loaded.nsfwStoragePath;
        _settings.musicSavePath = loaded.musicSavePath;
        _settings.ebookStoragePath = loaded.ebookStoragePath;
        _settings.mangaStoragePath = loaded.mangaStoragePath;
        _settings.comicsStoragePath = loaded.comicsStoragePath;
        _settings.ollamaModel = loaded.ollamaModel;
        _settings.translationProfile = loaded.translationProfile;
        _settings.mediaFolders = loaded.mediaFolders;
        _settings.mediaServerToken = loaded.mediaServerToken;
        _settings.pairedDeviceIds = loaded.pairedDeviceIds;
        _settings.pairedDevices = loaded.pairedDevices;
        _settings.deniedDeviceIds = loaded.deniedDeviceIds;
        _settings.enableRemoteTunnel = loaded.enableRemoteTunnel;
        _settings.autoStartServer = loaded.autoStartServer;
        _settings.enablePiaVpn = loaded.enablePiaVpn;
        _settings.piaVpnRegion = loaded.piaVpnRegion;
        _settings.iptvMaxConnections = loaded.iptvMaxConnections;
        _settings.iptvUserAgent = loaded.iptvUserAgent;
        _settings.scraperToggles = loaded.scraperToggles;
        _settings.documentMetadataToggles = loaded.documentMetadataToggles;
        _settings.bookmarks = loaded.bookmarks;

        mediaServer.setAuthToken(_settings.mediaServerToken);
        mediaServer.setPairedDevices(
          _settings.pairedDeviceIds,
          deniedDeviceIds: _settings.deniedDeviceIds,
        );
        mediaServer.setSettings(_settings);
        mediaServer.setDocumentFolders(
          ebookPath: _settings.ebookStoragePath,
          mangaPath: _settings.mangaStoragePath,
          comicsPath: _settings.comicsStoragePath,
        );
        for (final entry in _settings.scraperToggles.entries) {
          _subtitleScraperService.toggleScraper(entry.key, entry.value);
        }

        _volume.value = _settings.volume;
        notifyListeners();

        debugPrint(
          'Settings loaded: intro=${_settings.enableIntro}, music=${_settings.enableMenuMusic}, model=${_settings.ollamaModel}',
        );
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  // ─── Library Folders Persistence (#13) ────────────────────────────────
  Future<void> _saveLibraryFolders() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/library_folders.json');
      await file.writeAsString(jsonEncode(_libraryFolders));
    } catch (e) {
      debugPrint('Error saving library folders: $e');
    }
  }

  Future<void> _loadLibraryFolders() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/library_folders.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as List;
        _libraryFolders = json.cast<String>();
      }
    } catch (e) {
      debugPrint('Error loading library folders: $e');
    }
  }

  Future<void> checkInstalledModels() async {
    const models = [
      'ggml-tiny.bin',
      'ggml-base.bin',
      'ggml-small.bin',
      'ggml-medium.bin',
      'ggml-large-v3.bin',
    ];
    for (final m in models) {
      _installedModels[m] = await _downloader.isModelInstalled(m);
    }
    notifyListeners();
  }

  Future<void> downloadWhisperModel(String modelName) async {
    try {
      await _downloader.downloadModel(modelName, (progress) {
        _downloadProgress[modelName] = progress;
        notifyListeners();
      });
      _installedModels[modelName] = true;
      _downloadProgress.remove(modelName);
      notifyListeners();
    } catch (e) {
      debugPrint('Error downloading $modelName: $e');
      _downloadProgress.remove(modelName);
      notifyListeners();
    }
  }

  Future<void> deleteWhisperModel(String modelName) async {
    await _downloader.deleteModel(modelName);
    _installedModels[modelName] = false;
    notifyListeners();
  }

  // ─── Music Library Helpers ───────────────────────────────────────────

  List<Map<String, dynamic>> getLocalAlbums(String artistName) {
    final artistSongs = audioFiles.where((m) => (m.artist ?? 'Unknown Artist') == artistName).toList();
    final Map<String, List<MediaFile>> albumGroups = {};
    for (var song in artistSongs) {
      final album = song.album ?? 'Unknown Album';
      albumGroups.putIfAbsent(album, () => []).add(song);
    }

    return albumGroups.entries.map((entry) {
      final firstSong = entry.value.first;
      return {
        'id': 'local_${artistName}_${entry.key}',
        'name': entry.key,
        'artist': artistName,
        'imageUrl': firstSong.posterUrl ?? firstSong.coverArtUrl,
        'isLocal': true,
        'songs': entry.value,
        'releaseDate': firstSong.releaseDate ?? '',
      };
    }).toList()..sort((a, b) => (b['releaseDate'] as String).compareTo(a['releaseDate'] as String));
  }

  List<MediaFile> getLocalArtistSongs(String artistName) {
    return audioFiles.where((m) => (m.artist ?? 'Unknown Artist') == artistName).toList()
      ..sort((a, b) {
        if (a.album != b.album) return (a.album ?? '').compareTo(b.album ?? '');
        return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      });
  }
}
