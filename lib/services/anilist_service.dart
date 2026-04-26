import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class AnilistService {
  static const String _baseUrl = 'https://graphql.anilist.co';

  Future<Map<String, dynamic>?> searchHentai(String query) async {
    return _search(query, isAdult: true);
  }

  Future<Map<String, dynamic>?> searchAnime(String query) async {
    return _search(query, isAdult: false);
  }

  Future<Map<String, dynamic>?> _search(String query, {bool isAdult = false}) async {
    const String graphQLQuery = r'''
      query ($search: String, $isAdult: Boolean) {
        Page(page: 1, perPage: 1) {
          media(search: $search, type: ANIME, isAdult: $isAdult) {
            id
            title {
              romaji
              english
              native
            }
            coverImage {
              large
              extraLarge
            }
            bannerImage
            description
            seasonYear
            averageScore
            genres
            episodes
            status
            synonyms
          }
        }
      }
    ''';

    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'query': graphQLQuery,
          'variables': {
            'search': query,
            'isAdult': isAdult,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic>? media = data['data']?['Page']?['media'];
        if (media != null && media.isNotEmpty) {
          return media.first;
        }
      } else {
        debugPrint('AniList API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error searching AniList: $e');
    }
    return null;
  }
}
