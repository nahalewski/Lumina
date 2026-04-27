import 'dart:convert';
import 'package:http/http.dart' as http;
import 'cache_service.dart';

class ActorMetadataService {
  final CacheService _cache = CacheService.instance;

  // ─────────────────────────────────────────────────────────────────────────────
  //                                WIKIDATA SPARQL
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getActorDetails(String actorName) async {
    final cached = await _cache.readJson<Map<String, dynamic>>('api', 'actor:$actorName');
    if (cached != null) return cached;
    try {
      final sparqlQuery = '''
      SELECT ?actor ?actorLabel ?image ?description ?birthDate ?birthPlace WHERE {
        ?actor wdt:P106 wd:Q33999;
               rdfs:label "${actorName.replaceAll('"', '\\"')}"@en.
        OPTIONAL { ?actor wdt:P18 ?image. }
        OPTIONAL { ?actor schema:description ?description. FILTER(LANG(?description) = "en") }
        OPTIONAL { ?actor wdt:P569 ?birthDate. }
        OPTIONAL { ?actor wdt:P19 ?birthPlace. ?birthPlace rdfs:label ?birthPlaceLabel. FILTER(LANG(?birthPlaceLabel) = "en") }
        SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
      }
      LIMIT 1
      ''';

      final response = await http.post(
        Uri.parse('https://query.wikidata.org/sparql'),
        headers: {
          'Accept': 'application/sparql-results+json',
          'User-Agent': 'Lumina Media Player/1.0',
        },
        body: {'query': sparqlQuery},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results']['bindings'] as List;
        
        if (results.isNotEmpty) {
          final item = results[0];
          final result = {
            'name': item['actorLabel']['value'],
            'imageUrl': item['image']?['value'],
            'description': item['description']?['value'],
            'birthDate': item['birthDate']?['value'],
            'birthPlace': item['birthPlaceLabel']?['value'],
            'wikidataId': item['actor']['value'].split('/').last,
          };
          await _cache.writeJson('api', 'actor:$actorName', result);
          return result;
        }
      }
    } catch (e) {
      print('Wikidata Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                GET FILMOGRAPHY
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getActorFilmography(String wikidataId) async {
    try {
      final sparqlQuery = '''
      SELECT ?work ?workLabel ?year ?character WHERE {
        wd:$wikidataId p:P1066 ?statement.
        ?statement ps:P1066 ?work.
        OPTIONAL { ?statement pq:P453 ?character. }
        OPTIONAL { ?work wdt:P577 ?date. BIND(YEAR(?date) AS ?year) }
        SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
      }
      ORDER BY DESC(?year)
      ''';

      final response = await http.post(
        Uri.parse('https://query.wikidata.org/sparql'),
        headers: {
          'Accept': 'application/sparql-results+json',
          'User-Agent': 'Lumina Media Player/1.0',
        },
        body: {'query': sparqlQuery},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results']['bindings'] as List;
        
        return results.map((item) => {
          'title': item['workLabel']['value'],
          'year': item['year']?['value'],
          'character': item['character']?['value'],
        }).toList();
      }
    } catch (e) {
      print('Wikidata Filmography Error: $e');
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                IMDB ACTOR SEARCH
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> searchActor(String query) async {
    try {
      final response = await http.get(Uri.parse(
        'https://v2.sg.media-imdb.com/suggestion/t/${Uri.encodeComponent(query)}.json'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['d'] as List;
        
        return results
            .where((item) => item['q'] == 'name')
            .map((item) => {
              'name': item['l'],
              'imdbId': item['id'],
              'imageUrl': item['i']?['imageUrl'],
            }).toList();
      }
    } catch (e) {
      print('IMDb Search Error: $e');
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                GET MOVIE CAST
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getMovieCast(String movieTitle) async {
    final cached = await _cache.readJson<List<dynamic>>('api', 'cast:$movieTitle');
    if (cached != null) {
      return cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    try {
      final sparqlQuery = '''
      SELECT ?actor ?actorLabel ?characterLabel ?image WHERE {
        ?work wdt:P31 wd:Q11424;
              rdfs:label "${movieTitle.replaceAll('"', '\\"')}"@en.
        ?work p:P161 ?castStatement.
        ?castStatement ps:P161 ?actor.
        OPTIONAL { ?castStatement pq:P453 ?character. }
        OPTIONAL { ?actor wdt:P18 ?image. }
        SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
      }
      LIMIT 50
      ''';

      final response = await http.post(
        Uri.parse('https://query.wikidata.org/sparql'),
        headers: {
          'Accept': 'application/sparql-results+json',
          'User-Agent': 'Lumina Media Player/1.0',
        },
        body: {'query': sparqlQuery},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results']['bindings'] as List;
        
        final cast = results.map((item) => {
          'name': item['actorLabel']['value'],
          'character': item['characterLabel']?['value'],
          'imageUrl': item['image']?['value'],
        }).toList();
        await _cache.writeJson('api', 'cast:$movieTitle', cast);
        return cast;
      }
    } catch (e) {
      print('Wikidata Cast Error: $e');
    }
    return [];
  }
}
