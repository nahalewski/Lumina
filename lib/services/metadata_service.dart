import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/media_model.dart';
import 'anilist_service.dart';

/// Service to identify local media and enrich it from public metadata sources.
class MetadataService {
  static const String _jikanBaseUrl = 'https://api.jikan.moe/v4';
  static const String _tmdbBaseUrl = 'https://api.themoviedb.org/3';
  static const String _tmdbImageBaseUrl = 'https://image.tmdb.org/t/p/w780';

  String get _tmdbApiKey => _envValue('TMDB_API_KEY');
  String get _tmdbAccessToken => _envValue('TMDB_READ_ACCESS_TOKEN');

  final AnilistService _anilistService = AnilistService();

  String _envValue(String key) {
    final defined = String.fromEnvironment(key);
    if (defined.isNotEmpty) return defined;
    return Platform.environment[key] ?? dotenv.env[key] ?? '';
  }

  /// Search for anime by title and return the best match
  Future<Map<String, dynamic>?> searchAnime(String query) async {
    try {
      // Clean query (remove extension, S01E01, etc.)
      final cleanQuery = _sanitizeQuery(query);
      if (cleanQuery.isEmpty) return null;

      final url = Uri.parse(
        '$_jikanBaseUrl/anime?q=${Uri.encodeComponent(cleanQuery)}&limit=1',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data'].isNotEmpty) {
          return data['data'][0];
        }
      }
    } catch (e) {
      print('Error searching anime: $e');
    }
    return null;
  }

  /// Sanitize filename to get a clean title for search
  String _sanitizeQuery(String query) {
    // Remove common scene tags and extensions
    String result = query.replaceAll(
      RegExp(r'\.(mp4|mkv|avi|mov|webm|ts|m4v|flv|wmv|mpg|mpeg|vob)$', caseSensitive: false),
      '',
    );
    result = result.replaceAll(RegExp(r'\[.*?\]'), ''); // Remove [SubGroup]
    result = result.replaceAll(RegExp(r'\(.*?\)'), ''); // Remove (Year)
    result = result.replaceAll(
      RegExp(r'\bS\d+E\d+\b', caseSensitive: false),
      '',
    ); // Remove S01E01
    result = result.replaceAll(
      RegExp(
        r'\b(h264|x264|hevc|x265|1080p|720p|2160p|4k|bluray|multi|sub|dub|web-dl|webrip|brrip|hdtv|internal|proper|repack)\b',
        caseSensitive: false,
      ),
      '',
    );
    result = result.replaceAll(
      RegExp(r'[\._\-]'),
      ' ',
    ); // Replace separators with spaces
    
    // Remove trailing junk characters like ( or [ that might be left over
    result = result.replaceAll(RegExp(r'[\[\(\]\)]'), ' ');
    
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Apply metadata to a MediaFile
  Future<MediaFile> enrichMediaFile(MediaFile file) async {
    final parsed = parseEpisodeInfoFromFileName(file.fileName);
    final inferredKind = parsed.episode != null ? MediaKind.tv : file.mediaKind;
    final localFile = _applyLocalMetadata(file, parsed, inferredKind);

    if ((_tmdbApiKey.isNotEmpty || _tmdbAccessToken.isNotEmpty) &&
        inferredKind != MediaKind.audio) {
      final tmdb = inferredKind == MediaKind.tv
          ? await _searchTmdbTv(
              localFile,
              localFile.showTitle ?? localFile.animeTitle ?? localFile.title,
              parsed,
            )
          : await _searchTmdbMovie(
              localFile,
              localFile.movieTitle ?? localFile.title,
            );
      if (tmdb != null) return tmdb;
    }

    if (localFile.contentType == ContentType.adult) {
      final hentai = await _anilistService.searchHentai(file.fileName);
      if (hentai != null) {
        return localFile.copyWith(
          metadataId: 'anilist:${hentai['id']}',
          animeTitle: hentai['title']['english'] ?? hentai['title']['romaji'],
          showTitle: localFile.showTitle ??
              hentai['title']['english'] ??
              hentai['title']['romaji'],
          mediaKind: inferredKind,
          coverArtUrl: hentai['coverImage']['extraLarge'] ??
              hentai['coverImage']['large'],
          posterUrl: hentai['coverImage']['extraLarge'] ??
              hentai['coverImage']['large'],
          backdropUrl: hentai['bannerImage'],
          description:
              hentai['description']?.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ''),
          synopsis:
              hentai['description']?.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ''),
          releaseYear: hentai['seasonYear'],
          rating: (hentai['averageScore'] as num?)?.toDouble() != null
              ? (hentai['averageScore'] as num?)!.toDouble() / 10.0
              : null,
          genres: (hentai['genres'] as List?)?.cast<String>(),
          season: localFile.season,
          episode: localFile.episode,
        );
      }
    }

    if (localFile.contentType != ContentType.anime) return localFile;

    final anime = await searchAnime(file.fileName);
    if (anime == null) {
      // Fallback to AniList for non-Hentai anime if Jikan fails
      final anilist = await _anilistService.searchAnime(file.fileName);
      if (anilist != null) {
        return localFile.copyWith(
          metadataId: 'anilist:${anilist['id']}',
          animeTitle: anilist['title']['english'] ?? anilist['title']['romaji'],
          showTitle: localFile.showTitle ??
              anilist['title']['english'] ??
              anilist['title']['romaji'],
          mediaKind: inferredKind,
          coverArtUrl: anilist['coverImage']['extraLarge'] ??
              anilist['coverImage']['large'],
          posterUrl: anilist['coverImage']['extraLarge'] ??
              anilist['coverImage']['large'],
          backdropUrl: anilist['bannerImage'],
          description: anilist['description']
              ?.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ''),
          synopsis: anilist['description']
              ?.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ''),
          releaseYear: anilist['seasonYear'],
          rating: (anilist['averageScore'] as num?)?.toDouble() != null
              ? (anilist['averageScore'] as num?)!.toDouble() / 10.0
              : null,
          genres: (anilist['genres'] as List?)?.cast<String>(),
          season: localFile.season,
          episode: localFile.episode,
        );
      }
      return localFile;
    }

    return localFile.copyWith(
      animeId: anime['mal_id'].toString(),
      animeTitle: anime['title_english'] ?? anime['title'],
      showTitle:
          localFile.showTitle ?? anime['title_english'] ?? anime['title'],
      mediaKind: inferredKind,
      coverArtUrl: anime['images']['webp']['large_image_url'],
      posterUrl: anime['images']['webp']['large_image_url'],
      description: anime['synopsis'],
      synopsis: anime['synopsis'],
      releaseYear: anime['year'],
      rating: (anime['score'] as num?)?.toDouble(),
      genres: _names(anime['genres']),
      season: localFile.season,
      episode: localFile.episode,
    );
  }

  MediaFile _applyLocalMetadata(
    MediaFile file,
    ParsedEpisodeInfo parsed,
    MediaKind inferredKind,
  ) {
    final yearMatch = RegExp(
      r'\b(19\d{2}|20\d{2})\b',
    ).firstMatch(file.fileName);
    final resolutionMatch = RegExp(
      r'\b(480p|720p|1080p|2160p|4k)\b',
      caseSensitive: false,
    ).firstMatch(file.fileName);
    final language = RegExp(
      r'\b(eng|english|jpn|japanese|spa|spanish|fre|french|multi)\b',
      caseSensitive: false,
    ).firstMatch(file.fileName)?.group(1)?.toUpperCase();

    return file.copyWith(
      mediaKind: inferredKind,
      showTitle: file.showTitle ?? parsed.showTitle,
      movieTitle: inferredKind == MediaKind.movie
          ? file.movieTitle ?? _movieTitleFromFile(file.fileName)
          : file.movieTitle,
      episodeTitle: file.episodeTitle ?? parsed.episodeTitle,
      season: file.season ?? parsed.season,
      episode: file.episode ?? parsed.episode,
      releaseYear: file.releaseYear ?? int.tryParse(yearMatch?.group(1) ?? ''),
      resolution: file.resolution ?? resolutionMatch?.group(1)?.toUpperCase(),
      language: file.language ?? language,
    );
  }

  String _movieTitleFromFile(String fileName) {
    return _sanitizeQuery(fileName);
  }

  Future<MediaFile?> _searchTmdbMovie(MediaFile file, String query) async {
    try {
      final year = file.releaseYear;
      final url = Uri.parse(
        '$_tmdbBaseUrl/search/movie?${_tmdbQueryParameters({
              'query': query,
              'include_adult': 'false',
              if (year != null) 'primary_release_year': year.toString(),
            })}',
      );
      final response = await http.get(
        url,
        headers: _tmdbHeaders(),
      );
      if (response.statusCode != 200) return null;
      final results = jsonDecode(response.body)['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final movie = results.first as Map<String, dynamic>;
      final details = await _tmdbDetails('movie', movie['id']);
      return _applyTmdbMovie(file, movie, details);
    } catch (e) {
      print('Error searching TMDB movie: $e');
      return null;
    }
  }

  Future<MediaFile?> _searchTmdbTv(
    MediaFile file,
    String query,
    ParsedEpisodeInfo parsed,
  ) async {
    try {
      final year = file.releaseYear;
      final url = Uri.parse(
        '$_tmdbBaseUrl/search/tv?${_tmdbQueryParameters({
              'query': query,
              if (year != null) 'first_air_date_year': year.toString(),
            })}',
      );
      final response = await http.get(
        url,
        headers: _tmdbHeaders(),
      );
      if (response.statusCode != 200) return null;
      final results = jsonDecode(response.body)['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final show = results.first as Map<String, dynamic>;
      final showDetails = await _tmdbDetails('tv', show['id']);
      Map<String, dynamic>? episodeDetails;
      if (parsed.season != null && parsed.episode != null) {
        final episodeUrl = Uri.parse(
          '$_tmdbBaseUrl/tv/${show['id']}/season/${parsed.season}/episode/${parsed.episode}?${_tmdbQueryParameters({
                'append_to_response': 'credits'
              })}',
        );
        final episodeResponse = await http.get(
          episodeUrl,
          headers: _tmdbHeaders(),
        );
        if (episodeResponse.statusCode == 200) {
          episodeDetails =
              jsonDecode(episodeResponse.body) as Map<String, dynamic>;
        }
      }
      return _applyTmdbTv(file, show, showDetails, episodeDetails);
    } catch (e) {
      print('Error searching TMDB TV: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _tmdbDetails(String type, dynamic id) async {
    final url = Uri.parse(
      '$_tmdbBaseUrl/$type/$id?${_tmdbQueryParameters({
            'append_to_response': 'credits,videos'
          })}',
    );
    final response = await http.get(
      url,
      headers: _tmdbHeaders(),
    );
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  List<String> _names(dynamic items) {
    if (items is! List) return const [];
    return items
        .map((item) => item is Map ? item['name']?.toString() : null)
        .whereType<String>()
        .take(8)
        .toList();
  }

  MediaFile _applyTmdbMovie(
    MediaFile file,
    Map<String, dynamic> movie,
    Map<String, dynamic>? details,
  ) {
    final credits = details?['credits'] as Map<String, dynamic>?;
    final crew =
        (credits?['crew'] as List?)?.whereType<Map>().toList() ?? const [];
    final videos =
        (details?['videos']?['results'] as List?)?.whereType<Map>().toList() ??
            const [];
    return file.copyWith(
      mediaKind: MediaKind.movie,
      metadataId: 'tmdb:${movie['id']}',
      movieTitle: movie['title'] ?? movie['original_title'],
      synopsis: movie['overview'],
      posterUrl: _image(movie['poster_path']),
      backdropUrl: _image(movie['backdrop_path']),
      releaseDate: movie['release_date'],
      releaseYear: _year(movie['release_date']),
      rating: (movie['vote_average'] as num?)?.toDouble(),
      genres: _names(details?['genres']),
      cast: _names((credits?['cast'] as List?)?.take(10).toList()),
      directors: crew
          .where((p) => p['job'] == 'Director')
          .map((p) => p['name'].toString())
          .toList(),
      writers: crew
          .where((p) => p['job'] == 'Writer' || p['job'] == 'Screenplay')
          .map((p) => p['name'].toString())
          .toList(),
      trailerUrl: _trailer(videos),
    );
  }

  MediaFile _applyTmdbTv(
    MediaFile file,
    Map<String, dynamic> show,
    Map<String, dynamic>? showDetails,
    Map<String, dynamic>? episodeDetails,
  ) {
    final credits = showDetails?['credits'] as Map<String, dynamic>?;
    final crew =
        (episodeDetails?['crew'] as List?)?.whereType<Map>().toList() ??
            const [];
    final videos = (showDetails?['videos']?['results'] as List?)
            ?.whereType<Map>()
            .toList() ??
        const [];
    return file.copyWith(
      mediaKind: MediaKind.tv,
      metadataId: 'tmdb:${show['id']}',
      showTitle: show['name'] ?? show['original_name'],
      episodeTitle: episodeDetails?['name'] ?? file.episodeTitle,
      synopsis: episodeDetails?['overview'] ?? show['overview'],
      posterUrl: _image(show['poster_path']),
      backdropUrl: _image(show['backdrop_path']),
      thumbnailUrl: _image(episodeDetails?['still_path']),
      seasonPosterUrl: _seasonPoster(showDetails, file.season),
      releaseDate: show['first_air_date'],
      airDate: episodeDetails?['air_date'],
      releaseYear: _year(show['first_air_date']),
      rating: (episodeDetails?['vote_average'] as num?)?.toDouble() ??
          (show['vote_average'] as num?)?.toDouble(),
      genres: _names(showDetails?['genres']),
      cast: _names((credits?['cast'] as List?)?.take(10).toList()),
      directors: crew
          .where((p) => p['job'] == 'Director')
          .map((p) => p['name'].toString())
          .toList(),
      writers: crew
          .where((p) => p['job'] == 'Writer' || p['job'] == 'Screenplay')
          .map((p) => p['name'].toString())
          .toList(),
      trailerUrl: _trailer(videos),
    );
  }

  String? _seasonPoster(Map<String, dynamic>? details, int? season) {
    final seasons = details?['seasons'];
    if (seasons is! List || season == null) return null;
    final match = seasons.whereType<Map>().firstWhere(
          (item) => item['season_number'] == season,
          orElse: () => const {},
        );
    return _image(match['poster_path']);
  }

  String? _image(dynamic path) =>
      (path == null || (path is String && path.isEmpty)) ? null : '$_tmdbImageBaseUrl$path';

  Map<String, String> _tmdbHeaders() {
    if (_tmdbAccessToken.isNotEmpty) {
      return {
        'Authorization': 'Bearer $_tmdbAccessToken',
        'accept': 'application/json',
      };
    }
    return {'accept': 'application/json'};
  }

  String _tmdbQueryParameters(Map<String, String> values) {
    final params = {
      ...values,
      if (_tmdbApiKey.isNotEmpty) 'api_key': _tmdbApiKey,
    };
    return params.entries
        .map((entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
  }

  int? _year(dynamic date) => date is String && date.length >= 4
      ? int.tryParse(date.substring(0, 4))
      : null;
  String? _trailer(List<Map> videos) {
    final trailer = videos.cast<Map?>().firstWhere(
          (video) => video?['site'] == 'YouTube' && video?['type'] == 'Trailer',
          orElse: () => null,
        );
    final key = trailer?['key'];
    return key == null ? null : 'https://www.youtube.com/watch?v=$key';
  }

  /// Fetch poster for an IPTV media item
  Future<String?> fetchIptvPoster(String name, {bool isSeries = false}) async {
    try {
      final query = _sanitizeQuery(name);
      if (query.isEmpty) return null;

      final type = isSeries ? 'tv' : 'movie';
      final url = Uri.parse(
        '$_tmdbBaseUrl/search/$type?${_tmdbQueryParameters({
              'query': query,
              'include_adult': 'false',
            })}',
      );
      final response = await http.get(url, headers: _tmdbHeaders());
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final posterPath = data['results'][0]['poster_path'];
          if (posterPath != null) {
            return '$_tmdbImageBaseUrl$posterPath';
          }
        }
      }
    } catch (e) {
      print('Error fetching IPTV poster: $e');
    }
    return null;
  }
}
