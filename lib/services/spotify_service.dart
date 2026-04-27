import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'cache_service.dart';

class SpotifyService {
  static const String _envClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
  static const String _envClientSecret = String.fromEnvironment('SPOTIFY_CLIENT_SECRET');
  final CacheService _cache = CacheService.instance;
  String? _accessToken;
  DateTime? _expiry;

  String? _manualClientId;
  String? _manualClientSecret;

  String get clientId => _manualClientId ?? (_envClientId.isNotEmpty
      ? _envClientId
      : (Platform.environment['SPOTIFY_CLIENT_ID'] ?? ''));
  String get clientSecret => _manualClientSecret ?? (_envClientSecret.isNotEmpty
      ? _envClientSecret
      : (Platform.environment['SPOTIFY_CLIENT_SECRET'] ?? ''));

  void setCredentials(String id, String secret) {
    _manualClientId = id;
    _manualClientSecret = secret;
    _accessToken = null; // Reset token on credential change
  }

  Future<String?> getAccessToken() async {
    if (_accessToken != null && _expiry != null && DateTime.now().isBefore(_expiry!)) {
      return _accessToken;
    }
    if (clientId.isEmpty || clientSecret.isEmpty) {
      debugPrint('Spotify: Client ID or Secret is empty. ID: "${clientId.isNotEmpty ? "***" : "empty"}", Secret: "${clientSecret.isNotEmpty ? "***" : "empty"}"');
      return null;
    }

    debugPrint('Spotify: Requesting access token with client credentials');

    try {
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic ' + base64Encode(utf8.encode('$clientId:$clientSecret')),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'grant_type': 'client_credentials'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _expiry = DateTime.now().add(Duration(seconds: data['expires_in']));
        debugPrint('Spotify: Successfully got access token');
        return _accessToken;
      } else {
        debugPrint('Spotify: Failed to get access token - ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Spotify: Error getting access token: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> searchTrack(String query) async {
    final cacheKey = 'track:$query';
    final cached = await _cache.readJson<Map<String, dynamic>>('api', cacheKey);
    if (cached != null) return cached;
    final token = await getAccessToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=track&limit=1'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tracks = data['tracks']['items'] as List;
        if (tracks.isNotEmpty) {
          final result = tracks.first as Map<String, dynamic>;
          await _cache.writeJson('api', cacheKey, result);
          return result;
        }
      }
    } catch (e) {
      print('Spotify Search Error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getTrackMetadata(String filename) async {
    // Clean filename for search (remove extension and common noise)
    String cleanName = filename.split('.').first;
    cleanName = cleanName.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    
    return await searchTrack(cleanName);
  }

  Future<List<Map<String, dynamic>>> getArtistAlbums(String artistName) async {
    final cacheKey = 'albums:$artistName';
    final cached = await _cache.readJson<List<dynamic>>('api', cacheKey);
    if (cached != null) {
      return cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final token = await getAccessToken();
    if (token == null) return [];

    final url = 'https://api.spotify.com/v1/search?q=artist:${Uri.encodeComponent(artistName)}&type=album&limit=20';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> items = data['albums']['items'];
        final results = items.map((item) => {
          'id': item['id'],
          'name': item['name'],
          'imageUrl': (item['images'] as List).isNotEmpty ? item['images'][0]['url'] : null,
          'releaseDate': item['release_date'],
        }).toList();
        await _cache.writeJson('api', cacheKey, results);
        return results;
      }
    } catch (e) {
      print('Error fetching artist albums: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getAlbumTracks(String albumId) async {
    final cacheKey = 'tracks:$albumId';
    final cached = await _cache.readJson<List<dynamic>>('api', cacheKey);
    if (cached != null) {
      return cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final token = await getAccessToken();
    if (token == null) return [];

    final url = 'https://api.spotify.com/v1/albums/$albumId/tracks?limit=100';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> items = data['items'];
        final results = items.map((item) => {
          'id': item['id'],
          'name': item['name'],
          'trackNumber': item['track_number'],
          'durationMs': item['duration_ms'],
        }).toList();
        await _cache.writeJson('api', cacheKey, results);
        return results;
      }
    } catch (e) {
      print('Error fetching album tracks: $e');
    }
    return [];
  }

  // Genre tags that indicate non-American music
  static const _nonAmericanGenrePatterns = [
    'k-pop', 'j-pop', 'j-rock', 'j-idol', 'anime',
    'bollywood', 'filmi', 'desi', 'hindi',
    'latin pop', 'reggaeton', 'cumbia', 'salsa', 'latin trap',
    'afrobeats', 'afropop', 'afro',
    'mandopop', 'c-pop', 'cantopop', 'cpop',
    'thai pop', 'viet pop', 'korean',
    'flamenco', 'samba', 'bossa nova',
  ];

  Future<List<Map<String, dynamic>>> getDiscoveryArtists() async {
    const cacheKey = 'discovery-artists-us-v2';
    final cached = await _cache.readJson<List<dynamic>>('api', cacheKey);
    if (cached != null) {
      return cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final token = await getAccessToken();
    if (token == null) return [];

    // Query several distinctly American genres
    final genreQueries = [
      ('hip-hop', 15),
      ('r-n-b', 12),
      ('country', 10),
      ('rock', 10),
      ('pop', 10),
    ];

    final seen = <String>{};
    final artists = <Map<String, dynamic>>[];

    for (final (genre, limit) in genreQueries) {
      try {
        final url =
            'https://api.spotify.com/v1/search?q=genre:$genre&type=artist&market=US&limit=$limit';
        final response = await http.get(Uri.parse(url), headers: {
          'Authorization': 'Bearer $token',
        });
        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body);
        final items = data['artists']['items'] as List;

        for (final item in items) {
          final id = item['id'] as String;
          if (seen.contains(id)) continue;

          final genres = List<String>.from(item['genres'] as List? ?? []);
          final genresLower = genres.map((g) => g.toLowerCase()).toList();

          // Skip artists whose genre tags suggest non-American origin
          final isNonAmerican = _nonAmericanGenrePatterns
              .any((pattern) => genresLower.any((g) => g.contains(pattern)));
          if (isNonAmerican) continue;

          seen.add(id);
          artists.add({
            'id': id,
            'name': item['name'],
            'imageUrl': (item['images'] as List).isNotEmpty
                ? item['images'][0]['url']
                : null,
            'genres': genres,
            'popularity': item['popularity'] ?? 0,
          });
        }
      } catch (e) {
        print('Error fetching discovery artists for genre $genre: $e');
      }
    }

    // Sort by popularity so the best-known names appear first
    artists.sort((a, b) =>
        (b['popularity'] as int).compareTo(a['popularity'] as int));

    final results = artists.take(40).toList();
    if (results.isNotEmpty) {
      await _cache.writeJson('api', cacheKey, results);
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getDiscoveryAlbums() async {
    const cacheKey = 'discovery-albums';
    final cached = await _cache.readJson<List<dynamic>>('api', cacheKey);
    if (cached != null) {
      return cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final token = await getAccessToken();
    if (token == null) return [];

    const url = 'https://api.spotify.com/v1/browse/new-releases?limit=20';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> items = data['albums']['items'];
        final results = items.map((item) => {
          'id': item['id'],
          'name': item['name'],
          'imageUrl': (item['images'] as List).isNotEmpty ? item['images'][0]['url'] : null,
          'artist': item['artists'][0]['name'],
          'releaseDate': item['release_date'],
        }).toList();
        await _cache.writeJson('api', cacheKey, results);
        return results;
      }
    } catch (e) {
      print('Error fetching discovery albums: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getSearchSuggestions(String query) async {
    final cacheKey = 'suggestions:$query';
    final cached = await _cache.readJson<List<dynamic>>('api', cacheKey);
    if (cached != null) {
      return cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final token = await getAccessToken();
    if (token == null) return [];

    final url = 'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=artist,track&limit=10';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> artists = data['artists']['items'];
        final List<dynamic> tracks = data['tracks']['items'];
        
        final suggestions = <Map<String, dynamic>>[];
        
        for (var item in artists) {
          suggestions.add({
            'name': item['name'],
            'type': 'Artist',
            'imageUrl': (item['images'] as List).isNotEmpty ? item['images'][0]['url'] : null,
          });
        }
        
        for (var item in tracks) {
          suggestions.add({
            'name': item['name'],
            'artist': item['artists'][0]['name'],
            'type': 'Track',
            'imageUrl': (item['album']['images'] as List).isNotEmpty ? item['album']['images'][0]['url'] : null,
          });
        }
        
        await _cache.writeJson('api', cacheKey, suggestions);
        return suggestions;
      }
    } catch (e) {
      print('Error fetching suggestions: $e');
    }
    return [];
  }
}
