import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

class RemoteMediaFile {
  final String id;
  final String title;
  final String fileName;
  final String extension;
  final Duration duration;
  final String? coverArtUrl;
  final bool isVideo;
  final bool isAudio;
  final String? artist;
  final String? album;
  final int? trackNumber;

  RemoteMediaFile({
    required this.id,
    required this.title,
    required this.fileName,
    required this.extension,
    required this.duration,
    this.coverArtUrl,
    required this.isVideo,
    required this.isAudio,
    this.artist,
    this.album,
    this.trackNumber,
  });

  factory RemoteMediaFile.fromJson(Map<String, dynamic> json) {
    return RemoteMediaFile(
      id: json['id'] as String,
      title: json['title'] as String,
      fileName: json['fileName'] as String,
      extension: json['extension'] as String,
      duration: Duration(milliseconds: json['duration'] as int),
      coverArtUrl: json['coverArtUrl'] as String?,
      isVideo: json['isVideo'] as bool,
      isAudio: json['isAudio'] as bool,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      trackNumber: json['trackNumber'] as int?,
    );
  }
}

class RemoteMediaProvider extends ChangeNotifier {
  List<RemoteMediaFile> _media = [];
  bool _isLoading = false;
  String? _baseUrl;
  VideoPlayerController? _controller;
  RemoteMediaFile? _currentMedia;

  List<RemoteMediaFile> get media => _media;
  bool get isLoading => _isLoading;
  RemoteMediaFile? get currentMedia => _currentMedia;
  VideoPlayerController? get controller => _controller;

  /// The URLs to try for connection
  final List<String> _possibleUrls = [
    'http://localhost:8080',      // Localhost (if server is on same device)
    'http://192.168.0.148:8080',  // Your Mac's Local IP
    'https://lumina.orosapp.us',  // Remote URL provided by user
  ];

  Future<void> connectAndFetch() async {
    _isLoading = true;
    _baseUrl = null; // Reset
    notifyListeners();

    // Try to find a working base URL
    for (final url in _possibleUrls) {
      debugPrint('Trying connection to: $url');
      try {
        final response = await http.get(Uri.parse('$url/api/health')).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          _baseUrl = url;
          debugPrint('Connected successfully to: $_baseUrl');
          break;
        }
      } catch (e) {
        debugPrint('Failed to connect to $url: $e');
      }
    }

    if (_baseUrl != null) {
      await fetchLibrary();
    } else {
      debugPrint('No Lumina Media Server found at any tried location');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchLibrary() async {
    if (_baseUrl == null) return;

    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/library'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> mediaJson = data['media'];
        _media = mediaJson.map((j) => RemoteMediaFile.fromJson(j)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching library: $e');
    }
  }

  Future<void> playMedia(RemoteMediaFile media) async {
    if (_baseUrl == null) return;

    _currentMedia = media;
    notifyListeners();

    if (_controller != null) {
      await _controller!.dispose();
    }

    final streamUrl = '$_baseUrl/api/media/${media.id}/stream';
    _controller = VideoPlayerController.networkUrl(Uri.parse(streamUrl));

    try {
      await _controller!.initialize();
      await _controller!.play();
    } catch (e) {
      debugPrint('Error playing media: $e');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
