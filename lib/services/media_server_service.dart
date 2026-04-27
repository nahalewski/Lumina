import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../models/media_model.dart';
import '../providers/iptv_provider.dart';
import 'iptv_service.dart';
import 'ebook_manga_metadata_service.dart';
import 'user_account_service.dart';

/// HTTP server that serves the media library and IPTV data to remote clients (e.g., Android app).
///
/// Supports both local network access and remote access via a public domain.
/// No authentication — this is a private app for personal use.
///
/// Endpoints:
///   GET  /api/discover           → Server info (local IP, remote domain, port)
///   GET  /api/health             → Health check
///   GET  /api/library            → JSON list of all media files
///   GET  /api/media/:id          → JSON details for a single media file
///   GET  /api/media/:id/stream   → Video stream (supports range requests)
///   GET  /api/media/:id/srt      → SRT subtitle file (if exists)
///   GET  /api/thumbnail/:id      → Thumbnail/cover art image
///   GET  /api/iptv/live          → IPTV live channels
///   GET  /api/iptv/movies        → IPTV movies
///   GET  /api/iptv/series        → IPTV TV shows
///   GET  /api/iptv/stream?url=... → Proxy stream for IPTV channel/movie
class MediaServerService {
  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  static const int _discoveryPort = 8888;
  List<MediaFile> _library = [];
  final Map<String, MediaFile> _libraryById = {};
  List<Map<String, dynamic>> _libraryJsonCache = [];
  int _port = 8080;
  String _remoteDomain = '';
  String _authToken = '';
  String? _ebookPath;
  String? _mangaPath;
  String? _comicsPath;
  final List<String> _pairedDeviceIds = [];
  final List<String> _deniedDeviceIds = [];
  final Set<String> _pendingDeviceIds = {};
  final StreamController<PairingRequest> _pairingController =
      StreamController.broadcast();
  Stream<PairingRequest> get pairingRequests => _pairingController.stream;
  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  final ValueNotifier<String> localAddress = ValueNotifier('');
  final ValueNotifier<String> remoteAddress = ValueNotifier('');
  final ValueNotifier<int> activeConnections = ValueNotifier(0);
  final ValueNotifier<String?> lastError = ValueNotifier(null);
  final ValueNotifier<List<String>> logs = ValueNotifier([]);

  /// Reference to the IPTV provider for serving IPTV data via API
  IptvProvider? _iptvProvider;
  UserAccountService? _userAccountService;
  final Map<String, String> _iptvStreamUrls = {};
  final Map<String, _IptvStreamSession> _iptvSessions = {};
  PlaybackSettings _settings = PlaybackSettings();
  
  /// Callback for music downloads (usually provided by MediaProvider)
  Future<void> Function(Map<String, String> ytResult)? onMusicDownload;

  void setMusicDownloadCallback(Future<void> Function(Map<String, String>) callback) {
    onMusicDownload = callback;
  }

  void setSettings(PlaybackSettings settings) {
    _settings = settings;
  }

  /// Set the IPTV provider reference so the server can serve IPTV data
  void setIptvProvider(IptvProvider provider) {
    _iptvProvider = provider;
  }

  void setUserAccountService(UserAccountService service) {
    _userAccountService = service;
  }

  /// Set the remote domain for external access (e.g., "lumina.orosapp.us")
  void setRemoteDomain(String domain) {
    _remoteDomain = domain.trim();
    if (domain.isNotEmpty) {
      remoteAddress.value = 'https://$domain';
    } else {
      remoteAddress.value = '';
    }
  }

  void setAuthToken(String token) {
    _authToken = token.trim();
  }

  void setDocumentFolders({
    String? ebookPath,
    String? mangaPath,
    String? comicsPath,
  }) {
    _ebookPath = ebookPath;
    _mangaPath = mangaPath;
    _comicsPath = comicsPath;
  }

  /// Get the remote domain
  String get remoteDomain => _remoteDomain;

  /// Start the HTTP server on the given port
  Future<void> start({int port = 8080}) async {
    if (_server != null) return;

    _port = port;
    lastError.value = null;
    _addLog('Starting server on port $_port...');

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      isRunning.value = true;
      _startDiscoveryListener();

      // Get the local IP address for display
      final interfaces = await NetworkInterface.list();
      String? localIp;
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            localIp = addr.address;
            break;
          }
        }
        if (localIp != null) break;
      }
      localAddress.value = 'http://${localIp ?? 'localhost'}:$_port';

      _addLog('Server started on ${localAddress.value}');
      debugPrint('[MediaServer] Started on ${localAddress.value}');
      if (_remoteDomain.isNotEmpty) {
        debugPrint('[MediaServer] Remote access via https://$_remoteDomain');
      }

      _server!.listen((request) {
        unawaited(_handleRequest(request));
      }, onError: (e) {
        debugPrint('[MediaServer] Error: $e');
      });
    } catch (e) {
      final error = 'Failed to start: $e';
      _addLog('ERROR: $error');
      debugPrint('[MediaServer] $error');
      lastError.value = error;
      isRunning.value = false;
      rethrow;
    }
  }

  /// Stop the HTTP server

  Future<void> _startDiscoveryListener() async {
    try {
      _discoverySocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort);
      _discoverySocket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket?.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            if (message == 'LUMINA_DISCOVER') {
              final response = jsonEncode({
                'app': 'Lumina Media Server',
                'localAddress': localAddress.value,
                'remoteAddress':
                    remoteAddress.value.isNotEmpty ? remoteAddress.value : null,
              });
              _discoverySocket?.send(
                  utf8.encode(response), datagram.address, datagram.port);
            }
          }
        }
      });
      _addLog('Discovery listener started on UDP $_discoveryPort');
    } catch (e) {
      _addLog('Failed to start discovery listener: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    isRunning.value = false;
    activeConnections.value = 0;
    _addLog('Server stopped');
    debugPrint('[MediaServer] Stopped');
  }

  /// Update the library being served

  void setPairedDevices(List<String> deviceIds,
      {List<String> deniedDeviceIds = const []}) {
    _pairedDeviceIds.clear();
    _pairedDeviceIds.addAll(deviceIds);
    _deniedDeviceIds
      ..clear()
      ..addAll(deniedDeviceIds);
  }

  void approvePairing(String deviceId, {String name = 'Unknown Device', String? ip}) {
    _deniedDeviceIds.remove(deviceId);
    _pendingDeviceIds.remove(deviceId);
    if (!_pairedDeviceIds.contains(deviceId)) {
      _pairedDeviceIds.add(deviceId);
    }
    
    // Persist to user management
    if (_userAccountService != null) {
      _userAccountService!.addPairedDevice(PairedDevice(
        id: deviceId,
        name: name,
        pairedAt: DateTime.now(),
        lastKnownIp: ip,
        lastSeenAt: DateTime.now(),
      ));
    }
  }

  void denyPairing(String deviceId) {
    _pairedDeviceIds.remove(deviceId);
    _pendingDeviceIds.remove(deviceId);
    if (!_deniedDeviceIds.contains(deviceId)) {
      _deniedDeviceIds.add(deviceId);
    }
    
    // Persist to user management
    _userAccountService?.denyDevice(deviceId);
  }

  void revokePairing(String deviceId) {
    _pairedDeviceIds.remove(deviceId);
    _deniedDeviceIds.remove(deviceId);
    _pendingDeviceIds.remove(deviceId);
    
    // Persist to user management
    _userAccountService?.revokeDevice(deviceId);
  }

  void updateLibrary(List<MediaFile> library) {
    _library = List<MediaFile>.unmodifiable(library);
    _libraryById
      ..clear()
      ..addEntries(_library.map((media) => MapEntry(media.id, media)));
    _libraryJsonCache = _library.map((media) => _mediaToJson(media)).toList();
    _addLog('Library updated: ${library.length} files');
    debugPrint('[MediaServer] Library updated: ${library.length} files');
  }

  /// Get the local server URL for display
  String get url => localAddress.value;

  /// Handle incoming HTTP requests
  Future<void> _handleRequest(HttpRequest request) async {
    activeConnections.value++;

    try {
      final uri = Uri.parse(request.uri.toString());
      final path = uri.path;
      final method = request.method;
      final clientIp =
          request.connectionInfo?.remoteAddress.address ?? 'unknown';

      _addLog('$method $path (from $clientIp)');
      debugPrint('[MediaServer] $method $path');

      // CORS headers for cross-origin requests
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers
          .set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      request.response.headers.set('Access-Control-Allow-Headers',
          'Range, Content-Type, Authorization, x-lumina-token, x-lumina-device-id, x-lumina-device-name');

      if (method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      if (!_isAuthorized(request) &&
          path != '/api/health' &&
          path != '/api/discover' &&
          path != '/api/pairing/status' &&
          path != '/api/auth/login') {
        final deviceId = request.headers.value('x-lumina-device-id');
        final denied = deviceId != null && _deniedDeviceIds.contains(deviceId);
        await _sendJson(
          request,
          {'error': denied ? 'Device denied' : 'Pending approval'},
          denied ? HttpStatus.forbidden : HttpStatus.unauthorized,
        );
        return;
      }

      // Route handling
      if (path == '/api/discover') {
        await _handleDiscover(request);
      } else if (path == '/api/health') {
        await _handleHealth(request);
      } else if (path == '/api/pairing/status') {
        await _handlePairingStatus(request);
      } else if (path == '/api/auth/login') {
        await _handleAuthLogin(request);
      } else if (path == '/api/library') {
        await _handleLibrary(request);
      } else if (path == '/api/documents/ebooks') {
        await _handleDocumentList(request, 'ebook');
      } else if (path == '/api/documents/manga') {
        await _handleDocumentList(request, 'manga');
      } else if (path == '/api/documents/comics') {
        await _handleDocumentList(request, 'comic');
      } else if (path.startsWith('/api/documents/') &&
          path.endsWith('/stream')) {
        final parts = path.split('/');
        await _handleDocumentStream(request, parts[3], parts[4]);
      } else if (path.startsWith('/api/media/') && path.endsWith('/stream')) {
        final id = path.split('/')[3];
        await _handleStream(request, id);
      } else if (path.startsWith('/api/media/') && path.endsWith('/srt')) {
        final id = path.split('/')[3];
        await _handleSrt(request, id);
      } else if (path.startsWith('/api/thumbnail/')) {
        final id = path.split('/')[3];
        await _handleThumbnail(request, id);
      } else if (path.startsWith('/api/media/')) {
        final id = path.split('/')[3];
        await _handleMediaDetail(request, id);
      } else if (path == '/api/iptv/live') {
        await _handleIptvLive(request);
      } else if (path == '/api/iptv/movies') {
        await _handleIptvMovies(request);
      } else if (path == '/api/iptv/series') {
        await _handleIptvSeries(request);
      } else if (path == '/api/iptv/epg') {
        await _handleIptvEpg(request);
      } else if (path == '/api/iptv/stream') {
        await _handleIptvStream(request);
      } else if (path.startsWith('/api/iptv/stream/')) {
        final id = path.split('/').last;
        await _handleIptvStreamById(request, id);
      } else if (path == '/api/music/download' && method == 'POST') {
        await _handleMusicDownload(request);
      } else {
        await _sendJson(request, {'error': 'Not found'}, HttpStatus.notFound);
      }
    } catch (e) {
      debugPrint('[MediaServer] Request error: $e');
      try {
        await _sendJson(request, {'error': 'Internal server error'},
            HttpStatus.internalServerError);
      } catch (_) {}
    } finally {
      activeConnections.value--;
    }
  }

  Future<void> _handleDocumentList(HttpRequest request, String type) async {
    final forceRefresh = request.uri.queryParameters['refresh'] == '1';
    final items = await _scanDocuments(type, forceRefresh: forceRefresh);
    await _sendJson(request, {'items': items, 'total': items.length});
  }

  Future<void> _handleDocumentStream(
      HttpRequest request, String type, String id) async {
    final path = _documentPathFromId(id);
    if (path == null || !_documentPathIsAllowed(type, path)) {
      await _sendJson(
          request, {'error': 'Document not found'}, HttpStatus.notFound);
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      await _sendJson(
          request, {'error': 'File not found'}, HttpStatus.notFound);
      return;
    }
    request.response.headers.set('Content-Type', _documentMime(file.path));
    request.response.headers.set('Accept-Ranges', 'bytes');
    await file.openRead().pipe(request.response);
  }

  Future<List<Map<String, dynamic>>> _scanDocuments(
    String type, {
    bool forceRefresh = false,
  }) async {
    final rootPath = _documentRootPath(type);
    if (rootPath == null || rootPath.isEmpty) return [];
    final root = Directory(rootPath);
    if (!root.existsSync()) return [];

    final extensions = type == 'ebook'
        ? const ['.epub', '.pdf', '.txt', '.md', '.markdown', '.log']
        : const [
            '.cbz',
            '.cbr',
            '.pdf',
            '.jpg',
            '.jpeg',
            '.png',
            '.webp',
            '.gif'
          ];
    final files = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => extensions.any(file.path.toLowerCase().endsWith))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final items = <Map<String, dynamic>>[];
    final metadataService = EbookMangaMetadataService.instance;
    for (final file in files) {
      final id = _documentId(file.path);
      final name = file.uri.pathSegments.isNotEmpty
          ? Uri.decodeComponent(file.uri.pathSegments.last)
          : file.path.split(Platform.pathSeparator).last;
      DocumentMetadata metadata = const DocumentMetadata();
      if (type == 'comic' || type == 'ebook') {
        try {
          metadata = await metadataService.enrichFile(
            file,
            isManga: false,
            isComics: type == 'comic',
            forceRefresh: forceRefresh,
            providerToggles: _settings.documentMetadataToggles,
          );
        } catch (_) {}
      }
      items.add({
        'id': id,
        'title': metadata.title ?? name.replaceAll(RegExp(r'\.[^.]+$'), ''),
        'fileName': name,
        'path': file.path,
        'extension': name.split('.').last.toLowerCase(),
        'type': type,
        'size': file.lengthSync(),
        if (metadata.coverUrl != null) 'coverUrl': metadata.coverUrl,
        if (metadata.summary != null) 'summary': metadata.summary,
        if (metadata.localCoverPath != null)
          'localCoverPath': metadata.localCoverPath,
        if (metadata.authors.isNotEmpty) 'authors': metadata.authors,
        if (metadata.isbn != null) 'isbn': metadata.isbn,
        if (metadata.series != null) 'series': metadata.series,
        if (metadata.publisher != null) 'publisher': metadata.publisher,
        if (metadata.volume != null) 'volume': metadata.volume,
        if (metadata.chapter != null) 'issue': metadata.chapter,
        if (metadata.writers.isNotEmpty) 'writers': metadata.writers,
        if (metadata.artists.isNotEmpty) 'artists': metadata.artists,
        if (metadata.detailUrl != null) 'detailUrl': metadata.detailUrl,
        if (metadata.tags.isNotEmpty) 'tags': metadata.tags,
        if (metadata.rating != null) 'rating': metadata.rating,
      });
    }
    return items;
  }

  String _documentId(String path) =>
      base64Url.encode(utf8.encode(path)).replaceAll('=', '');

  String? _documentPathFromId(String id) {
    try {
      final padded = id.padRight(id.length + ((4 - id.length % 4) % 4), '=');
      return utf8.decode(base64Url.decode(padded));
    } catch (_) {
      return null;
    }
  }

  bool _documentPathIsAllowed(String type, String path) {
    final rootPath = _documentRootPath(type);
    if (rootPath == null || rootPath.isEmpty) return false;
    final normalizedRoot = Directory(rootPath).absolute.path.toLowerCase();
    final normalizedPath = File(path).absolute.path.toLowerCase();
    return normalizedPath == normalizedRoot ||
        normalizedPath.startsWith('$normalizedRoot${Platform.pathSeparator}');
  }

  String _documentMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.epub')) return 'application/epub+zip';
    if (lower.endsWith('.cbz')) return 'application/vnd.comicbook+zip';
    if (lower.endsWith('.cbr')) return 'application/vnd.comicbook-rar';
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.markdown')) {
      return 'text/plain; charset=utf-8';
    }
    return 'image/jpeg';
  }

  String? _documentRootPath(String type) {
    if (type == 'ebook') return _ebookPath;
    if (type == 'comic') return _comicsPath;
    return _mangaPath;
  }

  /// GET /api/discover — Returns server info for auto-detection
  Future<void> _handleDiscover(HttpRequest request) async {
    _queuePairingRequest(request);
    await _sendJson(request, {
      'status': 'ok',
      'app': 'Lumina Media Server',
      'localAddress': localAddress.value,
      'remoteAddress':
          remoteAddress.value.isNotEmpty ? remoteAddress.value : null,
      'remoteDomain': _remoteDomain.isNotEmpty ? _remoteDomain : null,
      'librarySize': _library.length,
      'activeConnections': activeConnections.value,
      'hasIptv': _iptvProvider != null && _iptvProvider!.hasLoaded,
      'requiresApproval': true,
      'pairingStatus':
          _pairingStatusFor(request.headers.value('x-lumina-device-id')),
    });
  }

  Future<void> _handlePairingStatus(HttpRequest request) async {
    final deviceId = request.headers.value('x-lumina-device-id');
    _queuePairingRequest(request);
    await _sendJson(request, {
      'status': _pairingStatusFor(deviceId),
      'app': 'Lumina Media Server',
      'localAddress': localAddress.value,
      'remoteAddress':
          remoteAddress.value.isNotEmpty ? remoteAddress.value : null,
    });
  }

  String _pairingStatusFor(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) return 'unknown';
    if (_pairedDeviceIds.contains(deviceId)) return 'approved';
    if (_deniedDeviceIds.contains(deviceId)) return 'denied';
    if (_pendingDeviceIds.contains(deviceId)) return 'pending';
    return 'unpaired';
  }

  void _queuePairingRequest(HttpRequest request) {
    final deviceId = request.headers.value('x-lumina-device-id');
    if (deviceId == null ||
        deviceId.isEmpty ||
        _pairedDeviceIds.contains(deviceId) ||
        _deniedDeviceIds.contains(deviceId) ||
        _pendingDeviceIds.contains(deviceId)) {
      return;
    }

    _pendingDeviceIds.add(deviceId);
    _pairingController.add(PairingRequest(
      deviceId: deviceId,
      deviceName:
          request.headers.value('x-lumina-device-name') ?? 'Unknown Device',
      ipAddress: request.connectionInfo?.remoteAddress.address ?? 'Unknown',
      timestamp: DateTime.now(),
    ));
  }

  /// GET /api/health
  Future<void> _handleHealth(HttpRequest request) async {
    await _sendJson(request, {
      'status': 'ok',
      'app': 'Lumina Media Server',
      'librarySize': _library.length,
      'activeConnections': activeConnections.value,
    });
  }

  /// GET /api/library
  Future<void> _handleLibrary(HttpRequest request) async {
    await _sendJson(request, {
      'media': _libraryJsonCache,
      'total': _libraryJsonCache.length,
    });
  }

  /// GET /api/media/:id
  Future<void> _handleMediaDetail(HttpRequest request, String id) async {
    final media = _libraryById[id];
    if (media == null) {
      await _sendJson(
          request, {'error': 'Media not found'}, HttpStatus.notFound);
      return;
    }
    await _sendJson(request, _mediaToJson(media));
  }

  /// GET /api/media/:id/stream — Video streaming with range support
  Future<void> _handleStream(HttpRequest request, String id) async {
    final media = _libraryById[id];
    if (media == null) {
      await _sendJson(
          request, {'error': 'Media not found'}, HttpStatus.notFound);
      return;
    }

    final file = File(media.filePath);
    if (!await file.exists()) {
      await _sendJson(
          request, {'error': 'File not found on disk'}, HttpStatus.notFound);
      return;
    }

    final fileSize = await file.length();
    final rangeHeader = request.headers.value('range');
    request.response.headers.set('Accept-Ranges', 'bytes');
    request.response.headers.set('Content-Type', _getMimeType(media.extension));

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final range = rangeHeader.substring(6).split('-');
      var start = int.tryParse(range[0]) ?? 0;
      var end = range.length > 1 && range[1].isNotEmpty
          ? int.tryParse(range[1]) ?? (fileSize - 1)
          : fileSize - 1;
      if (start < 0) start = 0;
      if (end >= fileSize) end = fileSize - 1;
      if (start > end || start >= fileSize) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set('Content-Range', 'bytes */$fileSize');
        await request.response.close();
        return;
      }

      final contentLength = end - start + 1;

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers
          .set('Content-Range', 'bytes $start-$end/$fileSize');
      request.response.headers.set('Content-Length', contentLength.toString());
      await file.openRead(start, end + 1).pipe(request.response);
    } else {
      request.response.headers.set('Content-Length', fileSize.toString());
      await file.openRead().pipe(request.response);
    }
  }

  /// GET /api/media/:id/srt — Serve SRT subtitle file
  Future<void> _handleSrt(HttpRequest request, String id) async {
    final media = _libraryById[id];
    if (media == null) {
      await _sendJson(
          request, {'error': 'Media not found'}, HttpStatus.notFound);
      return;
    }

    final srtPath = media.filePath.replaceAll(RegExp(r'\.[^.]+$'), '') + '.srt';
    final srtFile = File(srtPath);

    if (!await srtFile.exists()) {
      await _sendJson(
          request, {'error': 'No subtitles available'}, HttpStatus.notFound);
      return;
    }

    request.response.headers.set('Content-Type', 'text/plain; charset=utf-8');
    request.response.headers.set(
        'Content-Disposition', 'attachment; filename="${media.title}.srt"');
    await srtFile.openRead().pipe(request.response);
  }

  /// GET /api/thumbnail/:id — Serve thumbnail/cover art
  Future<void> _handleThumbnail(HttpRequest request, String id) async {
    final media = _libraryById[id];
    if (media == null) {
      await _sendJson(
          request, {'error': 'Media not found'}, HttpStatus.notFound);
      return;
    }

    String? imagePath = media.thumbnailPath;

    if (imagePath == null || !await File(imagePath).exists()) {
      final remoteImage =
          media.posterUrl ?? media.coverArtUrl ?? media.thumbnailUrl;
      if (remoteImage != null && remoteImage.isNotEmpty) {
        request.response.statusCode = HttpStatus.temporaryRedirect;
        request.response.headers.set('Location', remoteImage);
        await request.response.close();
        return;
      }
      await _sendJson(request, {'error': 'No thumbnail'}, HttpStatus.notFound);
      return;
    }

    final file = File(imagePath);
    final ext = imagePath.split('.').last.toLowerCase();
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

    request.response.headers.set('Content-Type', mimeType);
    await file.openRead().pipe(request.response);
  }

  // ========================
  // IPTV API Endpoints
  // ========================

  /// GET /api/iptv/live — Returns IPTV live channels
  Future<void> _handleIptvLive(HttpRequest request) async {
    final provider = _iptvProvider;
    if (provider == null || !provider.hasLoaded) {
      await _sendJson(
          request, {'error': 'IPTV not loaded', 'channels': [], 'total': 0});
      return;
    }
    final channels =
        provider.liveChannels.map((c) => _iptvMediaToJson(c)).toList();
    await _sendJson(request, {'channels': channels, 'total': channels.length});
  }

  /// GET /api/iptv/movies — Returns IPTV movies
  Future<void> _handleIptvMovies(HttpRequest request) async {
    final provider = _iptvProvider;
    if (provider == null || !provider.hasLoaded) {
      await _sendJson(
          request, {'error': 'IPTV not loaded', 'movies': [], 'total': 0});
      return;
    }
    final movies = provider.movies.map((m) => _iptvMediaToJson(m)).toList();
    await _sendJson(request, {'movies': movies, 'total': movies.length});
  }

  /// GET /api/iptv/series — Returns IPTV TV shows
  Future<void> _handleIptvSeries(HttpRequest request) async {
    final provider = _iptvProvider;
    if (provider == null || !provider.hasLoaded) {
      await _sendJson(
          request, {'error': 'IPTV not loaded', 'shows': [], 'total': 0});
      return;
    }
    final shows = provider.tvShows.map((s) => _iptvMediaToJson(s)).toList();
    await _sendJson(request, {'shows': shows, 'total': shows.length});
  }

  Future<void> _handleIptvEpg(HttpRequest request) async {
    final provider = _iptvProvider;
    if (provider == null || !provider.hasLoaded) {
      await _sendJson(request, {'entries': [], 'total': 0});
      return;
    }
    final entries = provider.epgEntries.map((e) => e.toJson()).toList();
    await _sendJson(request, {'entries': entries, 'total': entries.length});
  }

  /// GET /api/iptv/stream?url=... — Proxy stream for IPTV channel/movie
  Future<void> _handleMusicDownload(HttpRequest request) async {
    if (onMusicDownload == null) {
      await _sendJson(request, {'error': 'Music download service unavailable'},
          HttpStatus.serviceUnavailable);
      return;
    }
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final ytResult = Map<String, String>.from(data);
      
      // Trigger download in background on server
      unawaited(onMusicDownload!(ytResult));
      
      await _sendJson(request, {'status': 'Download started on server'});
    } catch (e) {
      await _sendJson(request, {'error': 'Invalid download request: $e'},
          HttpStatus.badRequest);
    }
  }

  Future<void> _handleIptvStream(HttpRequest request) async {
    final uri = Uri.parse(request.uri.toString());
    final streamUrl = uri.queryParameters['url'];
    if (streamUrl == null || streamUrl.isEmpty) {
      await _sendJson(
          request, {'error': 'Missing url parameter'}, HttpStatus.badRequest);
      return;
    }

    await _proxyIptvStream(request, streamUrl);
  }

  Future<void> _handleIptvStreamById(HttpRequest request, String id) async {
    final streamUrl = _iptvStreamUrls[id];
    if (streamUrl == null || streamUrl.isEmpty) {
      await _sendJson(
          request, {'error': 'Stream not found'}, HttpStatus.notFound);
      return;
    }
    await _proxyIptvStream(request, streamUrl);
  }

  Future<void> _proxyIptvStream(HttpRequest request, String streamUrl) async {
    // 1. Check for existing session (De-duplication)
    if (_iptvSessions.containsKey(streamUrl)) {
      _iptvSessions[streamUrl]!.addListener(request);
      return;
    }

    // 2. Check connection limit
    if (_iptvSessions.length >= _settings.iptvMaxConnections) {
      _addLog(
          'IPTV: Connection limit reached (${_settings.iptvMaxConnections})');
      await _sendJson(
          request,
          {
            'error':
                'IPTV connection limit reached. Please close other streams.'
          },
          HttpStatus.serviceUnavailable);
      return;
    }

    // 3. Start new session
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final upstreamRequest = await client.getUrl(Uri.parse(streamUrl));

      // Forward Range header if present
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstreamRequest.headers.set(HttpHeaders.rangeHeader, range);
      }

      // Use configured User-Agent
      upstreamRequest.headers
          .set(HttpHeaders.userAgentHeader, _settings.iptvUserAgent);

      final upstreamResponse = await upstreamRequest.close();

      final session =
          _IptvStreamSession(streamUrl, upstreamResponse, client, onEmpty: () {
        _iptvSessions.remove(streamUrl);
      });

      _iptvSessions[streamUrl] = session;
      session.addListener(request);
      session.start();
    } catch (e) {
      _addLog('IPTV: Proxy error: $e');
      client.close(force: true);
      if (!request.response.headers.contentType.toString().contains('json')) {
        await _sendJson(
            request,
            {'error': 'Unable to connect to IPTV provider'},
            HttpStatus.badGateway);
      }
    }
  }

  /// Convert IptvMedia to JSON for the API
  Map<String, dynamic> _iptvMediaToJson(IptvMedia media) {
    final streamId = _registerIptvStreamUrl(media.url);
    return {
      'name': media.name,
      'logo': media.logo,
      'url': '/api/iptv/stream/$streamId',
      'streamId': streamId,
      'group': media.group,
      'isLive': media.isLive,
      'isMovie': media.isMovie,
      'isSeries': media.isSeries,
      'tvgId': media.tvgId,
      'tvgName': media.tvgName,
    };
  }

  String _registerIptvStreamUrl(String url) {
    final id = sha1.convert(utf8.encode(url)).toString();
    _iptvStreamUrls[id] = url;
    return id;
  }

  /// Convert MediaFile to a JSON-safe map for the API
  Map<String, dynamic> _mediaToJson(MediaFile media) {
    return {
      'id': media.id,
      'fileName': media.fileName,
      'title': media.title,
      'extension': media.extension,
      'duration': media.duration.inMilliseconds,
      'durationFormatted': media.durationFormatted,
      'addedAt': media.addedAt.toIso8601String(),
      'isFavorite': media.isFavorite,
      'mediaKind': media.mediaKind.name,
      'contentType': media.contentType.name,
      'isVideo': media.isVideo,
      'isAudio': media.isAudio,
      'animeId': media.animeId,
      'animeTitle': media.animeTitle,
      'season': media.season,
      'episode': media.episode,
      'coverArtUrl': media.coverArtUrl,
      'posterUrl': media.posterUrl,
      'thumbnailUrl': media.thumbnailUrl,
      'description': media.description,
      'artist': media.artist,
      'album': media.album,
      'trackNumber': media.trackNumber,
      'hasSubtitles':
          File('${media.filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.srt')
              .existsSync(),
      'fileSize': File(media.filePath).existsSync()
          ? File(media.filePath).lengthSync()
          : 0,
    };
  }

  /// Send a JSON response
  Future<void> _sendJson(HttpRequest request, Map<String, dynamic> data,
      [int statusCode = HttpStatus.ok]) async {
    final json = jsonEncode(data);
    request.response.statusCode = statusCode;
    request.response.headers
        .set('Content-Type', 'application/json; charset=utf-8');
    request.response.write(json);
    await request.response.close();
  }

  bool _isAuthorized(HttpRequest request) {
    final deviceId = request.headers.value('x-lumina-device-id');

    // If device is already paired, it's authorized
    if (deviceId != null && _pairedDeviceIds.contains(deviceId)) {
      return true;
    }

    if (deviceId != null && _deniedDeviceIds.contains(deviceId)) {
      return false;
    }

    // Token-based auth (backward compatibility or manual override)
    final header = request.headers.value('x-lumina-token');
    final bearer = request.headers.value(HttpHeaders.authorizationHeader);
    final queryToken = request.uri.queryParameters['token'];
    final bearerToken = bearer != null && bearer.startsWith('Bearer ')
        ? bearer.substring(7).trim()
        : null;
    final token = header ?? queryToken ?? bearerToken;

    if (_authToken.isNotEmpty && token == _authToken) {
      return true;
    }

    // If not paired and not using a valid token, it's unauthorized
    // BUT we trigger a pairing request if a deviceId is present
    _queuePairingRequest(request);

    return false ||
        (_userAccountService?.validateSession(header ?? '') ?? false) ||
        (_userAccountService?.validateSession(queryToken ?? '') ?? false) ||
        (_userAccountService?.validateSession(bearerToken ?? '') ?? false);
  }

  Future<void> _handleAuthLogin(HttpRequest request) async {
    if (request.method != 'POST') {
      _sendJson(request, {'error': 'Method not allowed'},
          HttpStatus.methodNotAllowed);
      return;
    }
    final service = _userAccountService;
    if (service == null) {
      _sendJson(request, {'error': 'User accounts unavailable'},
          HttpStatus.serviceUnavailable);
      return;
    }

    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final username = data['username'] as String? ?? '';
      final password = data['password'] as String? ?? '';
      final result = await service.authenticate(username, password);
      if (result == null) {
        _sendJson(request, {'error': 'Invalid username or password'},
            HttpStatus.unauthorized);
        return;
      }
      _sendJson(request, result);
    } catch (e) {
      _sendJson(
          request, {'error': 'Invalid login request'}, HttpStatus.badRequest);
    }
  }

  /// Get MIME type from file extension
  String _getMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'mp4':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'm4a':
        return 'audio/m4a';
      default:
        return 'application/octet-stream';
    }
  }

  void _addLog(String message) {
    final timestamp =
        DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    final logLine = '[$timestamp] $message';
    final currentLogs = List<String>.from(logs.value);
    currentLogs.add(logLine);
    // Keep only last 50 logs
    if (currentLogs.length > 50) currentLogs.removeAt(0);
    logs.value = currentLogs;
  }
}

/// Manages a single upstream IPTV stream and broadcasts it to multiple clients.
class _IptvStreamSession {
  final String url;
  final HttpClientResponse upstream;
  final HttpClient client;
  final VoidCallback onEmpty;
  final List<HttpRequest> _listeners = [];
  StreamSubscription<List<int>>? _subscription;
  bool _isClosed = false;

  _IptvStreamSession(this.url, this.upstream, this.client,
      {required this.onEmpty});

  void addListener(HttpRequest request) {
    if (_isClosed) return;

    final response = request.response;
    _listeners.add(request);

    // Set headers
    response.statusCode = upstream.statusCode;
    upstream.headers.forEach((name, values) {
      if (name.toLowerCase() == 'transfer-encoding') return;
      if (values.isNotEmpty) {
        response.headers.set(name, values);
      }
    });
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Cache-Control', 'no-cache');

    // Monitor client disconnect (Graceful Teardown)
    unawaited(response.done.then((_) {
      removeListener(request);
    }).catchError((_) {
      removeListener(request);
    }));
  }

  void start() {
    _subscription = upstream.listen(
      (data) {
        for (final request in List.from(_listeners)) {
          try {
            request.response.add(data);
          } catch (_) {
            removeListener(request);
          }
        }
      },
      onDone: () => _close('Upstream closed'),
      onError: (e) => _close('Upstream error: $e'),
      cancelOnError: true,
    );
  }

  void removeListener(HttpRequest request) {
    _listeners.remove(request);
    if (_listeners.isEmpty) {
      _close('No more listeners');
    }
  }

  void _close(String reason) {
    if (_isClosed) return;
    _isClosed = true;

    debugPrint('[IptvSession] Closing stream ($reason): $url');

    _subscription?.cancel();
    for (final request in _listeners) {
      try {
        request.response.close();
      } catch (_) {}
    }
    _listeners.clear();
    client.close(force: true);
    onEmpty();
  }
}

class PairingRequest {
  final String deviceId;
  final String deviceName;
  final String ipAddress;
  final DateTime timestamp;

  PairingRequest({
    required this.deviceId,
    required this.deviceName,
    required this.ipAddress,
    required this.timestamp,
  });
}
