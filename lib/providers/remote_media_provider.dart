import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../services/app_update_service.dart';
import '../services/iptv_service.dart';

class RemoteMediaFile {
  final String id;
  final String title;
  final String fileName;
  final String extension;
  final Duration duration;
  final String? coverArtUrl;
  final String? posterUrl;
  final bool isVideo;
  final bool isAudio;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final String mediaKind;
  final String contentType;
  final String? showTitle;
  final String? movieTitle;
  final int? season;
  final int? episode;
  final String? synopsis;
  final String? releaseDate;
  final double? rating;

  RemoteMediaFile({
    required this.id,
    required this.title,
    required this.fileName,
    required this.extension,
    required this.duration,
    this.coverArtUrl,
    this.posterUrl,
    required this.isVideo,
    required this.isAudio,
    this.artist,
    this.album,
    this.trackNumber,
    required this.mediaKind,
    required this.contentType,
    this.showTitle,
    this.movieTitle,
    this.season,
    this.episode,
    this.synopsis,
    this.releaseDate,
    this.rating,
  });

  String get displayArt => posterUrl ?? coverArtUrl ?? '';

  factory RemoteMediaFile.fromJson(Map<String, dynamic> json) {
    return RemoteMediaFile(
      id: json['id'] as String,
      title: json['title'] as String,
      fileName: json['fileName'] as String,
      extension: json['extension'] as String,
      duration: Duration(milliseconds: json['duration'] as int),
      coverArtUrl: json['coverArtUrl'] as String?,
      posterUrl: json['posterUrl'] as String?,
      isVideo: json['isVideo'] as bool,
      isAudio: json['isAudio'] as bool,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      trackNumber: json['trackNumber'] as int?,
      mediaKind: json['mediaKind'] as String? ?? 'movie',
      contentType: json['contentType'] as String? ?? 'general',
      showTitle: json['showTitle'] as String?,
      movieTitle: json['movieTitle'] as String?,
      season: json['season'] as int?,
      episode: json['episode'] as int?,
      synopsis: json['synopsis'] as String?,
      releaseDate: json['releaseDate'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'fileName': fileName,
        'extension': extension,
        'duration': duration.inMilliseconds,
        'coverArtUrl': coverArtUrl,
        'posterUrl': posterUrl,
        'isVideo': isVideo,
        'isAudio': isAudio,
        'artist': artist,
        'album': album,
        'trackNumber': trackNumber,
        'mediaKind': mediaKind,
        'contentType': contentType,
        'showTitle': showTitle,
        'movieTitle': movieTitle,
        'season': season,
        'episode': episode,
        'synopsis': synopsis,
        'releaseDate': releaseDate,
        'rating': rating,
      };
}

class RemoteMediaProvider extends ChangeNotifier {
  bool _isLoading = false;
  List<RemoteMediaFile> _media = [];
  String? _baseUrl;
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  String? get baseUrl => _baseUrl;
  VideoPlayerController? _controller;
  RemoteMediaFile? _currentMedia;
  bool _isPreparingPlayback = false;
  String? _playbackError;
  static const String _envServerToken =
      String.fromEnvironment('LUMINA_SERVER_TOKEN');
  String? _serverToken = _envServerToken.isNotEmpty ? _envServerToken : null;
  String? _customBaseUrl;
  String? get customBaseUrl => _customBaseUrl;
  String? _authError;
  String? get authError => _authError;
  int _remoteLibrarySize = 0;
  int get remoteLibrarySize => _remoteLibrarySize;

  // Background update check result (set automatically after connect)
  AppUpdateInfo? _pendingUpdate;
  AppUpdateInfo? get pendingUpdate => _pendingUpdate;
  final _updateService = AppUpdateService();

  String? _deviceId;
  String _deviceName = 'Unknown Android Device';
  bool _isPaired = false;
  bool _isDenied = false;
  bool _isFetching = false;

  String? get deviceId => _deviceId;
  String get deviceName => _deviceName;
  bool get isPaired => _isPaired;
  bool get isDenied => _isDenied;

  RemoteMediaProvider() {
    _loadSettings();
  }

  List<RemoteMediaFile> get media => List.unmodifiable(_media);
  bool get isLoading => _isLoading;
  RemoteMediaFile? get currentMedia => _currentMedia;
  VideoPlayerController? get controller => _controller;
  String? get serverToken => _serverToken;
  bool get isPreparingPlayback => _isPreparingPlayback;
  String? get playbackError => _playbackError;

  Future<void> _loadSettings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _deviceName = _defaultDeviceName();

      final file = File('${dir.path}/remote_settings.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        _serverToken = data['token'];
        _customBaseUrl = data['baseUrl'];
        _deviceId = data['deviceId'];
        _isPaired = data['isPaired'] as bool? ?? false;
        _isDenied = data['isDenied'] as bool? ?? false;

        if (_deviceId == null) {
          _deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}';
          _saveSettings();
        }

        // Load cached library immediately so the UI isn't blank on launch
        await _loadMediaCache();
        notifyListeners();
        connectAndFetch();
      } else {
        _deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}';
        _saveSettings();

        // Fallback to old token file if it exists
        final oldFile = File('${dir.path}/remote_token.json');
        if (await oldFile.exists()) {
          final data = jsonDecode(await oldFile.readAsString());
          _serverToken = data['token'];
          notifyListeners();
          connectAndFetch();
        }
      }
    } catch (e) {
      debugPrint('Error loading remote settings: $e');
    }
  }

  Future<void> _loadMediaCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/remote_media_cache.json');
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(data['savedAt'] as String? ?? '');
      if (savedAt != null && DateTime.now().difference(savedAt).inHours < 24) {
        final List<dynamic> mediaJson = data['media'] as List;
        _media = mediaJson
            .map((j) => RemoteMediaFile.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading media cache: $e');
    }
  }

  Future<void> _saveMediaCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/remote_media_cache.json');
      await file.writeAsString(jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'media': _media.map((m) => m.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('Error saving media cache: $e');
    }
  }

  String _defaultDeviceName() {
    if (Platform.isAndroid) {
      return 'Android Device';
    }
    return Platform.localHostname;
  }

  Future<void> _ensureDeviceIdentity() async {
    var changed = false;
    if (_deviceName == 'Unknown Android Device') {
      _deviceName = _defaultDeviceName();
      changed = true;
    }
    if (_deviceId == null || _deviceId!.trim().isEmpty) {
      _deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}';
      changed = true;
    }
    if (changed) {
      await _saveSettings();
    }
  }

  Future<void> _saveSettings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/remote_settings.json');
      await file.writeAsString(jsonEncode({
        'token': _serverToken,
        'baseUrl': _customBaseUrl,
        'deviceId': _deviceId,
        'isPaired': _isPaired,
        'isDenied': _isDenied,
      }));
    } catch (e) {
      debugPrint('Error saving remote settings: $e');
    }
  }

  void setServerToken(String token) {
    _serverToken = token.trim().isEmpty ? null : token.trim();
    _saveSettings();
    notifyListeners();
  }

  void setCustomBaseUrl(String? url) {
    if (url != null && url.isNotEmpty) {
      if (!url.startsWith('http')) {
        url = 'http://$url';
      }
      if (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }
      _customBaseUrl = url;
    } else {
      _customBaseUrl = null;
    }
    _saveSettings();
    notifyListeners();
  }

  Map<String, String> get _authHeaders {
    final headers = <String, String>{};
    if (_serverToken != null) {
      headers['x-lumina-token'] = _serverToken!;
    }
    if (_deviceId != null) {
      headers['x-lumina-device-id'] = _deviceId!;
      headers['x-lumina-device-name'] = _deviceName;
    }
    return headers;
  }

  Map<String, String> get authHeaders => _authHeaders;

  Uri _authUri(String url) {
    final uri = Uri.parse(url);
    if (_serverToken == null) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'token': _serverToken!,
    });
  }

  // IPTV Data
  List<dynamic> _remoteLiveChannels = [];
  List<dynamic> _remoteIptvMovies = [];
  List<dynamic> _remoteIptvSeries = [];
  List<EpgEntry> _remoteEpgEntries = [];

  List<dynamic> get remoteLiveChannels => _remoteLiveChannels;
  List<dynamic> get remoteIptvMovies => _remoteIptvMovies;
  List<dynamic> get remoteIptvSeries => _remoteIptvSeries;
  List<EpgEntry> get remoteEpgEntries => List.unmodifiable(_remoteEpgEntries);

  /// The URLs to try for connection
  List<String> get _possibleUrls {
    final urls = [
      'http://localhost:8080', // Localhost (if server is on same device)
      'http://10.0.2.2:8080', // Android Emulator host IP
      'http://192.168.0.240:8080', // Current Windows Server IP
      'http://192.168.1.100:8080', // Home LAN default
      'http://192.168.0.1:8080', // Alternative gateway
      'https://lumina.orosapp.us', // Remote URL via Cloudflare
    ];

    if (_customBaseUrl != null && !urls.contains(_customBaseUrl)) {
      urls.insert(0, _customBaseUrl!);
    }

    return urls;
  }

  Future<void> discoverServer() async {
    debugPrint('Starting UDP discovery...');
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final discoveryMsg = utf8.encode('LUMINA_DISCOVER');
      socket.send(discoveryMsg, InternetAddress('255.255.255.255'), 8888);

      // Wait for response
      await socket
          .listen((event) {
            if (event == RawSocketEvent.read) {
              final datagram = socket.receive();
              if (datagram != null) {
                final response = jsonDecode(utf8.decode(datagram.data));
                if (response['app'] == 'Lumina Media Server') {
                  _baseUrl = response['localAddress'];
                  _isConnected = true;
                  debugPrint('Server discovered via UDP: $_baseUrl');
                  socket.close();
                  notifyListeners();
                }
              }
            }
          })
          .asFuture()
          .timeout(const Duration(seconds: 3), onTimeout: () {
            socket.close();
          });
    } catch (e) {
      debugPrint('Discovery error: $e');
    }
  }

  Future<void> connectAndFetch() async {
    if (_isFetching) return; // Prevent concurrent calls (IndexedStack builds multiple screens)
    _isFetching = true;
    await _ensureDeviceIdentity();
    _isLoading = true;
    _baseUrl = null;
    notifyListeners();

    // Try to find a working base URL
    _isConnected = false;
    _authError = null;
    for (final url in _possibleUrls) {
      debugPrint('Trying connection to: $url');
      try {
        final response = await http
            .get(Uri.parse('$url/api/discover'), headers: _authHeaders)
            .timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final pairingStatus = data['pairingStatus'] as String? ?? 'unpaired';
          _isPaired = pairingStatus == 'approved';
          _isDenied = pairingStatus == 'denied';
          _remoteLibrarySize = data['librarySize'] ?? 0;
          _baseUrl = url;
          _isConnected = true;
          debugPrint('Connected to: $_baseUrl (Paired: $_isPaired)');
          break;
        }
      } catch (e) {
        debugPrint('Failed to connect to $url: $e');
      }
    }

    if (_isConnected) {
      if (_isPaired) {
        // Already confirmed paired from discover — fetch right away
        await fetchLibrary();
        await fetchIptvData();
        // Verify approval still valid in background (no blocking wait)
        _quickPairingVerify();
        // Check for APK updates in background (Android only)
        if (Platform.isAndroid) _backgroundUpdateCheck();
      } else {
        // Not yet approved — start the polling wait
        await _refreshPairingStatus();
        if (_isPaired) {
          await fetchLibrary();
          await fetchIptvData();
        }
      }
    } else {
      await discoverServer();
      if (_isConnected) {
        if (_isPaired) {
          await fetchLibrary();
          await fetchIptvData();
        } else {
          await _refreshPairingStatus();
          if (_isPaired) {
            await fetchLibrary();
            await fetchIptvData();
          }
        }
      } else {
        if (_media.isEmpty) _media = [];
        _remoteLibrarySize = 0;
        debugPrint('No Lumina Media Server found after scan and discovery');
      }
    }

    _isLoading = false;
    _isFetching = false;
    notifyListeners();
  }

  /// Check for an APK update from the server; stores result for the Updates settings tile.
  Future<void> _backgroundUpdateCheck() async {
    final url = _baseUrl ?? _customBaseUrl;
    final token = _serverToken ?? '';
    if (url == null || url.isEmpty) return;
    try {
      final info = await _updateService.checkForUpdate(url, token);
      if (info != null) {
        _pendingUpdate = info;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// One-shot pairing check (no polling) — runs in background after fast connect
  Future<void> _quickPairingVerify() async {
    if (_baseUrl == null) return;
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/pairing/status'), headers: _authHeaders)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final status = jsonDecode(response.body)['status'] as String? ?? 'unpaired';
        final wasPaired = _isPaired;
        _isPaired = status == 'approved';
        _isDenied = status == 'denied';
        _authError = _isDenied ? 'This device was denied access.' : null;
        await _saveSettings();
        if (!_isPaired && wasPaired) {
          // Lost approval — clear library
          _media = [];
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Quick pairing verify error: $e');
    }
  }

  Future<void> _refreshPairingStatus() async {
    if (_baseUrl == null) return;
    try {
      for (var i = 0; i < 12; i++) {
        final response = await http
            .get(Uri.parse('$_baseUrl/api/pairing/status'),
                headers: _authHeaders)
            .timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final status =
              jsonDecode(response.body)['status'] as String? ?? 'unpaired';
          _isPaired = status == 'approved';
          _isDenied = status == 'denied';
          _authError = _isDenied
              ? 'This device was denied access.'
              : (_isPaired
                  ? null
                  : 'Waiting for approval from the Windows app...');
          notifyListeners();
          if (_isPaired || _isDenied) return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (e) {
      debugPrint('Pairing status error: $e');
    }
  }

  Future<void> fetchIptvData() async {
    if (_baseUrl == null) return;

    try {
      final liveRes = await http.get(Uri.parse('$_baseUrl/api/iptv/live'),
          headers: _authHeaders);
      if (liveRes.statusCode == 200) {
        _remoteLiveChannels =
            _normalizeRemoteIptvUrls(jsonDecode(liveRes.body)['channels']);
      }

      final moviesRes = await http.get(Uri.parse('$_baseUrl/api/iptv/movies'),
          headers: _authHeaders);
      if (moviesRes.statusCode == 200) {
        _remoteIptvMovies =
            _normalizeRemoteIptvUrls(jsonDecode(moviesRes.body)['movies']);
      }

      final seriesRes = await http.get(Uri.parse('$_baseUrl/api/iptv/series'),
          headers: _authHeaders);
      if (seriesRes.statusCode == 200) {
        _remoteIptvSeries =
            _normalizeRemoteIptvUrls(jsonDecode(seriesRes.body)['shows']);
      }

      final epgRes = await http.get(Uri.parse('$_baseUrl/api/iptv/epg'),
          headers: _authHeaders);
      if (epgRes.statusCode == 200) {
        final entries = jsonDecode(epgRes.body)['entries'] as List<dynamic>;
        _remoteEpgEntries = entries
            .map((e) => EpgEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching remote IPTV: $e');
    }
  }

  List<dynamic> _normalizeRemoteIptvUrls(dynamic items) {
    if (_baseUrl == null || items is! List) return [];
    return items.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final url = map['url'] as String? ?? '';
      if (url.startsWith('/')) {
        map['url'] = '$_baseUrl$url';
      }
      return map;
    }).toList();
  }

  static const int _fetchPageSize = 250;

  Future<void> fetchLibrary() async {
    if (_baseUrl == null) return;

    try {
      // Fetch in pages so we never download one giant JSON blob
      final accumulated = <RemoteMediaFile>[];
      int offset = 0;
      int total = 1; // set after first response

      while (offset < total) {
        final url = Uri.parse(
          '$_baseUrl/api/library?offset=$offset&limit=$_fetchPageSize',
        );
        final response =
            await http.get(url, headers: _authHeaders).timeout(
          const Duration(seconds: 30),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          total = data['total'] as int? ?? 0;
          final List<dynamic> page = data['media'] as List;
          accumulated.addAll(
            page.map((j) =>
                RemoteMediaFile.fromJson(j as Map<String, dynamic>)),
          );
          offset += page.length;
          // Notify with what we have so far — UI shows data incrementally
          _media = List.from(accumulated);
          _authError = null;
          _isPaired = true;
          notifyListeners();
          if (page.isEmpty) break; // safety — server returned empty page
        } else if (response.statusCode == 401) {
          _isPaired = false;
          _isDenied = false;
          _authError = 'Waiting for approval from server...';
          _media = [];
          await _saveSettings();
          return;
        } else if (response.statusCode == 403) {
          _isPaired = false;
          _isDenied = true;
          _authError = 'This device was denied access.';
          _media = [];
          await _saveSettings();
          return;
        } else {
          break;
        }
      }

      if (accumulated.isNotEmpty) {
        _media = accumulated;
        _isPaired = true;
        await _saveMediaCache();
        await _saveSettings();
      }
    } catch (e) {
      debugPrint('Error fetching library: $e');
      // Keep cached media on network failure
    }
  }

  Future<List<dynamic>> fetchDocumentJson(String type,
      {bool forceRefresh = false}) async {
    if (_baseUrl == null) return [];
    final path = type == 'manga'
        ? 'manga'
        : type == 'comic'
            ? 'comics'
            : 'ebooks';
    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/api/documents/$path${forceRefresh ? '?refresh=1' : ''}',
        ),
        headers: _authHeaders,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['items'] as List<dynamic>;
      }
    } catch (e) {
      debugPrint('Error fetching $type documents: $e');
    }
    return [];
  }

  Future<void> playMedia(RemoteMediaFile media) async {
    if (_baseUrl == null) return;

    _currentMedia = media;
    _isPreparingPlayback = true;
    _playbackError = null;
    notifyListeners();

    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }

    final streamUrl = '$_baseUrl/api/media/${media.id}/stream';
    _controller = VideoPlayerController.networkUrl(
      _authUri(streamUrl),
      httpHeaders: _authHeaders,
    );

    try {
      await _controller!.initialize();
      await _controller!.play();
    } catch (e) {
      debugPrint('Error playing media: $e');
      _playbackError = e.toString();
    } finally {
      _isPreparingPlayback = false;
    }
    notifyListeners();
  }

  /// Skip to next/previous track in the same mediaKind bucket
  Future<void> skipNext() async {
    if (_currentMedia == null) return;
    final kind = _currentMedia!.mediaKind;
    final bucket = _media.where((m) => m.mediaKind == kind).toList();
    final idx = bucket.indexWhere((m) => m.id == _currentMedia!.id);
    if (idx != -1 && idx < bucket.length - 1) {
      await playMedia(bucket[idx + 1]);
    }
  }

  Future<void> skipPrevious() async {
    if (_currentMedia == null) return;
    final kind = _currentMedia!.mediaKind;
    final bucket = _media.where((m) => m.mediaKind == kind).toList();
    final idx = bucket.indexWhere((m) => m.id == _currentMedia!.id);
    if (idx > 0) {
      await playMedia(bucket[idx - 1]);
    }
  }

  Future<void> stopPlayback() async {
    if (_controller != null) {
      await _controller!.pause();
      await _controller!.dispose();
      _controller = null;
    }
    _currentMedia = null;
    _playbackError = null;
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final current = _controller;
    if (current == null || !current.value.isInitialized) return;
    await current.setPlaybackSpeed(speed);
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    final current = _controller;
    if (current == null || !current.value.isInitialized) return;
    if (current.value.isPlaying) {
      await current.pause();
    } else {
      await current.play();
    }
    notifyListeners();
  }

  Future<bool> downloadMusic(Map<String, String> ytResult) async {
    if (_baseUrl == null) return false;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/music/download'),
        headers: {
          ..._authHeaders,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(ytResult),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error triggering remote download: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
