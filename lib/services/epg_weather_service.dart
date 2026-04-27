import 'dart:convert';
import 'package:http/http.dart' as http;

class EpgWeatherService {

  // ─────────────────────────────────────────────────────────────────────────────
  //                                OPENWEATHER API
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getCurrentWeather(String apiKey, double lat, double lon) async {
    try {
      final response = await http.get(Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric'
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final weather = data['weather'][0];
        
        return {
          'condition': weather['main'],
          'description': weather['description'],
          'icon': weather['icon'],
          'temperature': data['main']['temp'],
          'humidity': data['main']['humidity'],
          'isRain': weather['id'] >= 500 && weather['id'] < 600,
          'isCloudy': weather['id'] >= 801,
          'isNight': DateTime.now().hour > 20 || DateTime.now().hour < 6,
        };
      }
    } catch (e) {
      print('OpenWeather Error: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                WEATHER PLAYLISTS
  // ─────────────────────────────────────────────────────────────────────────────
  List<String> getWeatherPlaylist(Map<String, dynamic> weather) {
    if (weather['isRain'] == true) {
      return [
        'rainy day movies',
        'cozy movies',
        'slow cinema',
        'atmospheric films',
        'classic noir',
      ];
    }
    if (weather['isNight'] == true) {
      return [
        'night movies',
        'midnight movies',
        'thrillers',
        'horror',
        'noir',
      ];
    }
    if (weather['isCloudy'] == true) {
      return [
        'cloudy day movies',
        'drama films',
        'indie movies',
        'coming of age',
      ];
    }
    return [
      'sunny day movies',
      'comedy',
      'adventure',
      'feel good movies',
      'action',
    ];
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                XMLTV EPG PARSER
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> parseXmltvData(String xmlContent) async {
    final programs = <Map<String, dynamic>>[];
    final regex = RegExp(
      r'<programme\s+start="([^"]+)"\s+stop="([^"]+)"\s+channel="([^"]+)"[^>]*>'
      r'(.*?)</programme>',
      dotAll: true,
      caseSensitive: false,
    );

    for (final match in regex.allMatches(xmlContent)) {
      final body = match.group(4) ?? '';
      programs.add({
        'channel': _decode(match.group(3) ?? ''),
        'start': _parseXmltvTime(match.group(1) ?? '').toIso8601String(),
        'end': _parseXmltvTime(match.group(2) ?? '').toIso8601String(),
        'title': _extractTag(body, 'title') ?? 'Unknown',
        'description': _extractTag(body, 'desc') ?? '',
        'category': _extractTag(body, 'category'),
      });
    }

    return programs;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                EPG SOURCE LOADER
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> loadEpgSource(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return await parseXmltvData(response.body);
      }
    } catch (e) {
      print('EPG Source Error: $e');
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //                                CURRENT CHANNEL PROGRAMS
  // ─────────────────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> getCurrentPrograms(List<Map<String, dynamic>> epgData) {
    final now = DateTime.now();
    return epgData.where((program) {
      final start = DateTime.parse(program['start']);
      final end = DateTime.parse(program['end']);
      return now.isAfter(start) && now.isBefore(end);
    }).toList();
  }

  DateTime _parseXmltvTime(String value) {
    final match = RegExp(r'^(\d{14})(?:\s*([+-]\d{4}))?').firstMatch(value);
    if (match == null) return DateTime.now();
    final raw = match.group(1)!;
    final base = DateTime(
      int.parse(raw.substring(0, 4)),
      int.parse(raw.substring(4, 6)),
      int.parse(raw.substring(6, 8)),
      int.parse(raw.substring(8, 10)),
      int.parse(raw.substring(10, 12)),
      int.parse(raw.substring(12, 14)),
    );
    final offset = match.group(2);
    if (offset == null) return base;
    final sign = offset.startsWith('-') ? -1 : 1;
    final hours = int.parse(offset.substring(1, 3));
    final minutes = int.parse(offset.substring(3, 5));
    return base.toUtc().subtract(Duration(hours: sign * hours, minutes: sign * minutes)).toLocal();
  }

  String? _extractTag(String body, String tag) {
    final match = RegExp('<$tag[^>]*>(.*?)</$tag>', dotAll: true, caseSensitive: false).firstMatch(body);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : _decode(value);
  }

  String _decode(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}
