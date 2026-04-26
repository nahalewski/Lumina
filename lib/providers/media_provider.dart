import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
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

  // ─── Media Server (Remote Access) ─────────────────────────────────────

  final MediaServerService mediaServer = MediaServerService();
  final CloudflareTunnelService cloudflareTunnel = CloudflareTunnelService();

  Future<void> startMediaServer({int port = 8080}) async {
    mediaServer.updateLibrary(_mediaFiles);
    await mediaServer.start(port: port);
    // Auto-start Cloudflare tunnel to expose the server publicly
    await cloudflareTunnel.start();
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

  void setMediaServerRemoteDomain(String domain) {
    mediaServer.setRemoteDomain(domain);
    notifyListeners();
  }

  /// Wire the IPTV provider into the media server so IPTV data is served via API
  void setIptvProviderForServer(IptvProvider iptvProvider) {
    mediaServer.setIptvProvider(iptvProvider);
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

  List<Map<String, dynamic>> _searchSuggestions = [];
  List<Map<String, dynamic>> get searchSuggestions => _searchSuggestions;

  // ─── Smart Filters Getters (#10) ──────────────────────────────────────
  LibrarySort get currentSort => _currentSort;
  LibraryFilter get currentFilter => _currentFilter;
  String get searchQuery => _searchQuery;

  List<MediaFile> get movieFiles => filteredAndSortedVideos.where((m) => m.mediaKind == MediaKind.movie).toList();
  List<MediaFile> get tvFiles => filteredAndSortedVideos.where((m) => m.mediaKind == MediaKind.tv).toList();
  List<MediaFile> get audioFiles => filteredAndSortedVideos.where((m) => m.mediaKind == MediaKind.audio).toList();
  List<MediaFile> get favoriteFiles => _mediaFiles.where((m) => m.isFavorite).toList();
  List<MediaFile> get videoFiles => _mediaFiles.where((m) => m.isVideo).toList();

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
    
    if (_searchQuery.length > 2) {
      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
        _searchYoutube(_searchQuery);
        _fetchSuggestions(_searchQuery);
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
    if (_isSearchingYoutube) return;
    _isSearchingYoutube = true;
    notifyListeners();

    try {
      // Append "music" to ensure we get music-related results for the predictive search
      final musicQuery = "$query music";
      final results = await _ytdlpService.searchYouTube(musicQuery);
      _youtubeSearchResults = results;
    } catch (e) {
      debugPrint('YouTube search error: $e');
    } finally {
      _isSearchingYoutube = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, String>>> searchYoutubeDiscovery(String query) async {
    return await _ytdlpService.searchYouTube(query);
  }

  Future<void> downloadAndAddMusic(Map<String, String> ytResult, {String? artworkUrl}) async {
    String? saveDir = _settings.musicSavePath;
    if (saveDir == null) {
      final appDir = await getApplicationDocumentsDirectory();
      saveDir = '${appDir.path}/Music';
      final dir = Directory(saveDir);
      if (!await dir.exists()) await dir.create(recursive: true);
    }

    final filePath = await _ytdlpService.downloadMusic(ytResult['url']!, saveDir);
    if (filePath != null) {
      final fileName = filePath.split('/').last;
      await _addMediaFile(filePath, fileName, artworkUrl: artworkUrl);
    }
  }

  Future<void> downloadAlbum(Map<String, dynamic> album) async {
    final tracks = await getAlbumTracks(album['id']);
    for (var track in tracks) {
      final query = "${track['name']} ${album['name']}";
      final ytResults = await _ytdlpService.searchYouTube("$query music");
      if (ytResults.isNotEmpty) {
        await downloadAndAddMusic(ytResults.first, artworkUrl: album['imageUrl']);
      }
    }
  }

  Future<void> installYtDlp() async {
    await _ytdlpService.install();
    notifyListeners();
  }

  Future<bool> isYtDlpInstalled() => _ytdlpService.isInstalled();

  void setMusicSavePath(String path) {
    _settings.musicSavePath = path;
    _saveSettings();
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getArtistAlbums(String artistName) => _spotifyService.getArtistAlbums(artistName);
  Future<List<Map<String, dynamic>>> getAlbumTracks(String albumId) => _spotifyService.getAlbumTracks(albumId);
  Future<List<Map<String, dynamic>>> getDiscoveryArtists() => _spotifyService.getDiscoveryArtists();
  Future<List<Map<String, dynamic>>> getDiscoveryAlbums() => _spotifyService.getDiscoveryAlbums();

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
                (m.animeTitle?.toLowerCase().contains(query) ?? false),
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
    notifyListeners();
  }

  Future<void> scanAllFolders() async {
    _isLoading = true;
    notifyListeners();

    for (final folder in _libraryFolders) {
      await scanFolder(folder);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> scanFolder(String path) async {
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
          _addMediaFile(entity.path, entity.path.split('/').last);
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

  /// Pick and load media files
  Future<void> pickMediaFiles() async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4',
          'mkv',
          'mov',
          'avi',
          'webm',
          'mp3',
          'wav',
          'flac',
          'aac',
          'ogg',
          'm4a',
        ],
        allowMultiple: true,
      );

      if (result != null) {
        for (final file in result.files) {
          if (file.path != null) {
            _addMediaFile(file.path!, file.name);
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
        final dir = Directory(selectedDirectory);
        if (await dir.exists()) {
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
                _addMediaFile(entity.path, entity.path.split('/').last);
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
  Future<void> _addMediaFile(String filePath, String fileName, {String? artworkUrl}) async {
    if (_mediaFiles.any((m) => m.filePath == filePath)) return;

    var mediaFile = MediaFile(
      id: DateTime.now().millisecondsSinceEpoch.toString() +
          _mediaFiles.length.toString(),
      filePath: filePath,
      fileName: fileName,
    );

    // Phase 4: Fetch Metadata
    if (mediaFile.isAudio) {
      mediaFile = await _enrichAudioMetadata(mediaFile);
    }
    // Enrich
    final enriched = await _metadataService.enrichMediaFile(mediaFile);
    
    // If we have a specific artwork from Spotify (discovery), override
    final finalFile = artworkUrl != null 
      ? enriched.copyWith(posterUrl: artworkUrl, coverArtUrl: artworkUrl)
      : enriched;

    _mediaFiles.add(finalFile);

    // Automatically start processing for videos only if enabled
    if (finalFile.isVideo && _settings.autoProcessNewMedia) {
      autoProcessMedia(finalFile);
    }

    _saveLibrary();
    notifyListeners();
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

    for (int i = 0; i < _mediaFiles.length; i++) {
      if (_mediaFiles[i].isAudio && _mediaFiles[i].artist == null) {
        _mediaFiles[i] = await _enrichAudioMetadata(_mediaFiles[i]);
        notifyListeners();
      } else if (_mediaFiles[i].mediaKind != MediaKind.audio && _mediaFiles[i].animeTitle == null) {
        _mediaFiles[i] = await _metadataService.enrichMediaFile(_mediaFiles[i]);
        notifyListeners();
      }
    }

    _isLoading = false;
    _saveLibrary();
    notifyListeners();
  }

  Future<MediaFile> _enrichAudioMetadata(MediaFile file) async {
    final metadata = await _spotifyService.getTrackMetadata(file.fileName);
    if (metadata != null) {
      final artists = (metadata['artists'] as List).map((a) => a['name']).join(', ');
      final album = metadata['album']['name'];
      final artwork = metadata['album']['images'].isNotEmpty 
          ? metadata['album']['images'][0]['url'] 
          : null;
      final releaseDate = metadata['album']['release_date'];
      final trackNumber = metadata['track_number'];
      
      return file.copyWith(
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

  /// Remove a media file from the library
  void removeMediaFile(MediaFile file) {
    _mediaFiles.removeWhere((m) => m.id == file.id);
    _playbackQueue.removeWhere((m) => m.id == file.id);
    _processingStatus.remove(file.filePath);
    _processingProgress.remove(file.filePath);
    _subtitleProvider?.engine.cancelTranscription(file.filePath);
    _saveLibrary();
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
  Future<void> setCurrentMedia(MediaFile media, {bool skipIntro = false}) async {
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
      _videoController = VideoPlayerController.file(File(filePath));
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

  Future<void> playMenuMusic() async {
    if (!_settings.enableMenuMusic) return;
    if (_videoController != null && _videoController!.value.isPlaying) return;
    if (_musicController != null && _musicController!.value.isPlaying) return;

    try {
      if (_musicController != null) await _musicController!.dispose();
      _musicController = VideoPlayerController.asset("assets/audio/menu_music.mp4");
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
    await _loadLibraryFolders();
    
    // Auto-start media server on launch
    await startMediaServer(port: 8080);

    // Play menu music only if enabled in loaded settings
    await playMenuMusic();
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
        _settings.ollamaModel = loaded.ollamaModel;
        _settings.translationProfile = loaded.translationProfile;
        
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
