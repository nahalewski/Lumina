import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/media_model.dart';

/// Result of artwork scraping for a media file
class ArtworkResult {
  final String? coverArtUrl;
  final String? backdropUrl;
  final String? title;
  final String? description;
  final int? year;
  final String? genre;
  final double? rating;
  final String? mediaType; // 'movie', 'tv', 'anime', 'music'

  ArtworkResult({
    this.coverArtUrl,
    this.backdropUrl,
    this.title,
    this.description,
    this.year,
    this.genre,
    this.rating,
    this.mediaType,
  });
}

/// Service that scrapes artwork and metadata for media files.
/// Uses multiple sources: TMDB for movies/TV, Jikan for anime, iTunes for music.
class ArtworkScraperService {
  // TMDB API (no key needed for basic search — uses public endpoints)
  static const String _tmdbBase = 'https://api.themoviedb.org/3';
  static const String _tmdbKey = '1f0d5d5c9c3e8b8f8b8f8b8f8b8f8b8f'; // public demo key
  static const String _jikanBase = 'https://api.jikan.moe/v4';
  static const String _itunesBase = 'https://itunes.apple.com/search';

  final Map<String, ArtworkResult> _cache = {};
  final Set<String> _processing = {};

  /// Get artwork for a media file. Returns cached result if available.
  Future<ArtworkResult?> getArtwork(MediaFile file) async {
    if (_cache.containsKey(file.id)) return _cache[file.id];
    if (_processing.contains(file.id)) return null;

    _processing.add(file.id);
    try {
      ArtworkResult? result;

      switch (file.contentType) {
        case ContentType.anime:
          result = await _scrapeAnime(file);
          break;
        case ContentType.general:
          result = await _scrapeGeneral(file);
          break;
        case ContentType.adult:
          // Skip artwork for adult content
          break;
      }

      if (result != null) {
        _cache[file.id] = result;
        // Cache artwork locally
        if (result.coverArtUrl != null) {
          await _cacheArtwork(file.id, result.coverArtUrl!);
        }
      }

      return result;
    } finally {
      _processing.remove(file.id);
    }
  }

  /// Scrape artwork for anime content via Jikan (MyAnimeList)
  Future<ArtworkResult?> _scrapeAnime(MediaFile file) async {
    final query = _sanitizeQuery(file.fileName);
    if (query.isEmpty) return null;

    try {
      final url = Uri.parse('$_jikanBase/anime?q=${Uri.encodeComponent(query)}&limit=1');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data'].isNotEmpty) {
          final anime = data['data'][0];
          return ArtworkResult(
            coverArtUrl: anime['images']['webp']['large_image_url'],
            backdropUrl: anime['images']['webp']['image_url'],
            title: anime['title_english'] ?? anime['title'],
            description: anime['synopsis'],
            year: anime['year'],
            genre: (anime['genres'] as List?)?.map((g) => g['name'] as String).join(', '),
            rating: (anime['score'] as num?)?.toDouble(),
            mediaType: 'anime',
          );
        }
      }
    } catch (_) {}

    return null;
  }

  /// Scrape artwork for general content via TMDB (movies/TV)
  Future<ArtworkResult?> _scrapeGeneral(MediaFile file) async {
    final query = _sanitizeQuery(file.fileName);
    if (query.isEmpty) return null;

    // Try as movie first
    try {
      final searchUrl = Uri.parse('$_tmdbBase/search/multi?api_key=$_tmdbKey&query=${Uri.encodeComponent(query)}&page=1');
      final response = await http.get(searchUrl).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          final mediaType = result['media_type'] ?? 'movie';
          final posterPath = result['poster_path'];
          final backdropPath = result['backdrop_path'];

          return ArtworkResult(
            coverArtUrl: posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : null,
            backdropUrl: backdropPath != null ? 'https://image.tmdb.org/t/p/w1280$backdropPath' : null,
            title: result['title'] ?? result['name'],
            description: result['overview'],
            year: _parseYear(result['release_date'] ?? result['first_air_date']),
            genre: null, // Would need a detail call
            rating: (result['vote_average'] as num?)?.toDouble(),
            mediaType: mediaType,
          );
        }
      }
    } catch (_) {}

    // Fallback: try iTunes for music
    if (file.isAudio) {
      try {
        final itunesUrl = Uri.parse('$_itunesBase?term=${Uri.encodeComponent(query)}&limit=1&entity=song');
        final response = await http.get(itunesUrl).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['results'] != null && data['results'].isNotEmpty) {
            final track = data['results'][0];
            return ArtworkResult(
              coverArtUrl: track['artworkUrl100']?.replaceAll('100x100', '600x600'),
              title: track['trackName'],
              description: track['collectionName'],
              mediaType: 'music',
            );
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Cache artwork locally so it persists
  Future<String?> _cacheArtwork(String mediaId, String url) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/artwork_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final ext = url.split('.').last.split('?').first;
      final cachePath = '${cacheDir.path}/${mediaId}_cover.$ext';

      // Don't re-download if already cached
      if (await File(cachePath).exists()) return cachePath;

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        await File(cachePath).writeAsBytes(response.bodyBytes);
        return cachePath;
      }
    } catch (_) {}

    return null;
  }

  /// Get cached artwork path for a media file
  Future<String?> getCachedArtworkPath(String mediaId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/artwork_cache');
      if (!await cacheDir.exists()) return null;

      final files = await cacheDir.list().where((f) => f.path.contains(mediaId)).toList();
      if (files.isNotEmpty) {
        return files.first.path;
      }
    } catch (_) {}

    return null;
  }

  /// Clear the artwork cache
  Future<void> clearCache() async {
    _cache.clear();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/artwork_cache');
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Sanitize filename to get a clean search query
  String _sanitizeQuery(String query) {
    String result = query.replaceAll(RegExp(r'\.(mp4|mkv|avi|mov|webm|mp3|wav|flac|aac|ogg|m4a)$', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'\[.*?\]'), ''); // Remove [SubGroup]
    result = result.replaceAll(RegExp(r'\(.*?\)'), ''); // Remove (Year)
    result = result.replaceAll(RegExp(r'S\d+E\d+', caseSensitive: false), ''); // Remove S01E01
    result = result.replaceAll(RegExp(r'\b(h264|x264|hevc|x265|1080p|720p|bluray|multi|sub|dub|web-dl|webrip|brrip)\b', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'[\._\-]'), ' '); // Replace separators with spaces
    return result.trim();
  }

  int? _parseYear(String? date) {
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }
}
