import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../../models/music_models.dart';
import '../spotify_service.dart';
import 'metadata_provider.dart';

class SpotifyProvider implements MusicMetadataProvider {
  final SpotifyService _service = SpotifyService();
  final MusicProviderSettings settings;

  SpotifyProvider(this.settings) {
    _service.setCredentials(settings.spotifyClientId, settings.spotifyClientSecret);
  }

  @override
  String get providerName => 'Spotify';

  @override
  bool get isEnabled => settings.enableSpotify;

  @override
  Future<List<MusicTrack>> searchTracks(String query, {int limit = 20}) async {
    final token = await _service.getAccessToken();
    if (token == null) {
      debugPrint('Spotify: No access token available - check credentials');
      return [];
    }
    debugPrint('Spotify: Got access token, searching for "$query"');

    final url = 'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=track&limit=$limit';
    final response = await http.get(Uri.parse(url), headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final items = data['tracks']['items'] as List;
      debugPrint('Spotify: Found ${items.length} tracks for "$query"');
      return items.map((item) => _mapTrack(item)).toList();
    } else {
      debugPrint('Spotify: API error ${response.statusCode} for "$query": ${response.body}');
    }
    return [];
  }

  @override
  Future<List<MusicAlbum>> searchAlbums(String query, {int limit = 20}) async {
    final token = await _service.getAccessToken();
    if (token == null) return [];

    final url = 'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=album&limit=$limit';
    final response = await http.get(Uri.parse(url), headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final items = data['albums']['items'] as List;
      return items.map((item) => _mapAlbum(item)).toList();
    }
    return [];
  }

  @override
  Future<List<MusicArtist>> searchArtists(String query, {int limit = 20}) async {
    final token = await _service.getAccessToken();
    if (token == null) return [];

    final url = 'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=artist&limit=$limit';
    final response = await http.get(Uri.parse(url), headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final items = data['artists']['items'] as List;
      return items.map((item) => _mapArtist(item)).toList();
    }
    return [];
  }

  @override
  Future<MusicTrack?> getTrackDetails(String id) async {
    final token = await _service.getAccessToken();
    if (token == null) return null;

    final url = 'https://api.spotify.com/v1/tracks/$id';
    final response = await http.get(Uri.parse(url), headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      return _mapTrack(jsonDecode(response.body));
    }
    return null;
  }

  @override
  Future<MusicAlbum?> getAlbumDetails(String id) async {
    final token = await _service.getAccessToken();
    if (token == null) return null;

    final url = 'https://api.spotify.com/v1/albums/$id';
    final response = await http.get(Uri.parse(url), headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      return _mapAlbum(jsonDecode(response.body));
    }
    return null;
  }

  @override
  Future<MusicArtist?> getArtistDetails(String id) async {
    final token = await _service.getAccessToken();
    if (token == null) return null;

    final url = 'https://api.spotify.com/v1/artists/$id';
    final response = await http.get(Uri.parse(url), headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      return _mapArtist(jsonDecode(response.body));
    }
    return null;
  }

  @override
  Future<List<MusicTrack>> getAlbumTracks(String albumId) async {
    final token = await _service.getAccessToken();
    if (token == null) return [];

    final url = 'https://api.spotify.com/v1/albums/$albumId/tracks?limit=50';
    final response = await http.get(Uri.parse(url), headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final items = data['items'] as List;
      return items.map((item) => _mapTrack(item)).toList();
    }
    return [];
  }

  @override
  Future<List<MusicAlbum>> getArtistAlbums(String artistId) async {
    final token = await _service.getAccessToken();
    if (token == null) return [];

    final url = 'https://api.spotify.com/v1/artists/$artistId/albums?limit=50&include_groups=album,single';
    final response = await http.get(Uri.parse(url), headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final items = data['items'] as List;
      return items.map((item) => _mapAlbum(item)).toList();
    }
    return [];
  }

  MusicTrack _mapTrack(Map<String, dynamic> item) {
    final album = item['album'] as Map<String, dynamic>?;
    final artists = item['artists'] as List;
    final firstArtist = artists.first as Map<String, dynamic>;
    
    return MusicTrack(
      id: item['id'],
      title: item['name'],
      artistId: firstArtist['id'],
      artistName: firstArtist['name'],
      albumId: album?['id'],
      albumName: album?['name'],
      albumArtworkUrl: (album?['images'] as List?)?.isNotEmpty == true 
          ? album!['images'][0]['url'] 
          : null,
      duration: Duration(milliseconds: item['duration_ms'] ?? 0),
      trackNumber: item['track_number'],
      discNumber: item['disc_number'],
      releaseDate: DateTime.tryParse(album?['release_date'] ?? ''),
      popularity: item['popularity'],
      isrc: item['external_ids']?['isrc'],
      externalUrls: Map<String, String>.from(item['external_urls'] ?? {}),
    );
  }

  MusicAlbum _mapAlbum(Map<String, dynamic> item) {
    final artists = item['artists'] as List;
    final firstArtist = artists.first as Map<String, dynamic>;

    return MusicAlbum(
      id: item['id'],
      name: item['name'],
      artistId: firstArtist['id'],
      artistName: firstArtist['name'],
      artworkUrl: (item['images'] as List?)?.isNotEmpty == true 
          ? item['images'][0]['url'] 
          : null,
      releaseDate: DateTime.tryParse(item['release_date'] ?? ''),
      totalTracks: item['total_tracks'],
      type: item['album_type'],
    );
  }

  MusicArtist _mapArtist(Map<String, dynamic> item) {
    return MusicArtist(
      id: item['id'],
      name: item['name'],
      imageUrl: (item['images'] as List?)?.isNotEmpty == true 
          ? item['images'][0]['url'] 
          : null,
      genres: List<String>.from(item['genres'] ?? []),
      popularity: item['popularity'],
    );
  }
}
