import 'dart:convert';
import 'package:http/http.dart' as http;
import 'cache_service.dart';

class SubtitleScraperService {
  final CacheService _cache = CacheService.instance;
  // API Scraper toggle state
  Map<String, bool> enabledScrapers = {
    'opensubtitles': true,
    'subscene': true,
    'yifysubtitles': true,
    'addic7ed': false,
    'subtitleseeker': false,
  };

  // ─────────────────────────────────────────────────────────────────────────────
  //                                OPENSUBTITLES
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> searchOpenSubtitles(String query) async {
    if (!enabledScrapers['opensubtitles']!) return [];

    try {
      final response = await http.get(Uri.parse(
        'https://api.opensubtitles.com/api/v1/subtitles?query=${Uri.encodeComponent(query)}'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['data'] as List;
        return results.map((sub) => {
          'name': sub['attributes']['release'],
          'language': sub['attributes']['language'],
          'downloadCount': sub['attributes']['download_count'],
          'rating': sub['attributes']['ratings'],
          'url': sub['attributes']['url'],
        }).toList();
      }
    } catch (e) {
      print('OpenSubtitles Error: $e');
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                YIFY SUBTITLES
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> searchYifySubtitles(String imdbId) async {
    if (!enabledScrapers['yifysubtitles']!) return [];

    try {
      final response = await http.get(Uri.parse(
        'https://yts-subs.com/api/v2/list_subtitles?imdb_id=$imdbId'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok') {
          final subs = data['subtitles'] as List;
          return subs.map((sub) => {
            'language': sub['language'],
            'rating': sub['rating'],
            'url': sub['url'],
            'format': sub['format'],
          }).toList();
        }
      }
    } catch (e) {
      print('YIFY Subtitles Error: $e');
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                SUBSCENE
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> searchSubscene(String query) async {
    if (!enabledScrapers['subscene']!) return [];

    try {
      final response = await http.get(Uri.parse(
        'https://subscene.com/subtitles/searchbytitle?query=${Uri.encodeComponent(query)}'
      ));

      if (response.statusCode == 200) {
        // Parse HTML response and extract subtitles
        // Note: Full implementation requires HTML parser
        return [];
      }
    } catch (e) {
      print('Subscene Error: $e');
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                ADDIC7ED
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> searchAddic7ed(String show, int season, int episode) async {
    if (!enabledScrapers['addic7ed']!) return [];

    try {
      final response = await http.get(Uri.parse(
        'https://www.addic7ed.com/ajax_getEpisodesSearch.php?show=$show&season=$season'
      ));

      if (response.statusCode == 200) {
        return [];
      }
    } catch (e) {
      print('Addic7ed Error: $e');
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                SUBTITLE SEEKER
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> searchSubtitleSeeker(String query) async {
    if (!enabledScrapers['subtitleseeker']!) return [];

    try {
      final response = await http.get(Uri.parse(
        'https://subtitleseeker.in/api/search?q=${Uri.encodeComponent(query)}'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return [];
      }
    } catch (e) {
      print('Subtitle Seeker Error: $e');
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                UNIVERSAL SEARCH
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> searchAll(String query, {String? imdbId}) async {
    final cacheKey = 'subtitles:$query:${imdbId ?? ''}:$enabledScrapers';
    final cached = await _cache.readJson<List<dynamic>>('api', cacheKey);
    if (cached != null) {
      return cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final List<Map<String, dynamic>> allResults = [];

    final results = await Future.wait([
      searchOpenSubtitles(query),
      if (imdbId != null) searchYifySubtitles(imdbId),
      searchSubscene(query),
    ]);

    for (final list in results) {
      allResults.addAll(list);
    }

    // Sort by rating / relevance
    allResults.sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));
    await _cache.writeJson('api', cacheKey, allResults);

    return allResults;
  }

  void toggleScraper(String name, bool enabled) {
    if (enabledScrapers.containsKey(name)) {
      enabledScrapers[name] = enabled;
    }
  }

  bool isScraperEnabled(String name) {
    return enabledScrapers[name] ?? false;
  }
}
