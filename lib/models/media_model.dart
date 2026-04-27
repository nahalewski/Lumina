enum ContentType { anime, adult, general }

enum MediaKind { movie, tv, audio, nsfw, manga, ebook, comic }

enum PlaybackState { idle, loading, playing, paused, buffering, error, stopped }

/// Represents a media file (video/audio) in the library
class MediaFile {
  final String id;
  final String filePath;
  final String fileName;
  final String? thumbnailPath;
  final Duration duration;
  final DateTime addedAt;
  bool isFavorite;
  ContentType contentType;
  bool isWatched;
  int playCount;
  String? resolution;
  String? language;
  List<String> subtitleTracks;
  List<String> audioTracks;
  final String? metadataTitle;

  // Plex-style library metadata
  final MediaKind mediaKind;
  final String? metadataId;
  final String? movieTitle;
  final String? showTitle;
  final String? episodeTitle;
  final String? synopsis;
  final String? posterUrl;
  final String? backdropUrl;
  final String? thumbnailUrl;
  final String? seasonPosterUrl;
  final String? trailerUrl;
  final String? releaseDate;
  final String? airDate;
  final int? releaseYear;
  final double? rating;
  final List<String> genres;
  final List<String> cast;
  final List<String> castPhotoUrls;
  final List<String> directors;
  final List<String> writers;

  // Music-specific fields
  final String? artist;
  final String? album;
  final int? trackNumber;

  // Backward-compatible anime fields
  final String? animeId;
  final String? animeTitle;
  final int? season;
  final int? episode;
  final String? coverArtUrl;
  final String? description;

  MediaFile({
    required this.id,
    required this.filePath,
    required this.fileName,
    this.thumbnailPath,
    this.duration = Duration.zero,
    DateTime? addedAt,
    this.isFavorite = false,
    ContentType? contentType,
    MediaKind? mediaKind,
    this.isWatched = false,
    this.playCount = 0,
    this.resolution,
    this.language,
    List<String>? subtitleTracks,
    List<String>? audioTracks,
    this.metadataId,
    this.movieTitle,
    this.showTitle,
    this.episodeTitle,
    this.synopsis,
    this.posterUrl,
    this.backdropUrl,
    this.thumbnailUrl,
    this.seasonPosterUrl,
    this.trailerUrl,
    this.releaseDate,
    this.airDate,
    this.releaseYear,
    this.rating,
    List<String>? genres,
    List<String>? cast,
    List<String>? castPhotoUrls,
    List<String>? directors,
    List<String>? writers,
    this.animeId,
    this.animeTitle,
    this.season,
    this.episode,
    this.coverArtUrl,
    this.description,
    this.artist,
    this.album,
    this.trackNumber,
    this.metadataTitle,
  })  : addedAt = addedAt ?? DateTime.now(),
        contentType = contentType ?? detectContentType(fileName),
        mediaKind = mediaKind ?? detectMediaKind(fileName),
        subtitleTracks = subtitleTracks ?? const [],
        audioTracks = audioTracks ?? const [],
        genres = genres ?? const [],
        cast = cast ?? const [],
        castPhotoUrls = castPhotoUrls ?? const [],
        directors = directors ?? const [],
        writers = writers ?? const [];

  static ContentType detectContentType(String name) {
    final lower = name.toLowerCase();
    final animeKeywords = [
      'bleach',
      'one piece',
      'naruto',
      'boruto',
      'chainsaw man',
      'jujutsu',
      'demon slayer',
      'kimetsu',
      'spy x family',
      'anime',
      'sub',
      'raw',
      'eng sub',
      'jap sub',
      'sennen kessen',
      '[',
      ']',
      'horriblesubs',
      'subs',
      'dub',
    ];
    final adultKeywords = [
      'uncensored',
      'censored',
      'hentai',
      'porn',
      'adult',
      'sex',
      'ero',
      '18+',
      'jav',
      'leak',
      'xxx',
    ];

    if (adultKeywords.any((k) => lower.contains(k))) return ContentType.adult;
    if (animeKeywords.any((k) => lower.contains(k)) ||
        lower.contains('bleach') ||
        lower.contains('thousand-year blood war')) return ContentType.anime;

    return ContentType.general;
  }

  static MediaKind detectMediaKind(String name, {MediaKind? override}) {
    if (override != null) return override;
    final lower = name.toLowerCase();

    // Priority 1: Clear audio extensions
    if (['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.opus'].any(lower.endsWith)) {
      return MediaKind.audio;
    }

    // Priority 2: TV Patterns
    final tvPatterns = [
      RegExp(r'\bs\d{1,2}e\d{1,3}\b', caseSensitive: false),
      RegExp(r'\b\d{1,2}x\d{1,3}\b', caseSensitive: false),
      RegExp(
        r'\bseason[ ._-]*\d{1,2}[ ._-]*episode[ ._-]*\d{1,3}\b',
        caseSensitive: false,
      ),
      RegExp(r'\bep\d{1,3}\b', caseSensitive: false),
      RegExp(r'\bepisode\s*\d{1,3}\b', caseSensitive: false),
      RegExp(r'\s-\s\d{1,3}\b',
          caseSensitive: false), // Common anime format: "Show - 01"
    ];
    if (tvPatterns.any((p) => p.hasMatch(name))) return MediaKind.tv;

    // Special case for known TV franchises
    final tvKeywords = [
      'bleach',
      'naruto',
      'one piece',
      'boruto',
      'jujutsu',
      'kaisen'
    ];
    if (tvKeywords.any((k) => lower.contains(k))) return MediaKind.tv;

    // Priority 3: Books/Manga/Comics
    if (['.epub', '.pdf', '.mobi'].any(lower.endsWith)) return MediaKind.ebook;
    if (['.cbz', '.cbr'].any(lower.endsWith)) return MediaKind.comic;
    if (['.zip', '.rar'].any(lower.endsWith) && (lower.contains('manga') || lower.contains('chapter'))) return MediaKind.manga;

    // Priority 4: Webm can be audio if no TV pattern matched
    if (lower.endsWith('.webm')) return MediaKind.audio;

    return MediaKind.movie;
  }

  String get extension => fileName.split('.').last.toLowerCase();
  String get title => metadataTitle ?? fileName.replaceAll('.$extension', '');
  String get libraryTitle {
    if (mediaKind == MediaKind.audio) {
      return (artist != null) ? '$artist - $title' : title;
    }
    if (mediaKind == MediaKind.tv) {
      return showTitle ?? animeTitle ?? parsedShowTitle ?? title;
    }
    return movieTitle ?? animeTitle ?? title;
  }

  String get displayTitle => episodeTitle ?? movieTitle ?? animeTitle ?? title;
  String? get parsedShowTitle => _parseEpisodeInfo(fileName).showTitle;
  int? get parsedSeason => _parseEpisodeInfo(fileName).season;
  int? get parsedEpisode => _parseEpisodeInfo(fileName).episode;
  String? get parsedEpisodeTitle => _parseEpisodeInfo(fileName).episodeTitle;
  bool get isVideo => ['mp4', 'mkv', 'mov', 'avi', 'webm'].contains(extension);
  bool get isAudio =>
      ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'].contains(extension);

  String get durationFormatted {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m ${seconds}s';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'fileName': fileName,
        'thumbnailPath': thumbnailPath,
        'duration': duration.inMilliseconds,
        'addedAt': addedAt.toIso8601String(),
        'isFavorite': isFavorite,
        'contentType': contentType.index,
        'mediaKind': mediaKind.index,
        'isWatched': isWatched,
        'playCount': playCount,
        'resolution': resolution,
        'language': language,
        'subtitleTracks': subtitleTracks,
        'audioTracks': audioTracks,
        'metadataId': metadataId,
        'movieTitle': movieTitle,
        'showTitle': showTitle,
        'episodeTitle': episodeTitle,
        'synopsis': synopsis,
        'posterUrl': posterUrl,
        'backdropUrl': backdropUrl,
        'thumbnailUrl': thumbnailUrl,
        'seasonPosterUrl': seasonPosterUrl,
        'trailerUrl': trailerUrl,
        'releaseDate': releaseDate,
        'airDate': airDate,
        'releaseYear': releaseYear,
        'rating': rating,
        'genres': genres,
        'cast': cast,
        'castPhotoUrls': castPhotoUrls,
        'directors': directors,
        'writers': writers,
        'animeId': animeId,
        'animeTitle': animeTitle,
        'season': season,
        'episode': episode,
        'coverArtUrl': coverArtUrl,
        'description': description,
        'artist': artist,
        'album': album,
        'trackNumber': trackNumber,
        'metadataTitle': metadataTitle,
      };

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        fileName: json['fileName'] as String,
        thumbnailPath: json['thumbnailPath'] as String?,
        duration: Duration(milliseconds: json['duration'] as int? ?? 0),
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.now(),
        isFavorite: json['isFavorite'] as bool? ?? false,
        contentType: json['contentType'] != null
            ? ContentType.values[json['contentType'] as int]
            : null,
        mediaKind: json['mediaKind'] != null
            ? MediaKind.values[json['mediaKind'] as int]
            : null,
        isWatched: json['isWatched'] as bool? ?? false,
        playCount: json['playCount'] as int? ?? 0,
        resolution: json['resolution'] as String?,
        language: json['language'] as String?,
        subtitleTracks: (json['subtitleTracks'] as List?)?.cast<String>(),
        audioTracks: (json['audioTracks'] as List?)?.cast<String>(),
        metadataId: json['metadataId'] as String?,
        movieTitle: json['movieTitle'] as String?,
        showTitle: json['showTitle'] as String?,
        episodeTitle: json['episodeTitle'] as String?,
        synopsis: json['synopsis'] as String?,
        posterUrl: json['posterUrl'] as String?,
        backdropUrl: json['backdropUrl'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        seasonPosterUrl: json['seasonPosterUrl'] as String?,
        trailerUrl: json['trailerUrl'] as String?,
        releaseDate: json['releaseDate'] as String?,
        airDate: json['airDate'] as String?,
        releaseYear: json['releaseYear'] as int?,
        rating: (json['rating'] as num?)?.toDouble(),
        genres: (json['genres'] as List?)?.cast<String>(),
        cast: (json['cast'] as List?)?.cast<String>(),
        castPhotoUrls: (json['castPhotoUrls'] as List?)?.cast<String>(),
        directors: (json['directors'] as List?)?.cast<String>(),
        writers: (json['writers'] as List?)?.cast<String>(),
        animeId: json['animeId'],
        animeTitle: json['animeTitle'],
        season: json['season'],
        episode: json['episode'],
        coverArtUrl: json['coverArtUrl'] as String?,
        description: json['description'] as String?,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        trackNumber: json['trackNumber'] as int?,
        metadataTitle: json['metadataTitle'] as String?,
      );

  MediaFile copyWith({
    bool? isFavorite,
    ContentType? contentType,
    MediaKind? mediaKind,
    bool? isWatched,
    int? playCount,
    String? resolution,
    String? language,
    List<String>? subtitleTracks,
    List<String>? audioTracks,
    String? metadataId,
    String? movieTitle,
    String? showTitle,
    String? episodeTitle,
    String? synopsis,
    String? posterUrl,
    String? backdropUrl,
    String? thumbnailUrl,
    String? seasonPosterUrl,
    String? trailerUrl,
    String? releaseDate,
    String? airDate,
    int? releaseYear,
    double? rating,
    List<String>? genres,
    List<String>? cast,
    List<String>? castPhotoUrls,
    List<String>? directors,
    List<String>? writers,
    String? animeId,
    String? animeTitle,
    int? season,
    int? episode,
    String? coverArtUrl,
    String? description,
    String? artist,
    String? album,
    int? trackNumber,
    String? metadataTitle,
  }) {
    return MediaFile(
      id: id,
      filePath: filePath,
      fileName: fileName,
      thumbnailPath: thumbnailPath,
      duration: duration,
      addedAt: addedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      contentType: contentType ?? this.contentType,
      mediaKind: mediaKind ?? this.mediaKind,
      isWatched: isWatched ?? this.isWatched,
      playCount: playCount ?? this.playCount,
      resolution: resolution ?? this.resolution,
      language: language ?? this.language,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      audioTracks: audioTracks ?? this.audioTracks,
      metadataId: metadataId ?? this.metadataId,
      movieTitle: movieTitle ?? this.movieTitle,
      showTitle: showTitle ?? this.showTitle,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      synopsis: synopsis ?? this.synopsis,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      seasonPosterUrl: seasonPosterUrl ?? this.seasonPosterUrl,
      trailerUrl: trailerUrl ?? this.trailerUrl,
      releaseDate: releaseDate ?? this.releaseDate,
      airDate: airDate ?? this.airDate,
      releaseYear: releaseYear ?? this.releaseYear,
      rating: rating ?? this.rating,
      genres: genres ?? this.genres,
      cast: cast ?? this.cast,
      castPhotoUrls: castPhotoUrls ?? this.castPhotoUrls,
      directors: directors ?? this.directors,
      writers: writers ?? this.writers,
      animeId: animeId ?? this.animeId,
      animeTitle: animeTitle ?? this.animeTitle,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      coverArtUrl: coverArtUrl ?? this.coverArtUrl,
      description: description ?? this.description,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      trackNumber: trackNumber ?? this.trackNumber,
      metadataTitle: metadataTitle ?? this.metadataTitle,
    );
  }
}

class ParsedEpisodeInfo {
  final String? showTitle;
  final int? season;
  final int? episode;
  final String? episodeTitle;

  const ParsedEpisodeInfo({
    this.showTitle,
    this.season,
    this.episode,
    this.episodeTitle,
  });
}

ParsedEpisodeInfo parseEpisodeInfoFromFileName(String fileName) =>
    _parseEpisodeInfo(fileName);

ParsedEpisodeInfo _parseEpisodeInfo(String fileName) {
  var base = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
  base = base.replaceAll(RegExp(r'\[[^\]]+\]'), ' ').trim();

  final patterns = [
    RegExp(
      r'^(.*?)\s*[ ._-]+s(\d{1,2})e(\d{1,3})(?:\s*[ ._-]+(.*))?$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(.*?)\s*[ ._-]+(\d{1,2})x(\d{1,3})(?:\s*[ ._-]+(.*))?$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(.*?)\s*[ ._-]+season[ ._-]*(\d{1,2})[ ._-]*episode[ ._-]*(\d{1,3})(?:\s*[ ._-]+(.*))?$',
      caseSensitive: false,
    ),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(base);
    if (match == null) continue;
    return ParsedEpisodeInfo(
      showTitle: _cleanTitle(match.group(1)),
      season: int.tryParse(match.group(2) ?? ''),
      episode: int.tryParse(match.group(3) ?? ''),
      episodeTitle: _cleanTitle(match.group(4)),
    );
  }

  return const ParsedEpisodeInfo();
}

String? _cleanTitle(String? value) {
  if (value == null) return null;
  final cleaned = value
      .replaceAll(
        RegExp(
          r'\b(1080p|720p|2160p|4k|bluray|web-dl|webrip|h264|x264|x265|hevc)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'\s*-\s*'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? null : cleaned;
}

enum TranslationProfile { standard, adult }

class MediaFolder {
  final String path;
  final MediaKind type;

  MediaFolder({required this.path, required this.type});

  Map<String, dynamic> toJson() => {'path': path, 'type': type.index};
  factory MediaFolder.fromJson(Map<String, dynamic> json) => MediaFolder(
        path: json['path'],
        type: MediaKind.values[json['type']],
      );
}

enum ParticleTheme { sakura, skulls }

class PlaybackSettings {
  bool isMuted = false;
  bool autoOrganizeManga = false;
  bool autoOrganizeComics = false;
  bool autoOrganizeEbooks = false;
  ParticleTheme particleTheme = ParticleTheme.sakura;
  double volume = 1.0;
  double playbackSpeed = 1.0;
  bool useOllamaTranslation = true;
  bool autoProcessNewMedia = true;
  bool enableIntro = true;
  bool enableMenuMusic = true;
  bool showNsfwTab = false;
  bool keepScreenOn = true;
  String? movieStoragePath;
  String? tvShowStoragePath;
  String? nsfwStoragePath;
  String? musicSavePath;
  String? ebookStoragePath;
  String? mangaStoragePath;
  String? comicsStoragePath;
  String ollamaModel = 'qwen2.5:14b-instruct';
  int iptvMaxConnections = 2;
  String iptvUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) LuminaMedia/1.0';
  TranslationProfile translationProfile = TranslationProfile.standard;
  bool isFullscreen = false;
  bool enablePiaVpn = false;
  String piaVpnRegion = 'ca-ontario';
  String? piaVpnCustomPath;
  String mediaServerToken = '';
  bool autoStartServer = false;
  List<String> pairedDeviceIds = [];
  Map<String, String> pairedDevices = {};
  List<String> deniedDeviceIds = [];
  bool enableRemoteTunnel = false;
  Map<String, bool> scraperToggles = {
    'tmdb': true,
    'tvmaze': true,
    'omdb': false,
    'jikan': true,
    'shikimori': true,
    'anilist': true,
    'kitsu': true,
    'spotify': true,
    'lastfm': false,
    'musicbrainz': true,
    'opensubtitles': true,
    'subscene': false,
    'yifysubtitles': false,
    'addic7ed': false,
    'wikidata': true,
    'imdb': true,
    'openweather': false,
    'danbooru': false,
    'waifupics': false,
  };
  Map<String, bool> documentMetadataToggles = {
    'googleBooks': true,
    'openLibraryCovers': true,
    'openLibrary': true,
    'projectGutenberg': true,
    'mangaDex': true,
    'jikan': true,
    'metaChan': false,
    'mangaVerse': false,
    'comicVine': true,
  };
  List<MediaFolder> mediaFolders = [];
  List<Map<String, String>> bookmarks = [
    {'name': 'AnimeNexus', 'url': 'https://anime.nexus'},
    {'name': 'AnimeKai', 'url': 'https://animekai.to/home'},
  ];

  PlaybackSettings();

  Map<String, dynamic> toJson() => {
        'isMuted': isMuted,
        'volume': volume,
        'playbackSpeed': playbackSpeed,
        'useOllamaTranslation': useOllamaTranslation,
        'autoProcessNewMedia': autoProcessNewMedia,
        'enableIntro': enableIntro,
        'enableMenuMusic': enableMenuMusic,
        'showNsfwTab': showNsfwTab,
        'movieStoragePath': movieStoragePath,
        'tvShowStoragePath': tvShowStoragePath,
        'nsfwStoragePath': nsfwStoragePath,
        'musicSavePath': musicSavePath,
        'ebookStoragePath': ebookStoragePath,
        'mangaStoragePath': mangaStoragePath,
        'comicsStoragePath': comicsStoragePath,
        'ollamaModel': ollamaModel,
        'translationProfile': translationProfile.index,
        'isFullscreen': isFullscreen,
        'enablePiaVpn': enablePiaVpn,
        'piaVpnRegion': piaVpnRegion,
        'piaVpnCustomPath': piaVpnCustomPath,
        'mediaServerToken': mediaServerToken,
        'autoStartServer': autoStartServer,
        'pairedDeviceIds': pairedDeviceIds,
        'pairedDevices': pairedDevices,
        'deniedDeviceIds': deniedDeviceIds,
        'enableRemoteTunnel': enableRemoteTunnel,
        'scraperToggles': scraperToggles,
        'documentMetadataToggles': documentMetadataToggles,
        'mediaFolders': mediaFolders.map((f) => f.toJson()).toList(),
        'bookmarks': bookmarks,
        'iptvMaxConnections': iptvMaxConnections,
        'iptvUserAgent': iptvUserAgent,
        'autoOrganizeManga': autoOrganizeManga,
        'autoOrganizeComics': autoOrganizeComics,
        'autoOrganizeEbooks': autoOrganizeEbooks,
        'particleTheme': particleTheme.index,
      };

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) {
    final settings = PlaybackSettings();
    settings.isMuted = json['isMuted'] ?? false;
    settings.autoOrganizeManga = json['autoOrganizeManga'] ?? false;
    settings.autoOrganizeComics = json['autoOrganizeComics'] ?? false;
    settings.autoOrganizeEbooks = json['autoOrganizeEbooks'] ?? false;
    settings.particleTheme = ParticleTheme.values[json['particleTheme'] ?? 0];
    settings.volume = json['volume'] ?? 1.0;
    settings.playbackSpeed = json['playbackSpeed'] ?? 1.0;
    settings.useOllamaTranslation = json['useOllamaTranslation'] ?? true;
    settings.autoProcessNewMedia = json['autoProcessNewMedia'] ?? true;
    settings.enableIntro = json['enableIntro'] ?? true;
    settings.enableMenuMusic = json['enableMenuMusic'] ?? true;
    settings.showNsfwTab = json['showNsfwTab'] ?? false;
    settings.movieStoragePath = json['movieStoragePath'];
    settings.tvShowStoragePath = json['tvShowStoragePath'];
    settings.nsfwStoragePath = json['nsfwStoragePath'];
    settings.musicSavePath = json['musicSavePath'];
    settings.ebookStoragePath = json['ebookStoragePath'];
    settings.mangaStoragePath = json['mangaStoragePath'];
    settings.comicsStoragePath = json['comicsStoragePath'];
    settings.ollamaModel = json['ollamaModel'] ?? 'qwen2.5:14b-instruct';
    settings.translationProfile = json['translationProfile'] != null
        ? TranslationProfile.values[json['translationProfile']]
        : TranslationProfile.standard;
    settings.isFullscreen = json['isFullscreen'] ?? false;
    settings.enablePiaVpn = json['enablePiaVpn'] ?? false;
    settings.piaVpnRegion = json['piaVpnRegion'] ?? 'ca-ontario';
    settings.piaVpnCustomPath = json['piaVpnCustomPath'];
    settings.mediaServerToken = json['mediaServerToken'] ?? '';
    settings.autoStartServer = json['autoStartServer'] ?? false;
    settings.pairedDeviceIds = List<String>.from(json['pairedDeviceIds'] ?? []);
    settings.pairedDevices =
        Map<String, String>.from(json['pairedDevices'] ?? {});
    settings.iptvMaxConnections = json['iptvMaxConnections'] ?? 2;
    settings.iptvUserAgent = json['iptvUserAgent'] ??
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) LuminaMedia/1.0';

    // Migration: If we have IDs but no names, add them with 'Unknown Device'
    for (var id in settings.pairedDeviceIds) {
      if (!settings.pairedDevices.containsKey(id)) {
        settings.pairedDevices[id] = 'Unknown Device';
      }
    }

    settings.deniedDeviceIds = List<String>.from(json['deniedDeviceIds'] ?? []);
    settings.enableRemoteTunnel = json['enableRemoteTunnel'] ?? false;
    if (json['scraperToggles'] != null) {
      settings.scraperToggles = {
        ...settings.scraperToggles,
        ...Map<String, bool>.from(json['scraperToggles'] as Map),
      };
    }
    if (json['documentMetadataToggles'] != null) {
      settings.documentMetadataToggles = {
        ...settings.documentMetadataToggles,
        ...Map<String, bool>.from(json['documentMetadataToggles'] as Map),
      };
    }
    if (json['mediaFolders'] != null) {
      settings.mediaFolders = List<MediaFolder>.from(
        (json['mediaFolders'] as List).map((e) => MediaFolder.fromJson(e)),
      );
    }
    if (json['bookmarks'] != null) {
      settings.bookmarks = List<Map<String, String>>.from(
        (json['bookmarks'] as List).map((e) => Map<String, String>.from(e)),
      );
    }
    return settings;
  }
}
class PairedDevice {
  final String id;
  final String name;
  final DateTime pairedAt;
  final String? lastKnownIp;
  final DateTime? lastSeenAt;

  const PairedDevice({
    required this.id,
    required this.name,
    required this.pairedAt,
    this.lastKnownIp,
    this.lastSeenAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pairedAt': pairedAt.toIso8601String(),
        'lastKnownIp': lastKnownIp,
        'lastSeenAt': lastSeenAt?.toIso8601String(),
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        pairedAt:
            DateTime.tryParse(json['pairedAt'] as String? ?? '') ?? DateTime.now(),
        lastKnownIp: json['lastKnownIp'] as String?,
        lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
      );

  PairedDevice copyWith({
    String? name,
    String? lastKnownIp,
    DateTime? lastSeenAt,
  }) {
    return PairedDevice(
      id: id,
      name: name ?? this.name,
      pairedAt: pairedAt,
      lastKnownIp: lastKnownIp ?? this.lastKnownIp,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}
