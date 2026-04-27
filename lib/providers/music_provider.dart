import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/music_models.dart';
import '../models/media_model.dart';
import '../services/music/music_search_service.dart';
import '../services/music/audio_match_service.dart';
import '../services/db_service.dart';

class MusicProvider extends ChangeNotifier {
  MusicProviderSettings _settings = MusicProviderSettings();
  late MusicSearchService _searchService;
  final AudioMatchService _matchService = AudioMatchService();
  final DBService _db = DBService.instance;

  MusicSearchResults _searchResults = MusicSearchResults();
  bool _isSearching = false;
  int _searchId = 0;

  MusicProvider() {
    _loadSettings();
    _searchService = MusicSearchService(_settings);
  }

  MusicProviderSettings get settings => _settings;
  MusicSearchResults get searchResults => _searchResults;
  bool get isSearching => _isSearching;

  Future<void> _loadSettings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/music_settings.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        _settings = MusicProviderSettings.fromJson(data);
        _searchService = MusicSearchService(_settings);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading music settings: $e');
    }
  }

  Future<void> saveSettings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/music_settings.json');
      await file.writeAsString(jsonEncode(_settings.toJson()));
      _searchService = MusicSearchService(_settings);
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving music settings: $e');
    }
  }

  Future<void> search(String query) async {
    final myId = ++_searchId;

    if (query.isEmpty) {
      _searchResults = MusicSearchResults();
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _searchService.searchTracks(query),
        _searchService.searchAlbums(query),
        _searchService.searchArtists(query),
      ]);
      
      if (myId != _searchId) return;

      _searchResults = MusicSearchResults(
        tracks: results[0] as List<MusicTrack>,
        albums: results[1] as List<MusicAlbum>,
        artists: results[2] as List<MusicArtist>,
      );
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      if (myId == _searchId) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  Future<MusicTrack?> getTrackDetails(String id, {String? providerName}) async {
    return await _searchService.getTrackDetails(id, providerName: providerName);
  }

  Future<MusicMatch?> findAudioSource(MusicTrack track, List<MediaFile> localLibrary) async {
    return await _matchService.findMatch(track, localLibrary);
  }

  Future<MusicAlbum?> getAlbumDetails(String id) async {
    return await _searchService.getAlbumDetails(id);
  }

  Future<MusicArtist?> getArtistDetails(String id) async {
    return await _searchService.getArtistDetails(id);
  }

  Future<List<MusicTrack>> getAlbumTracks(String albumId) async {
    return await _searchService.getAlbumTracks(albumId);
  }

  Future<List<MusicAlbum>> getArtistAlbums(String artistId) async {
    return await _searchService.getArtistAlbums(artistId);
  }

  void updateSettings(MusicProviderSettings newSettings) {
    _settings = newSettings;
    saveSettings();
  }
}
