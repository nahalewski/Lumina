enum ContentType { anime, adult, general }

enum MediaKind { movie, tv, audio }

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
  })  : addedAt = addedAt ?? DateTime.now(),
        contentType = contentType ?? _detectContentType(fileName),
        mediaKind = mediaKind ?? _detectMediaKind(fileName),
        subtitleTracks = subtitleTracks ?? const [],
        audioTracks = audioTracks ?? const [],
        genres = genres ?? const [],
        cast = cast ?? const [],
        castPhotoUrls = castPhotoUrls ?? const [],
        directors = directors ?? const [],
        writers = writers ?? const [];

  static ContentType _detectContentType(String name) {
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
    ];
    final adultKeywords = [
      'uncensored',
      'hentai',
      'porn',
      'adult',
      'sex',
      'ero',
      '18+',
      'jav',
      'leak',
      'brazzers',
      'bang',
      'cum',
      'cock',
      'pussy',
    ];

    if (adultKeywords.any((k) => lower.contains(k))) return ContentType.adult;
    if (animeKeywords.any((k) => lower.contains(k))) return ContentType.anime;

    return ContentType.general;
  }

  static MediaKind _detectMediaKind(String name) {
    final lower = name.toLowerCase();
    if (['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a'].any(lower.endsWith)) {
      return MediaKind.audio;
    }
    final tvPatterns = [
      RegExp(r'\bs\d{1,2}e\d{1,3}\b', caseSensitive: false),
      RegExp(r'\b\d{1,2}x\d{1,3}\b', caseSensitive: false),
      RegExp(
        r'\bseason[ ._-]*\d{1,2}[ ._-]*episode[ ._-]*\d{1,3}\b',
        caseSensitive: false,
      ),
    ];
    if (tvPatterns.any((p) => p.hasMatch(name))) return MediaKind.tv;
    return MediaKind.movie;
  }

  String get extension => fileName.split('.').last.toLowerCase();
  String get title => fileName.replaceAll('.$extension', '');
  String get libraryTitle {
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
        coverArtUrl: json['coverArtUrl'],
        description: json['description'],
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
  }) =>
      MediaFile(
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
      );
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

class PlaybackSettings {
  bool isMuted = false;
  double volume = 1.0;
  double playbackSpeed = 1.0;
  bool useOllamaTranslation = true;
  bool autoProcessNewMedia = true;
  bool enableIntro = true;
  bool enableMenuMusic = true; // New setting for background music
  String ollamaModel = 'qwen2.5:14b-instruct';
  TranslationProfile translationProfile = TranslationProfile.standard;
  bool isFullscreen = false;
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
        'ollamaModel': ollamaModel,
        'translationProfile': translationProfile.index,
        'isFullscreen': isFullscreen,
        'bookmarks': bookmarks,
      };

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) {
    final settings = PlaybackSettings();
    settings.isMuted = json['isMuted'] ?? false;
    settings.volume = json['volume'] ?? 1.0;
    settings.playbackSpeed = json['playbackSpeed'] ?? 1.0;
    settings.useOllamaTranslation = json['useOllamaTranslation'] ?? true;
    settings.autoProcessNewMedia = json['autoProcessNewMedia'] ?? true;
    settings.enableIntro = json['enableIntro'] ?? true;
    settings.enableMenuMusic = json['enableMenuMusic'] ?? true;
    settings.ollamaModel = json['ollamaModel'] ?? 'qwen2.5:14b-instruct';
    settings.translationProfile = json['translationProfile'] != null
        ? TranslationProfile.values[json['translationProfile']]
        : TranslationProfile.standard;
    settings.isFullscreen = json['isFullscreen'] ?? false;
    if (json['bookmarks'] != null) {
      settings.bookmarks = List<Map<String, String>>.from(
        (json['bookmarks'] as List).map((e) => Map<String, String>.from(e)),
      );
    }
    return settings;
  }
}
