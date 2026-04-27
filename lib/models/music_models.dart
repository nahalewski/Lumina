import 'package:flutter/foundation.dart';

enum MusicProviderType {
  spotify,
  musicbrainz,
  lastfm,
  listenbrainz,
  local,
  nas,
}

enum MatchConfidence {
  high,
  medium,
  low,
  none,
}

class MusicTrack {
  final String id;
  final String title;
  final String artistId;
  final String artistName;
  final String? albumId;
  final String? albumName;
  final String? albumArtworkUrl;
  final Duration duration;
  final int? trackNumber;
  final int? discNumber;
  final DateTime? releaseDate;
  final int? popularity;
  final List<String> genres;
  final String? musicBrainzId;
  final String? isrc;
  final Map<String, String> externalUrls;

  MusicTrack({
    required this.id,
    required this.title,
    required this.artistId,
    required this.artistName,
    this.albumId,
    this.albumName,
    this.albumArtworkUrl,
    required this.duration,
    this.trackNumber,
    this.discNumber,
    this.releaseDate,
    this.popularity,
    this.genres = const [],
    this.musicBrainzId,
    this.isrc,
    this.externalUrls = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artistId': artistId,
    'artistName': artistName,
    'albumId': albumId,
    'albumName': albumName,
    'albumArtworkUrl': albumArtworkUrl,
    'durationMs': duration.inMilliseconds,
    'trackNumber': trackNumber,
    'discNumber': discNumber,
    'releaseDate': releaseDate?.toIso8601String(),
    'popularity': popularity,
    'genres': genres,
    'musicBrainzId': musicBrainzId,
    'isrc': isrc,
    'externalUrls': externalUrls,
  };
}

class MusicAlbum {
  final String id;
  final String name;
  final String artistId;
  final String artistName;
  final String? artworkUrl;
  final DateTime? releaseDate;
  final int? totalTracks;
  final List<String> genres;
  final String? musicBrainzId;
  final String? type; // album, single, compilation

  MusicAlbum({
    required this.id,
    required this.name,
    required this.artistId,
    required this.artistName,
    this.artworkUrl,
    this.releaseDate,
    this.totalTracks,
    this.genres = const [],
    this.musicBrainzId,
    this.type,
  });
}

class MusicArtist {
  final String id;
  final String name;
  final String? imageUrl;
  final String? bio;
  final List<String> genres;
  final int? popularity;
  final String? musicBrainzId;
  final List<String> tags;

  MusicArtist({
    required this.id,
    required this.name,
    this.imageUrl,
    this.bio,
    this.genres = const [],
    this.popularity,
    this.musicBrainzId,
    this.tags = const [],
  });
}

class MusicSearchResults {
  final List<MusicTrack> tracks;
  final List<MusicAlbum> albums;
  final List<MusicArtist> artists;

  MusicSearchResults({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
  });

  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty;
}

class MusicMatch {
  final String trackId; // Metadata ID (e.g. Spotify)
  final String? localFilePath;
  final String? remoteSourceUrl;
  final MatchConfidence confidence;
  final String? matchedBy; // provider name
  final DateTime matchedAt;
  final bool isManual;

  MusicMatch({
    required this.trackId,
    this.localFilePath,
    this.remoteSourceUrl,
    required this.confidence,
    this.matchedBy,
    required this.matchedAt,
    this.isManual = false,
  });
}

class MusicProviderSettings {
  // Spotify
  bool enableSpotify = true;
  String spotifyClientId = '';
  String spotifyClientSecret = '';
  String spotifyRedirectUrl = 'http://localhost:8888/callback';

  // MusicBrainz
  bool enableMusicBrainz = true;
  String mbUserAgent = 'LuminaMedia/1.0';
  String mbContactEmail = '';
  bool mbRateLimit = true;

  // Last.fm
  bool enableLastFm = false;
  String lastFmApiKey = '';
  bool enableArtistBios = true;
  bool enableTags = true;

  // ListenBrainz
  bool enableListenBrainz = false;
  String lbUserToken = '';
  bool lbEnableRecommendations = true;
  bool lbEnableHistorySync = false;

  // Audio Sources
  bool enableLocalLibrary = true;
  List<String> musicFolders = [];
  bool autoScanFolders = true;
  bool folderWatcher = false;
  List<String> preferredSourceOrder = ['local', 'youtube'];
  double matchConfidenceThreshold = 0.8;

  // Cache
  bool cacheMetadata = true;
  bool cacheArtwork = true;
  String? cacheLocation;

  MusicProviderSettings();

  Map<String, dynamic> toJson() => {
    'enableSpotify': enableSpotify,
    'spotifyClientId': spotifyClientId,
    'spotifyClientSecret': spotifyClientSecret,
    'spotifyRedirectUrl': spotifyRedirectUrl,
    'enableMusicBrainz': enableMusicBrainz,
    'mbUserAgent': mbUserAgent,
    'mbContactEmail': mbContactEmail,
    'mbRateLimit': mbRateLimit,
    'enableLastFm': enableLastFm,
    'lastFmApiKey': lastFmApiKey,
    'enableArtistBios': enableArtistBios,
    'enableTags': enableTags,
    'enableListenBrainz': enableListenBrainz,
    'lbUserToken': lbUserToken,
    'lbEnableRecommendations': lbEnableRecommendations,
    'lbEnableHistorySync': lbEnableHistorySync,
    'enableLocalLibrary': enableLocalLibrary,
    'musicFolders': musicFolders,
    'autoScanFolders': autoScanFolders,
    'folderWatcher': folderWatcher,
    'preferredSourceOrder': preferredSourceOrder,
    'matchConfidenceThreshold': matchConfidenceThreshold,
    'cacheMetadata': cacheMetadata,
    'cacheArtwork': cacheArtwork,
    'cacheLocation': cacheLocation,
  };

  factory MusicProviderSettings.fromJson(Map<String, dynamic> json) {
    final s = MusicProviderSettings();
    s.enableSpotify = json['enableSpotify'] ?? true;
    s.spotifyClientId = json['spotifyClientId'] ?? '';
    s.spotifyClientSecret = json['spotifyClientSecret'] ?? '';
    s.spotifyRedirectUrl = json['spotifyRedirectUrl'] ?? 'http://localhost:8888/callback';
    s.enableMusicBrainz = json['enableMusicBrainz'] ?? true;
    s.mbUserAgent = json['mbUserAgent'] ?? 'LuminaMedia/1.0';
    s.mbContactEmail = json['mbContactEmail'] ?? '';
    s.mbRateLimit = json['mbRateLimit'] ?? true;
    s.enableLastFm = json['enableLastFm'] ?? false;
    s.lastFmApiKey = json['lastFmApiKey'] ?? '';
    s.enableArtistBios = json['enableArtistBios'] ?? true;
    s.enableTags = json['enableTags'] ?? true;
    s.enableListenBrainz = json['enableListenBrainz'] ?? false;
    s.lbUserToken = json['lbUserToken'] ?? '';
    s.lbEnableRecommendations = json['lbEnableRecommendations'] ?? true;
    s.lbEnableHistorySync = json['lbEnableHistorySync'] ?? false;
    s.enableLocalLibrary = json['enableLocalLibrary'] ?? true;
    s.musicFolders = List<String>.from(json['musicFolders'] ?? []);
    s.autoScanFolders = json['autoScanFolders'] ?? true;
    s.folderWatcher = json['folderWatcher'] ?? false;
    s.preferredSourceOrder = List<String>.from(json['preferredSourceOrder'] ?? ['local', 'youtube']);
    s.matchConfidenceThreshold = (json['matchConfidenceThreshold'] as num?)?.toDouble() ?? 0.8;
    s.cacheMetadata = json['cacheMetadata'] ?? true;
    s.cacheArtwork = json['cacheArtwork'] ?? true;
    s.cacheLocation = json['cacheLocation'];
    return s;
  }
}
