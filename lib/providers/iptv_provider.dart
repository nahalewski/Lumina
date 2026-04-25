import 'dart:async';
import 'package:flutter/material.dart';
import '../services/iptv_service.dart';

class IptvProvider with ChangeNotifier {
  final IptvService _service = IptvService();
  List<IptvMedia> _allMedia = [];
  List<EpgEntry> _epgEntries = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isLoadingEpg = false;
  Timer? _refreshTimer;
  String? _lastError;

  // Categorized data per tab
  List<IptvMedia> _liveChannels = [];
  List<IptvMedia> _movies = [];
  List<IptvMedia> _tvShows = [];
  List<IptvMedia> _recentlyAddedMovies = [];
  Map<String, Map<String, List<IptvMedia>>> _groupedSeries = {}; // Show -> Season -> Episodes
  
  List<String> _liveGroups = [];
  List<String> _movieGroups = [];
  List<String> _seriesGroups = [];

  // Getters for each tab
  List<IptvMedia> get liveChannels => _liveChannels;
  List<IptvMedia> get movies => _movies;
  List<IptvMedia> get tvShows => _tvShows;
  List<IptvMedia> get recentlyAddedMovies => _recentlyAddedMovies;
  Map<String, Map<String, List<IptvMedia>>> get groupedSeries => _groupedSeries;
  
  List<String> get liveGroups => _liveGroups;
  List<String> get movieGroups => _movieGroups;
  List<String> get seriesGroups => _seriesGroups;

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  bool get isLoadingEpg => _isLoadingEpg;
  String? get lastError => _lastError;
  List<EpgEntry> get epgEntries => _epgEntries;

  // Credentials
  String get server => _service.server;
  String get port => _service.port;
  String get username => _service.username;
  String get password => _service.password;

  Timer? _loadingTimeout;

  void initialize() {
    _refreshTimer?.cancel();
    Future.microtask(() {
      loadMedia();
      loadEpg();
    });
    _refreshTimer = Timer.periodic(const Duration(hours: 1), (_) {
      loadMedia();
      loadEpg();
    });
  }

  void _startLoadingTimeout() {
    _loadingTimeout?.cancel();
    _loadingTimeout = Timer(const Duration(seconds: 45), () {
      if (_isLoading) {
        _isLoading = false;
        _lastError = 'Loading timed out. Check your IPTV server connection.';
        notifyListeners();
      }
    });
  }

  void updateCredentials({
    required String server,
    required String port,
    required String username,
    required String password,
  }) {
    _service.updateCredentials(
      server: server,
      port: port,
      username: username,
      password: password,
    );
    loadMedia();
    loadEpg();
  }

  Future<void> loadMedia() async {
    if (_isLoading) return;
    _isLoading = true;
    _lastError = null;
    _startLoadingTimeout();
    notifyListeners();

    try {
      _allMedia = await _service.fetchMedia();
      _loadingTimeout?.cancel();
      _hasLoaded = true;

      if (_allMedia.isEmpty) {
        _lastError = 'No media found. Check your IPTV credentials.';
        _liveChannels = [];
        _movies = [];
        _tvShows = [];
        _recentlyAddedMovies = [];
        _groupedSeries = {};
      } else {
        // Use the explicit types from parsing
        _liveChannels = _allMedia.where((m) => m.type == IptvType.live).toList();
        _movies = _allMedia.where((m) => m.type == IptvType.movie).toList();
        _tvShows = _allMedia.where((m) => m.type == IptvType.series).toList();

        // If Series is still empty, try to fallback to group-based detection
        if (_tvShows.isEmpty) {
           _tvShows = _allMedia.where((m) => 
            !m.isLive && 
            (m.group.toLowerCase().contains('series') || 
             m.group.toLowerCase().contains('season') ||
             m.group.toLowerCase().contains('episode'))
          ).toList();
          
          final seriesUrls = _tvShows.map((s) => s.url).toSet();
          _movies.removeWhere((m) => seriesUrls.contains(m.url));
        }

        // Setup groups
        _liveGroups = _liveChannels.map((m) => m.group).toSet().toList()..sort();
        _movieGroups = _movies.map((m) => m.group).toSet().toList()..sort();
        _seriesGroups = _tvShows.map((m) => m.group).toSet().toList()..sort();

        // 1. Hierarchical Series Grouping (Show -> Season -> Episode)
        _groupedSeries = {};
        for (final episode in _tvShows) {
          final sPattern1 = RegExp(r'^(.+?)\s+S(\d+)\s*E(\d+)', caseSensitive: false);
          final sPattern2 = RegExp(r'^(.+?)\s+S(\d+)E(\d+)', caseSensitive: false);
          final sPattern3 = RegExp(r'^(.+?)\s+(\d+)x(\d+)', caseSensitive: false);
          final sPattern4 = RegExp(r'^(.+?)\s+Season\s*(\d+)\s*Episode\s*(\d+)', caseSensitive: false);
          final sPattern5 = RegExp(r'^(.+?)\s+Part\s*(\d+)', caseSensitive: false);

          String showName = episode.name;
          String seasonNum = "1";

          final match1 = sPattern1.firstMatch(episode.name);
          final match2 = sPattern2.firstMatch(episode.name);
          final match3 = sPattern3.firstMatch(episode.name);
          final match4 = sPattern4.firstMatch(episode.name);
          final match5 = sPattern5.firstMatch(episode.name);

          if (match1 != null) {
            showName = match1.group(1)!.trim();
            seasonNum = int.tryParse(match1.group(2)!)?.toString() ?? "1";
          } else if (match2 != null) {
            showName = match2.group(1)!.trim();
            seasonNum = int.tryParse(match2.group(2)!)?.toString() ?? "1";
          } else if (match3 != null) {
            showName = match3.group(1)!.trim();
            seasonNum = int.tryParse(match3.group(2)!)?.toString() ?? "1";
          } else if (match4 != null) {
            showName = match4.group(1)!.trim();
            seasonNum = int.tryParse(match4.group(2)!)?.toString() ?? "1";
          } else if (match5 != null) {
            showName = match5.group(1)!.trim();
            seasonNum = "1";
          } else {
            if (!episode.group.toLowerCase().contains('series') && !episode.group.toLowerCase().contains('tv show')) {
              showName = episode.group;
            }
          }

          _groupedSeries.putIfAbsent(showName, () => {});
          _groupedSeries[showName]!.putIfAbsent("Season $seasonNum", () => []);
          _groupedSeries[showName]!["Season $seasonNum"]!.add(episode);
        }

        // 2. Setup Recently Added (sort by addedDate descending)
        _recentlyAddedMovies = List.from(_movies)
          ..sort((a, b) => (b.addedDate ?? DateTime(2000)).compareTo(a.addedDate ?? DateTime(2000)));
        if (_recentlyAddedMovies.length > 50) {
          _recentlyAddedMovies = _recentlyAddedMovies.sublist(0, 50);
        }

        _lastError = null;
      }
    } catch (e) {
      _lastError = 'Failed to load IPTV: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadEpg() async {
    if (_isLoadingEpg) return;
    _isLoadingEpg = true;
    notifyListeners();

    try {
      _epgEntries = await _service.fetchEpg();
    } catch (e) {
      print("IPTV EPG error: $e");
    }

    _isLoadingEpg = false;
    notifyListeners();
  }

  List<EpgEntry> getEpgForChannel(String? tvgId) {
    if (tvgId == null || tvgId.isEmpty) return [];
    return _epgEntries.where((e) => e.channelId == tvgId).toList();
  }

  EpgEntry? getCurrentProgram(String? tvgId) {
    if (tvgId == null || tvgId.isEmpty) return null;
    final now = DateTime.now();
    try {
      final channelEntries = _epgEntries.where((e) => e.channelId == tvgId).toList();
      return channelEntries.firstWhere(
        (e) => e.start.isBefore(now) && e.end.isAfter(now),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
