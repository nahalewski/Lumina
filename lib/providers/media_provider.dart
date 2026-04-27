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
  watched,
  unwatched,
  processed,
  unprocessed,
  anime,
  hentai,
  general,
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
    if (!isMediaServerRunning) {
      await startMediaServer();
    } else {
      await cloudflareTunnel.start();
      notifyListeners();
    }
  }

  Future<void> stopRemoteTunnel() async {
    _settings.enableRemoteTunnel = false;
    await _saveSettings();
    await cloudflareTunnel.stop();
    notifyListeners();
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
    final filePath = await _ytdlpService.downloadMusic(
      ytResult['url']!,
      saveDir,
      spotifyMetadata: spotifyMetadata,
    );
    if (filePath != null) {
      final fileName = p.basename(filePath);
      return await _addMediaFile(
        filePath,
        fileName,
        artworkUrl: spotifyArtwork ?? artworkUrl,
        spotifyMetadata: spotifyMetadata,
        mediaKind: MediaKind.audio,
      );
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
    switch (_currentFilter) {
      case LibraryFilter.all:
        break;
      case LibraryFilter.favorites:
        videos = videos.where((m) => m.isFavorite).toList();
        break;
      case LibraryFilter.watched:
        videos = videos.where((m) => m.isWatched).toList();
        break;
      case LibraryFilter.unwatched:
        videos = videos.where((m) => !m.isWatched).toList();
        break;
      case LibraryFilter.processed:
        videos = videos
            .where(
              (m) =>
                  _processingStatus[m.filePath] == 'Done' ||
                  _processingStatus[m.filePath] == 'Done (cached SRT)',
            )
            .toList();
        break;
      case LibraryFilter.unprocessed:
        videos = videos
            .where(
              (m) =>
                  _processingStatus[m.filePath] == null ||
                  _processingStatus[m.filePath] == 'Error',
            )
            .toList();
        break;
      case LibraryFilter.anime:
        videos =
            videos.where((m) => m.contentType == ContentType.anime).toList();
        break;
      case LibraryFilter.hentai:
        videos =
            videos.where((m) => m.contentType == ContentType.adult).toList();
        break;
      case LibraryFilter.general:
        videos =
            videos.where((m) => m.contentType == ContentType.general).toList();
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
    if (_playbackQueue.isEmpty) return;
    final next = _playbackQueue.removeAt(0);
    notifyListeners();
    await playMedia(next);
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
    String? saveDir = _settings.musicSavePath;
    if (saveDir == null) {
      final appDir = await getApplicationDocumentsDirectory();
      saveDir = '${appDir.path}/Music';
    }
    final dir = Directory(saveDir);
    if (await dir.exists()) {
      await scanFolder(saveDir, mediaKind: MediaKind.audio);
    }
  }

  // Watch folders feature REMOVED

  void _startStorageScanTimer() {
    // Watch folders feature REMOVED - automatic scanning is disabled
  }

  void _cancelStorageScanTimer() {
    // Watch folders feature REMOVED
  }

  @override
  void dispose() {
    _cancelStorageScanTimer();
    _saveDebounce?.cancel();
    _searchDebounce?.cancel();
    _pairingSubscription?.cancel();
    cloudflareTunnel.stop();
    mediaServer.stop();
    super.dispose();
  }

  Future<void> scanFolder(String path, {MediaKind? mediaKind}) async {
    final dir = Directory(path);
    if (!await dir.exists()) return;

    final supportedExtensions = [
      '.mp4',
      '.mkv',
      '.mov',
      '.avi',
      '.webm',
      '.mp3',
      '.wav',
      '.flac',
      '.aac',
      '.ogg',
      '.m4a',
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
          ? enriched.copyWith(posterUrl: artworkUrl, coverArtUrl: artworkUrl)
          : enriched;

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

    for (int i = 0; i < _mediaFiles.length; i++) {
      if (_mediaFiles[i].isAudio && _mediaFiles[i].artist == null) {
        _mediaFiles[i] = await _enrichAudioMetadata(_mediaFiles[i]);
        notifyListeners();
      } else if (_mediaFiles[i].mediaKind != MediaKind.audio) {
        _mediaFiles[i] = await _enrichVideoMetadata(_mediaFiles[i]);
        notifyListeners();
      }
    }

    _isLoading = false;
    _saveLibrary();
    _syncServerLibrary();
    notifyListeners();
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

  Future<MediaFile> _enrichVideoMetadata(MediaFile file, {bool force = false}) async {
    // If it's already fully enriched, we might want to skip or just do a quick check
    var enriched = await _metadataService.enrichMediaFile(file);
    final query = enriched.libraryTitle;

    final tmdbApiKey = dotenv.env['TMDB_API_KEY'];

    // 1. Try TMDB (Movies & TV) - Primary high-quality source
    if (_settings.scraperToggles['tmdb'] == true &&
        tmdbApiKey != null &&
        (force || enriched.posterUrl == null || enriched.synopsis == null)) {
      final type = enriched.mediaKind == MediaKind.tv ? 'tv' : 'movie';
      final data =
          await _mediaScraperService.searchTmdb(query, tmdbApiKey, type: type);
      if (data != null) {
        enriched = enriched.copyWith(
          movieTitle: enriched.mediaKind == MediaKind.movie
              ? (data['title'] as String?)
              : enriched.movieTitle,
          showTitle: enriched.mediaKind == MediaKind.tv
              ? (data['title'] as String?)
              : enriched.showTitle,
          posterUrl: enriched.posterUrl ?? (data['posterUrl'] as String?),
          synopsis: enriched.synopsis ?? (data['description'] as String?),
          rating: enriched.rating ?? (data['rating'] as num?)?.toDouble(),
          releaseDate: enriched.releaseDate ?? (data['releaseDate'] as String?),
        );
      }
    }

    // 2. Try Jikan (Anime)
    if (_settings.scraperToggles['jikan'] == true &&
        enriched.contentType == ContentType.anime &&
        enriched.posterUrl == null) {
      final data = await _mediaScraperService.searchJikan(query);
      if (data != null) {
        enriched = enriched.copyWith(
          animeTitle: data['title'] as String?,
          posterUrl: enriched.posterUrl ?? (data['posterUrl'] as String?),
          synopsis: enriched.synopsis ?? (data['description'] as String?),
          rating: enriched.rating ?? (data['score'] as num?)?.toDouble(),
        );
      }
    }

    // 3. Try TVMaze (TV Shows secondary fallback)
    if (_settings.scraperToggles['tvmaze'] == true &&
        enriched.mediaKind == MediaKind.tv &&
        enriched.posterUrl == null) {
      final data = await _mediaScraperService.searchTvMaze(query);
      if (data != null) {
        enriched = enriched.copyWith(
          showTitle: data['title'] as String?,
          posterUrl: data['posterUrl'] as String?,
          synopsis: data['description'] as String?,
          rating: enriched.rating ?? (data['rating'] as num?)?.toDouble(),
          genres: enriched.genres.isNotEmpty
              ? enriched.genres
              : (data['genres'] as List?)?.cast<String>(),
        );
      }
    }

    // 4. Wikidata for Cast (if missing)
    if (_settings.scraperToggles['wikidata'] == true && enriched.cast.isEmpty) {
      final cast = await _actorMetadataService.getMovieCast(query);
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
        );
      }
    }

    return enriched;
  }

  Future<MediaFile> _enrichAudioMetadata(
    MediaFile file, {
    Map<String, dynamic>? spotifyMetadata,
  }) async {
    final metadata = spotifyMetadata ??
        await _spotifyService.getTrackMetadata(file.fileName);
    if (metadata != null) {
      final name = metadata['name']?.toString() ?? file.title;
      final artists =
          (metadata['artists'] as List).map((a) => a['name']).join(', ');
      final album = metadata['album']['name'];
      final artwork = metadata['album']['images'].isNotEmpty
          ? metadata['album']['images'][0]['url']
          : null;
      final releaseDate = metadata['album']['release_date'];
      final trackNumber = metadata['track_number'];

      return file.copyWith(
        metadataTitle: name,
        artist: artists,
        album: album,
        posterUrl: artwork,
        coverArtUrl: artwork,
        releaseDate: releaseDate,
        trackNumber: trackNumber,
      );
    }
    return file;
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
        // Ensure absolute path and correct URI format for fvp on Windows
        final absolutePath = File(filePath).absolute.path;
        _videoController = VideoPlayerController.networkUrl(
          Uri.file(absolutePath),
        );
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
      _mediaFiles[index].isFavorite = !_mediaFiles[index].isFavorite;
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
        );
      }
      _artworkScanned++;
      notifyListeners();
    }

    _isScanningArtwork = false;
    _saveLibrary();
    notifyListeners();
  }

  /// Get the ArtworkScraperService instance
  ArtworkScraperService get artworkScraper => _artworkScraper;

  // MARK: - Persistence

  /// BUG-03: Debounced save — waits 500ms after last call before writing to disk

  Future<void> _saveLibrary() async {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/media_library.json');
        final json = _mediaFiles.map((m) => m.toJson()).toList();
        await file.writeAsString(jsonEncode(json));
      } catch (e) {
        debugPrint('Error saving library: $e');
      }
    });
  }

  Future<void> loadLibrary() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/media_library.json');
      if (await file.exists()) {
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
}
