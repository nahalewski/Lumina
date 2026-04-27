import 'dart:convert';
import 'package:http/http.dart' as http;
import 'cache_service.dart';

class MediaScraperService {
  final CacheService _cache = CacheService.instance;
  // ─────────────────────────────────────────────────────────────────────────────
  //                                TV MAZE
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchTvMaze(String query) async {
    try {
      final response = await http.get(Uri.parse(
        'https://api.tvmaze.com/search/shows?q=${Uri.encodeComponent(query)}'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        if (data.isNotEmpty) {
          final show = data[0]['show'];
          return {
            'title': show['name'],
            'posterUrl': show['image']?['original'],
            'description': show['summary'],
            'year': show['premiered']?.substring(0, 4),
            'rating': show['rating']?['average'],
            'status': show['status'],
            'genres': show['genres'] ?? [],
          };
        }
      }
    } catch (e) {
      print('TVMaze Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                JIKAN API (MyAnimeList)
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchJikan(String query) async {
    try {
      final response = await http.get(Uri.parse(
        'https://api.jikan.moe/v4/anime?q=${Uri.encodeComponent(query)}&limit=1'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['data'] as List;
        if (items.isNotEmpty) {
          final anime = items[0];
          return {
            'title': anime['title'],
            'titleEnglish': anime['title_english'],
            'posterUrl': anime['images']['jpg']['large_image_url'],
            'description': anime['synopsis'],
            'episodes': anime['episodes'],
            'score': anime['score'],
            'status': anime['status'],
            'genres': (anime['genres'] as List).map((g) => g['name']).toList(),
            'year': anime['year'],
          };
        }
      }
    } catch (e) {
      print('Jikan Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                SHIKIMORI
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchShikimori(String query) async {
    try {
      final response = await http.get(
        Uri.parse('https://shikimori.one/api/animes?search=${Uri.encodeComponent(query)}&limit=1'),
        headers: {'User-Agent': 'Lumina Media Player'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        if (data.isNotEmpty) {
          final anime = data[0];
          return {
            'title': anime['name'],
            'titleRussian': anime['russian'],
            'posterUrl': 'https://shikimori.one${anime['image']['original']}',
            'description': anime['description'],
            'score': anime['score'],
            'status': anime['status'],
            'episodes': anime['episodes'],
          };
        }
      }
    } catch (e) {
      print('Shikimori Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                WAIFU.PICS
  // ─────────────────────────────────────────────────────────────────────────────
  Future<String?> getRandomWaifu({String category = 'waifu'}) async {
    try {
      final response = await http.get(Uri.parse('https://api.waifu.pics/sfw/$category'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'];
      }
    } catch (e) {
      print('Waifu.pics Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                NEKOS.BEST
  // ─────────────────────────────────────────────────────────────────────────────
  Future<String?> getRandomNeko() async {
    try {
      final response = await http.get(Uri.parse('https://nekos.best/api/v2/neko'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['results'][0]['url'];
      }
    } catch (e) {
      print('Nekos.best Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                DANBOORU
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<String>> searchDanbooru(String tags, {int limit = 10}) async {
    try {
      final response = await http.get(Uri.parse(
        'https://danbooru.donmai.us/posts.json?tags=${Uri.encodeComponent(tags)}&limit=$limit'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data
            .where((p) => p['file_url'] != null)
            .map((p) => p['file_url'] as String)
            .toList();
      }
    } catch (e) {
      print('Danbooru Error: $e');
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                MANGAGDEX
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchMangaDex(String query) async {
    try {
      final response = await http.get(Uri.parse(
        'https://api.mangadex.org/manga?title=${Uri.encodeComponent(query)}&limit=1&includes[]=cover_art'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['data'] as List;
        if (results.isNotEmpty) {
          final manga = results[0];
          final cover = manga['relationships']
              .firstWhere((r) => r['type'] == 'cover_art', orElse: () => null);

          String? coverUrl;
          if (cover != null) {
            coverUrl = 'https://uploads.mangadex.org/covers/${manga['id']}/${cover['attributes']['fileName']}.512.jpg';
          }

          return {
            'title': manga['attributes']['title']['en'],
            'description': manga['attributes']['description']['en'],
            'posterUrl': coverUrl,
            'status': manga['attributes']['status'],
            'year': manga['attributes']['year'],
          };
        }
      }
    } catch (e) {
      print('MangaDex Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                TMDB (MOVIES / TV)
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchTmdb(String query, String apiKey, {String type = 'movie'}) async {
    try {
      final response = await http.get(Uri.parse(
        'https://api.themoviedb.org/3/search/$type?api_key=$apiKey&query=${Uri.encodeComponent(query)}'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;
        if (results.isNotEmpty) {
          final item = results[0];
          return {
            'title': item['title'] ?? item['name'],
            'posterUrl': 'https://image.tmdb.org/t/p/original${item['poster_path']}',
            'description': item['overview'],
            'rating': item['vote_average'],
            'releaseDate': item['release_date'] ?? item['first_air_date'],
          };
        }
      }
    } catch (e) {
      print('TMDB Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                OMDb API
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchOmdb(String query, String apiKey) async {
    try {
      final response = await http.get(Uri.parse(
        'https://www.omdbapi.com/?t=${Uri.encodeComponent(query)}&apikey=$apiKey'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['Response'] == 'True') {
          return {
            'title': data['Title'],
            'year': data['Year'],
            'posterUrl': data['Poster'],
            'rating': data['imdbRating'],
            'plot': data['Plot'],
            'genre': data['Genre'],
          };
        }
      }
    } catch (e) {
      print('OMDb Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                ANILIST
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchAniList(String query) async {
    try {
      final queryStr = '''
      query {
        Media(search: "$query", type: ANIME) {
          id
          title {
            romaji
            english
          }
          description
          coverImage {
            large
          }
          episodes
          averageScore
          status
        }
      }
      ''';

      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': queryStr}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final media = data['data']['Media'];
        return {
          'title': media['title']['english'] ?? media['title']['romaji'],
          'posterUrl': media['coverImage']['large'],
          'description': media['description'],
          'episodes': media['episodes'],
          'score': media['averageScore'] / 10,
          'status': media['status'],
        };
      }
    } catch (e) {
      print('AniList Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                KITSU
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchKitsu(String query) async {
    try {
      final response = await http.get(Uri.parse(
        'https://kitsu.io/api/edge/anime?filter[text]=${Uri.encodeComponent(query)}&page[limit]=1'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'].isNotEmpty) {
          final item = data['data'][0];
          return {
            'title': item['attributes']['canonicalTitle'],
            'posterUrl': item['attributes']['posterImage']['original'],
            'description': item['attributes']['synopsis'],
            'rating': item['attributes']['averageRating'],
            'episodeCount': item['attributes']['episodeCount'],
          };
        }
      }
    } catch (e) {
      print('Kitsu Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                LAST.FM
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchLastFm(String query, String apiKey) async {
    try {
      final response = await http.get(Uri.parse(
        'https://ws.audioscrobbler.com/2.0/?method=track.search&track=${Uri.encodeComponent(query)}&api_key=$apiKey&format=json'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tracks = data['results']['trackmatches']['track'] as List;
        if (tracks.isNotEmpty) {
          final track = tracks[0];
          return {
            'name': track['name'],
            'artist': track['artist'],
            'url': track['url'],
          };
        }
      }
    } catch (e) {
      print('Last.fm Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                MUSICBRAINZ
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchMusicBrainz(String query) async {
    try {
      final response = await http.get(
        Uri.parse('https://musicbrainz.org/ws/2/recording?query=${Uri.encodeComponent(query)}&fmt=json&limit=1'),
        headers: {'User-Agent': 'Lumina Media Player/1.0'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final recordings = data['recordings'] as List;
        if (recordings.isNotEmpty) {
          final recording = recordings[0];
          return {
            'title': recording['title'],
            'artist': recording['artist-credit'][0]['name'],
            'length': recording['length'],
          };
        }
      }
    } catch (e) {
      print('MusicBrainz Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                CONSUMET API
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchConsumet(String query, String baseUrl) async {
    try {
      final response = await http.get(Uri.parse(
        '$baseUrl/meta/anilist/${Uri.encodeComponent(query)}?page=1&perPage=1'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results'].isNotEmpty) {
          final item = data['results'][0];
          return {
            'title': item['title']['english'] ?? item['title']['romaji'],
            'posterUrl': item['image'],
            'description': item['description'],
            'totalEpisodes': item['totalEpisodes'],
            'rating': item['rating'],
            'type': item['type'],
          };
        }
      }
    } catch (e) {
      print('Consumet Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                UNIVERSAL SEARCH
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchAnyMedia(String filename) async {
    String cleanName = filename.split('.').first;
    cleanName = cleanName.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    final cached = await _cache.readJson<Map<String, dynamic>>('api', 'media-scraper:$cleanName');
    if (cached != null) return cached;

    // Try all scrapers in priority order
    final results = await Future.wait([
      searchJikan(cleanName),
      searchTvMaze(cleanName),
      searchShikimori(cleanName),
    ]);

    for (final result in results) {
      if (result != null) {
        await _cache.writeJson('api', 'media-scraper:$cleanName', result);
        return result;
      }
    }

    return null;
  }
}
