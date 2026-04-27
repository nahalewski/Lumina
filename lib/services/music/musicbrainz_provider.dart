import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../../models/music_models.dart';
import 'metadata_provider.dart';

class MusicBrainzProvider implements MusicMetadataProvider {
  final MusicProviderSettings settings;
  final String _baseUrl = 'https://musicbrainz.org/ws/2';

  MusicBrainzProvider(this.settings);

  @override
  String get providerName => 'MusicBrainz';

  @override
  bool get isEnabled => settings.enableMusicBrainz;

  Map<String, String> get _headers => {
    'User-Agent': settings.mbUserAgent,
    'Accept': 'application/json',
  };

  @override
  Future<List<MusicTrack>> searchTracks(String query, {int limit = 20}) async {
    final url = '$_baseUrl/recording?query=${Uri.encodeComponent(query)}&limit=$limit&fmt=json';
    debugPrint('MusicBrainz: Searching for tracks by artist "$query"');
    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['recordings'] as List;
        debugPrint('MusicBrainz: Found ${items.length} tracks for artist "$query"');
        return items.map((item) => _mapTrack(item)).toList();
      } else {
        debugPrint('MusicBrainz: API error ${response.statusCode} for artist "$query"');
      }
    } catch (e) {
      debugPrint('MusicBrainz: Error searching tracks: $e');
    }
    return [];
  }

  @override
  Future<List<MusicAlbum>> searchAlbums(String query, {int limit = 20}) async {
    final url = '$_baseUrl/release-group?query=${Uri.encodeComponent(query)}&limit=$limit&fmt=json';
    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['release-groups'] as List;
        return items.map((item) => _mapAlbum(item)).toList();
      }
    } catch (e) {
      debugPrint('MusicBrainz: Error searching tracks: $e');
    }
    return [];
  }

  @override
  Future<List<MusicArtist>> searchArtists(String query, {int limit = 20}) async {
    final url = '$_baseUrl/artist?query=${Uri.encodeComponent(query)}&limit=$limit&fmt=json';
    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['artists'] as List;
        return items.map((item) => _mapArtist(item)).toList();
      }
    } catch (e) {
      print('MusicBrainz Artist Search Error: $e');
    }
    return [];
  }

  @override
  Future<MusicTrack?> getTrackDetails(String id) async {
    final url = '$_baseUrl/recording/$id?inc=artists+releases&fmt=json';
    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        return _mapTrack(jsonDecode(response.body));
      }
    } catch (e) {
      print('MusicBrainz Track Details Error: $e');
    }
    return null;
  }

  @override
  Future<MusicAlbum?> getAlbumDetails(String id) async {
    final url = '$_baseUrl/release-group/$id?inc=artists+releases&fmt=json';
    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        return _mapAlbum(jsonDecode(response.body));
      }
    } catch (e) {
      print('MusicBrainz Album Details Error: $e');
    }
    return null;
  }

  @override
  Future<MusicArtist?> getArtistDetails(String id) async {
    final url = '$_baseUrl/artist/$id?inc=release-groups&fmt=json';
    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        return _mapArtist(jsonDecode(response.body));
      }
    } catch (e) {
      print('MusicBrainz Artist Details Error: $e');
    }
    return null;
  }

  @override
  Future<List<MusicTrack>> getAlbumTracks(String albumId) async {
    // Release Group ID -> Get Releases -> Get first Release -> Get Tracks
    final url = '$_baseUrl/release-group/$albumId?inc=releases&fmt=json';
    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final releases = data['releases'] as List?;
        if (releases?.isNotEmpty == true) {
          final releaseId = releases!.first['id'];
          return await _getReleaseTracks(releaseId);
        }
      }
    } catch (e) {
      print('MusicBrainz Album Tracks Error: $e');
    }
    return [];
  }

  Future<List<MusicTrack>> _getReleaseTracks(String releaseId) async {
    final url = '$_baseUrl/release/$releaseId?inc=recordings&fmt=json';
    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final media = data['media'] as List?;
        final tracks = <MusicTrack>[];
        if (media != null) {
          for (var disc in media) {
            final tracksJson = disc['tracks'] as List?;
            if (tracksJson != null) {
              tracks.addAll(tracksJson.map((t) => _mapTrack(t['recording'])));
            }
          }
        }
        return tracks;
      }
    } catch (e) {
      print('MusicBrainz Release Tracks Error: $e');
    }
    return [];
  }

  @override
  Future<List<MusicAlbum>> getArtistAlbums(String artistId) async {
    final url = '$_baseUrl/artist/$artistId?inc=release-groups&fmt=json';
    try {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final groups = data['release-groups'] as List?;
        if (groups != null) {
          return groups.map((g) => _mapAlbum(g)).toList();
        }
      }
    } catch (e) {
      print('MusicBrainz Artist Albums Error: $e');
    }
    return [];
  }

  MusicTrack _mapTrack(Map<String, dynamic> item) {
    final artistCredit = item['artist-credit'] as List?;
    final firstArtist = artistCredit?.isNotEmpty == true ? artistCredit!.first['artist'] : null;
    final releases = item['releases'] as List?;
    final firstRelease = releases?.isNotEmpty == true ? releases!.first : null;
    final releaseGroupId = firstRelease?['release-group']?['id'];
    
    return MusicTrack(
      id: item['id'],
      title: item['title'],
      artistId: firstArtist?['id'] ?? '',
      artistName: firstArtist?['name'] ?? 'Unknown Artist',
      albumId: releaseGroupId,
      albumName: firstRelease?['title'],
      albumArtworkUrl: releaseGroupId != null 
          ? 'https://coverartarchive.org/release-group/$releaseGroupId/front'
          : null,
      duration: Duration(milliseconds: item['length'] ?? 0),
      musicBrainzId: item['id'],
    );
  }

  MusicAlbum _mapAlbum(Map<String, dynamic> item) {
    final artistCredit = item['artist-credit'] as List?;
    final firstArtist = artistCredit?.isNotEmpty == true ? artistCredit!.first['artist'] : null;

    return MusicAlbum(
      id: item['id'],
      name: item['title'],
      artistId: firstArtist?['id'] ?? '',
      artistName: firstArtist?['name'] ?? 'Unknown Artist',
      artworkUrl: 'https://coverartarchive.org/release-group/${item['id']}/front',
      musicBrainzId: item['id'],
      type: item['primary-type'],
    );
  }

  MusicArtist _mapArtist(Map<String, dynamic> item) {
    return MusicArtist(
      id: item['id'],
      name: item['name'],
      musicBrainzId: item['id'],
      tags: (item['tags'] as List?)?.map((t) => t['name'] as String).toList() ?? [],
    );
  }
}
