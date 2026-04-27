import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/music_models.dart';

class LastFmService {
  final MusicProviderSettings settings;
  final String _baseUrl = 'https://ws.audioscrobbler.com/2.0/';

  LastFmService(this.settings);

  Future<String?> getArtistBio(String artistName) async {
    if (!settings.enableLastFm || settings.lastFmApiKey.isEmpty) return null;

    final url = '$_baseUrl?method=artist.getinfo&artist=${Uri.encodeComponent(artistName)}&api_key=${settings.lastFmApiKey}&format=json';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['artist']?['bio']?['content'];
      }
    } catch (e) {
      print('Last.fm Bio Error: $e');
    }
    return null;
  }

  Future<List<String>> getTrackTags(String artist, String track) async {
    if (!settings.enableLastFm || settings.lastFmApiKey.isEmpty) return [];

    final url = '$_baseUrl?method=track.gettoptags&artist=${Uri.encodeComponent(artist)}&track=${Uri.encodeComponent(track)}&api_key=${settings.lastFmApiKey}&format=json';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tags = data['toptags']?['tag'] as List?;
        return tags?.map((t) => t['name'] as String).toList() ?? [];
      }
    } catch (e) {
      print('Last.fm Tags Error: $e');
    }
    return [];
  }
}
