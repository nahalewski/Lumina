import 'dart:convert';
import 'package:http/http.dart' as http;

class SpotifyService {
  final String clientId = '5716097d7155459398ff3b40641fd6bc';
  final String clientSecret = '1cb02539c28f469d95fbae163a0299a3';
  String? _accessToken;
  DateTime? _expiry;

  Future<String?> getAccessToken() async {
    if (_accessToken != null && _expiry != null && DateTime.now().isBefore(_expiry!)) {
      return _accessToken;
    }

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
        return _accessToken;
      }
    } catch (e) {
      print('Spotify Auth Error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> searchTrack(String query) async {
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
          return tracks.first;
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
        return items.map((item) => {
          'id': item['id'],
          'name': item['name'],
          'imageUrl': (item['images'] as List).isNotEmpty ? item['images'][0]['url'] : null,
          'releaseDate': item['release_date'],
        }).toList();
      }
    } catch (e) {
      print('Error fetching artist albums: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getAlbumTracks(String albumId) async {
    final token = await getAccessToken();
    if (token == null) return [];

    final url = 'https://api.spotify.com/v1/albums/$albumId/tracks?limit=50';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> items = data['items'];
        return items.map((item) => {
          'id': item['id'],
          'name': item['name'],
          'trackNumber': item['track_number'],
          'durationMs': item['duration_ms'],
        }).toList();
      }
    } catch (e) {
      print('Error fetching album tracks: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getDiscoveryArtists() async {
    final token = await getAccessToken();
    if (token == null) return [];

    // Search for popular artists to fill the page
    final url = 'https://api.spotify.com/v1/search?q=genre:pop&type=artist&limit=20';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> items = data['artists']['items'];
        return items.map((item) => {
          'id': item['id'],
          'name': item['name'],
          'imageUrl': (item['images'] as List).isNotEmpty ? item['images'][0]['url'] : null,
          'genres': item['genres'],
        }).toList();
      }
    } catch (e) {
      print('Error fetching discovery artists: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getDiscoveryAlbums() async {
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
        return items.map((item) => {
          'id': item['id'],
          'name': item['name'],
          'imageUrl': (item['images'] as List).isNotEmpty ? item['images'][0]['url'] : null,
          'artist': item['artists'][0]['name'],
          'releaseDate': item['release_date'],
        }).toList();
      }
    } catch (e) {
      print('Error fetching discovery albums: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getSearchSuggestions(String query) async {
    final token = await getAccessToken();
    if (token == null) return [];

    final url = 'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=artist,track&limit=5';
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
        
        return suggestions;
      }
    } catch (e) {
      print('Error fetching suggestions: $e');
    }
    return [];
  }
}
