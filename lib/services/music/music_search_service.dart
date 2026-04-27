import 'package:flutter/foundation.dart';
import '../../models/music_models.dart';
import 'metadata_provider.dart';
import 'spotify_provider.dart';
import 'musicbrainz_provider.dart';
import 'music_search_ranker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class MusicSearchService {
  final MusicProviderSettings settings;
  final List<MusicMetadataProvider> _providers = [];
  SearchMode defaultSearchMode = SearchMode.smart;

  MusicSearchService(this.settings) {
    if (settings.enableSpotify) {
      _providers.add(SpotifyProvider(settings));
    }
    if (settings.enableMusicBrainz) {
      _providers.add(MusicBrainzProvider(settings));
    }
  }

  Future<void> _logToFile(String message) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/music_search_debug.log');
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString('[$timestamp] $message\n', mode: FileMode.append);
    } catch (e) {
      // Fallback to console if file logging fails
      debugPrint('Failed to log to file: $e');
    }
  }

  Future<List<ScoredTrack>> searchTracksScored(String query, {SearchMode? mode}) async {
    final searchMode = mode ?? defaultSearchMode;
    final results = <String, MusicTrack>{}; // Use Map for deduplication by ID
    
    // Search all providers without early stopping to ensure completeness
    for (final provider in _providers) {
      if (provider.isEnabled) {
        try {
          final providerResults = await provider.searchTracks(query);
          final msg = '${provider.providerName} returned ${providerResults.length} tracks for "$query"';
          debugPrint(msg);
          _logToFile(msg);
          for (final track in providerResults) {
            results[track.id] = track; // Deduplicate by ID
          }
        } catch (e) {
          final msg = 'Error searching tracks from provider ${provider.providerName}: $e';
          debugPrint(msg);
          _logToFile(msg);
        }
      } else {
        final msg = '${provider.providerName} is disabled';
        debugPrint(msg);
        _logToFile(msg);
      }
    }
    
    debugPrint('Total unique tracks found before ranking: ${results.length}');
    if (results.isNotEmpty) {
      final sample = results.values.take(3).map((t) => '${t.title} by ${t.artistName}').join(', ');
      final msg = 'Sample tracks: $sample';
      debugPrint(msg);
      _logToFile(msg);
    }
    final scored = MusicSearchRanker.rankResults(results.values.toList(), query, searchMode);
    final msg1 = 'After ranking and filtering ($searchMode): ${scored.length} results';
    debugPrint(msg1);
    _logToFile(msg1);
    if (scored.isNotEmpty) {
      final sample = scored.take(3).map((s) => '${s.track.title} by ${s.track.artistName} (score: ${s.score.total.toStringAsFixed(1)})').join(', ');
      final msg2 = 'Top scored tracks: $sample';
      debugPrint(msg2);
      _logToFile(msg2);
    }
    return scored;
  }

  // Backwards compatibility for existing code
  Future<List<MusicTrack>> searchTracks(String query) async {
    final scored = await searchTracksScored(query);
    final msg = 'Final track results: ${scored.length}';
    debugPrint(msg);
    _logToFile(msg);
    return scored.map((s) => s.track).toList();
  }

  Future<List<MusicAlbum>> searchAlbums(String query) async {
    final results = <String, MusicAlbum>{}; // Use Map for deduplication by ID
    for (final provider in _providers) {
      if (provider.isEnabled) {
        try {
          final providerResults = await provider.searchAlbums(query);
          for (final album in providerResults) {
            results[album.id] = album; // Deduplicate by ID
          }
        } catch (e) {
          final msg = 'Error searching albums from provider ${provider.providerName}: $e';
          debugPrint(msg);
          _logToFile(msg);
        }
      }
    }
    return results.values.toList();
  }

  Future<List<MusicArtist>> searchArtists(String query) async {
    final results = <String, MusicArtist>{}; // Use Map for deduplication by ID
    for (final provider in _providers) {
      if (provider.isEnabled) {
        try {
          final providerResults = await provider.searchArtists(query);
          final msg = '${provider.providerName} returned ${providerResults.length} artists for "$query"';
          debugPrint(msg);
          _logToFile(msg);
          for (final artist in providerResults) {
            results[artist.id] = artist; // Deduplicate by ID
          }
        } catch (e) {
          final msg = 'Error searching artists from provider ${provider.providerName}: $e';
          debugPrint(msg);
          _logToFile(msg);
        }
      } else {
        final msg = '${provider.providerName} is disabled';
        debugPrint(msg);
        _logToFile(msg);
      }
    }
    final msg = 'Total unique artists found: ${results.length}';
    debugPrint(msg);
    _logToFile(msg);
    return results.values.toList();
  }
  
  Future<MusicTrack?> getTrackDetails(String id, {String? providerName}) async {
    for (final provider in _providers) {
      if (providerName == null || provider.providerName == providerName) {
        try {
          final details = await provider.getTrackDetails(id);
          if (details != null) return details;
        } catch (e) {
          final msg = 'Error getting track details from provider ${provider.providerName}: $e';
          debugPrint(msg);
          _logToFile(msg);
        }
      }
    }
    return null;
  }

  Future<MusicAlbum?> getAlbumDetails(String id) async {
    for (final provider in _providers) {
      try {
        final details = await provider.getAlbumDetails(id);
        if (details != null) return details;
      } catch (e) {
        final msg = 'Error getting album details from provider ${provider.providerName}: $e';
        debugPrint(msg);
        _logToFile(msg);
      }
    }
    return null;
  }

  Future<MusicArtist?> getArtistDetails(String id) async {
    for (final provider in _providers) {
      try {
        final details = await provider.getArtistDetails(id);
        if (details != null) return details;
      } catch (e) {
        final msg = 'Error getting artist details from provider ${provider.providerName}: $e';
        debugPrint(msg);
        _logToFile(msg);
      }
    }
    return null;
  }

  Future<List<MusicTrack>> getAlbumTracks(String albumId) async {
    for (final provider in _providers) {
      try {
        final tracks = await provider.getAlbumTracks(albumId);
        if (tracks.isNotEmpty) return tracks;
      } catch (e) {
        final msg = 'Error getting album tracks from provider ${provider.providerName}: $e';
        debugPrint(msg);
        _logToFile(msg);
      }
    }
    return [];
  }

  Future<List<MusicAlbum>> getArtistAlbums(String artistId) async {
    for (final provider in _providers) {
      try {
        final albums = await provider.getArtistAlbums(artistId);
        if (albums.isNotEmpty) return albums;
      } catch (e) {
        final msg = 'Error getting artist albums from provider ${provider.providerName}: $e';
        debugPrint(msg);
        _logToFile(msg);
      }
    }
    return [];
  }
}
