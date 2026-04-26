import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/media_model.dart';
import '../providers/iptv_provider.dart';
import 'iptv_service.dart';

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
  List<MediaFile> _library = [];
  int _port = 8080;
  String _remoteDomain = '';
  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  final ValueNotifier<String> localAddress = ValueNotifier('');
  final ValueNotifier<String> remoteAddress = ValueNotifier('');
  final ValueNotifier<int> activeConnections = ValueNotifier(0);
  final ValueNotifier<String?> lastError = ValueNotifier(null);
  final ValueNotifier<List<String>> logs = ValueNotifier([]);

  /// Reference to the IPTV provider for serving IPTV data via API
  IptvProvider? _iptvProvider;

  /// Set the IPTV provider reference so the server can serve IPTV data
  void setIptvProvider(IptvProvider provider) {
    _iptvProvider = provider;
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
      
      _server!.listen(_handleRequest, onError: (e) {
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
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    isRunning.value = false;
    activeConnections.value = 0;
    _addLog('Server stopped');
    debugPrint('[MediaServer] Stopped');
  }

  /// Update the library being served
  void updateLibrary(List<MediaFile> library) {
    _library = library;
    _addLog('Library updated: ${library.length} files');
    debugPrint('[MediaServer] Library updated: ${library.length} files');
  }

  /// Get the local server URL for display
  String get url => localAddress.value;

  /// Handle incoming HTTP requests
  void _handleRequest(HttpRequest request) {
    activeConnections.value++;
    
    try {
      final uri = Uri.parse(request.uri.toString());
      final path = uri.path;
      final method = request.method;
      final clientIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';
      
      _addLog('$method $path (from $clientIp)');
      debugPrint('[MediaServer] $method $path');

      // CORS headers for cross-origin requests
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
      request.response.headers.set('Access-Control-Allow-Headers', 'Range, Content-Type');

      if (method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        request.response.close();
        activeConnections.value--;
        return;
      }

      // Route handling
      if (path == '/api/discover') {
        _handleDiscover(request);
      } else if (path == '/api/health') {
        _handleHealth(request);
      } else if (path == '/api/library') {
        _handleLibrary(request);
      } else if (path.startsWith('/api/media/') && path.endsWith('/stream')) {
        final id = path.split('/')[3];
        _handleStream(request, id);
      } else if (path.startsWith('/api/media/') && path.endsWith('/srt')) {
        final id = path.split('/')[3];
        _handleSrt(request, id);
      } else if (path.startsWith('/api/thumbnail/')) {
        final id = path.split('/')[3];
        _handleThumbnail(request, id);
      } else if (path.startsWith('/api/media/')) {
        final id = path.split('/')[3];
        _handleMediaDetail(request, id);
      } else if (path == '/api/iptv/live') {
        _handleIptvLive(request);
      } else if (path == '/api/iptv/movies') {
        _handleIptvMovies(request);
      } else if (path == '/api/iptv/series') {
        _handleIptvSeries(request);
      } else if (path == '/api/iptv/stream') {
        _handleIptvStream(request);
      } else {
        _sendJson(request, {'error': 'Not found'}, HttpStatus.notFound);
      }
    } catch (e) {
      debugPrint('[MediaServer] Request error: $e');
      try {
        _sendJson(request, {'error': 'Internal server error'}, HttpStatus.internalServerError);
      } catch (_) {}
    } finally {
      activeConnections.value--;
    }
  }

  /// GET /api/discover — Returns server info for auto-detection
  void _handleDiscover(HttpRequest request) {
    _sendJson(request, {
      'status': 'ok',
      'app': 'Lumina Media Server',
      'localAddress': localAddress.value,
      'remoteAddress': remoteAddress.value.isNotEmpty ? remoteAddress.value : null,
      'remoteDomain': _remoteDomain.isNotEmpty ? _remoteDomain : null,
      'librarySize': _library.length,
      'activeConnections': activeConnections.value,
      'hasIptv': _iptvProvider != null && _iptvProvider!.hasLoaded,
    });
  }

  /// GET /api/health
  void _handleHealth(HttpRequest request) {
    _sendJson(request, {
      'status': 'ok',
      'app': 'Lumina Media Server',
      'librarySize': _library.length,
      'activeConnections': activeConnections.value,
    });
  }

  /// GET /api/library
  void _handleLibrary(HttpRequest request) {
    final mediaList = _library.map((m) => _mediaToJson(m)).toList();
    _sendJson(request, {
      'media': mediaList,
      'total': mediaList.length,
    });
  }

  /// GET /api/media/:id
  void _handleMediaDetail(HttpRequest request, String id) {
    final media = _library.where((m) => m.id == id).firstOrNull;
    if (media == null) {
      _sendJson(request, {'error': 'Media not found'}, HttpStatus.notFound);
      return;
    }
    _sendJson(request, _mediaToJson(media));
  }

  /// GET /api/media/:id/stream — Video streaming with range support
  void _handleStream(HttpRequest request, String id) {
    final media = _library.where((m) => m.id == id).firstOrNull;
    if (media == null) {
      _sendJson(request, {'error': 'Media not found'}, HttpStatus.notFound);
      return;
    }

    final file = File(media.filePath);
    if (!file.existsSync()) {
      _sendJson(request, {'error': 'File not found on disk'}, HttpStatus.notFound);
      return;
    }

    final fileSize = file.lengthSync();
    final rangeHeader = request.headers.value('range');
    
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      // Parse range request
      final range = rangeHeader.substring(6).split('-');
      final start = int.tryParse(range[0]) ?? 0;
      final end = range.length > 1 && range[1].isNotEmpty 
          ? int.tryParse(range[1]) ?? (fileSize - 1) 
          : fileSize - 1;
      
      final contentLength = end - start + 1;
      
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set('Content-Range', 'bytes $start-$end/$fileSize');
      request.response.headers.set('Content-Length', contentLength.toString());
      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.headers.set('Content-Type', _getMimeType(media.extension));
      
      // Stream the requested range using a controller
      final randomAccessFile = file.openSync();
      randomAccessFile.setPositionSync(start);
      
      const chunkSize = 65536; // 64KB chunks
      int bytesRemaining = contentLength;
      
      final controller = StreamController<List<int>>();
      
      // Read chunks synchronously
      Future<void> readChunks() async {
        try {
          while (bytesRemaining > 0) {
            final toRead = bytesRemaining < chunkSize ? bytesRemaining : chunkSize;
            bytesRemaining -= toRead;
            final chunk = randomAccessFile.readSync(toRead);
            if (chunk.isNotEmpty) {
              controller.add(chunk);
            } else {
              break;
            }
          }
        } catch (_) {
          // ignore read errors
        } finally {
          randomAccessFile.closeSync();
          await controller.close();
        }
      }

      // Start reading in the next event loop iteration
      readChunks();
      
      request.response.addStream(controller.stream).then((_) {
        request.response.close();
      }).catchError((_) {});

    } else {
      // Full file stream
      request.response.headers.set('Content-Length', fileSize.toString());
      request.response.headers.set('Content-Type', _getMimeType(media.extension));
      request.response.headers.set('Accept-Ranges', 'bytes');
      file.openRead().pipe(request.response).catchError((_) {});
    }
  }

  /// GET /api/media/:id/srt — Serve SRT subtitle file
  void _handleSrt(HttpRequest request, String id) {
    final media = _library.where((m) => m.id == id).firstOrNull;
    if (media == null) {
      _sendJson(request, {'error': 'Media not found'}, HttpStatus.notFound);
      return;
    }

    final srtPath = media.filePath.replaceAll(RegExp(r'\.[^.]+$'), '') + '.srt';
    final srtFile = File(srtPath);
    
    if (!srtFile.existsSync()) {
      _sendJson(request, {'error': 'No subtitles available'}, HttpStatus.notFound);
      return;
    }

    request.response.headers.set('Content-Type', 'text/plain; charset=utf-8');
    request.response.headers.set('Content-Disposition', 'attachment; filename="${media.title}.srt"');
    srtFile.openRead().pipe(request.response).catchError((_) {});
  }

  /// GET /api/thumbnail/:id — Serve thumbnail/cover art
  void _handleThumbnail(HttpRequest request, String id) {
    final media = _library.where((m) => m.id == id).firstOrNull;
    if (media == null) {
      _sendJson(request, {'error': 'Media not found'}, HttpStatus.notFound);
      return;
    }

    String? imagePath = media.thumbnailPath;
    
    if (imagePath == null || !File(imagePath).existsSync()) {
      _sendJson(request, {'error': 'No thumbnail'}, HttpStatus.notFound);
      return;
    }

    final file = File(imagePath);
    final ext = imagePath.split('.').last.toLowerCase();
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
    
    request.response.headers.set('Content-Type', mimeType);
    file.openRead().pipe(request.response).catchError((_) {});
  }

  // ========================
  // IPTV API Endpoints
  // ========================

  /// GET /api/iptv/live — Returns IPTV live channels
  void _handleIptvLive(HttpRequest request) {
    final provider = _iptvProvider;
    if (provider == null || !provider.hasLoaded) {
      _sendJson(request, {'error': 'IPTV not loaded', 'channels': [], 'total': 0});
      return;
    }
    final channels = provider.liveChannels.map((c) => _iptvMediaToJson(c)).toList();
    _sendJson(request, {'channels': channels, 'total': channels.length});
  }

  /// GET /api/iptv/movies — Returns IPTV movies
  void _handleIptvMovies(HttpRequest request) {
    final provider = _iptvProvider;
    if (provider == null || !provider.hasLoaded) {
      _sendJson(request, {'error': 'IPTV not loaded', 'movies': [], 'total': 0});
      return;
    }
    final movies = provider.movies.map((m) => _iptvMediaToJson(m)).toList();
    _sendJson(request, {'movies': movies, 'total': movies.length});
  }

  /// GET /api/iptv/series — Returns IPTV TV shows
  void _handleIptvSeries(HttpRequest request) {
    final provider = _iptvProvider;
    if (provider == null || !provider.hasLoaded) {
      _sendJson(request, {'error': 'IPTV not loaded', 'shows': [], 'total': 0});
      return;
    }
    final shows = provider.tvShows.map((s) => _iptvMediaToJson(s)).toList();
    _sendJson(request, {'shows': shows, 'total': shows.length});
  }

  /// GET /api/iptv/stream?url=... — Proxy stream for IPTV channel/movie
  void _handleIptvStream(HttpRequest request) {
    final uri = Uri.parse(request.uri.toString());
    final streamUrl = uri.queryParameters['url'];
    if (streamUrl == null || streamUrl.isEmpty) {
      _sendJson(request, {'error': 'Missing url parameter'}, HttpStatus.badRequest);
      return;
    }

    // Redirect the client to the actual IPTV stream URL
    // The Android app will play it directly
    request.response.statusCode = HttpStatus.temporaryRedirect;
    request.response.headers.set('Location', streamUrl);
    request.response.close();
  }

  /// Convert IptvMedia to JSON for the API
  Map<String, dynamic> _iptvMediaToJson(IptvMedia media) {
    return {
      'name': media.name,
      'logo': media.logo,
      'url': media.url,
      'group': media.group,
      'isLive': media.isLive,
      'tvgId': media.tvgId,
      'tvgName': media.tvgName,
    };
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
      'contentType': media.contentType.name,
      'isVideo': media.isVideo,
      'isAudio': media.isAudio,
      'animeId': media.animeId,
      'animeTitle': media.animeTitle,
      'season': media.season,
      'episode': media.episode,
      'coverArtUrl': media.coverArtUrl,
      'description': media.description,
      'artist': media.artist,
      'album': media.album,
      'trackNumber': media.trackNumber,
      'hasSubtitles': File('${media.filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.srt').existsSync(),
      'fileSize': File(media.filePath).existsSync() ? File(media.filePath).lengthSync() : 0,
    };
  }

  /// Send a JSON response
  void _sendJson(HttpRequest request, Map<String, dynamic> data, [int statusCode = HttpStatus.ok]) {
    final json = jsonEncode(data);
    request.response.statusCode = statusCode;
    request.response.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.response.write(json);
    request.response.close();
  }

  /// Get MIME type from file extension
  String _getMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'mp4': return 'video/mp4';
      case 'mkv': return 'video/x-matroska';
      case 'mov': return 'video/quicktime';
      case 'avi': return 'video/x-msvideo';
      case 'webm': return 'video/webm';
      case 'mp3': return 'audio/mpeg';
      case 'wav': return 'audio/wav';
      case 'flac': return 'audio/flac';
      case 'aac': return 'audio/aac';
      case 'ogg': return 'audio/ogg';
      case 'm4a': return 'audio/m4a';
      default: return 'application/octet-stream';
    }
  }
  
  void _addLog(String message) {
    final timestamp = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    final logLine = '[$timestamp] $message';
    final currentLogs = List<String>.from(logs.value);
    currentLogs.add(logLine);
    // Keep only last 50 logs
    if (currentLogs.length > 50) currentLogs.removeAt(0);
    logs.value = currentLogs;
  }
}
