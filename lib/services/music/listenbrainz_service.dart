import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/music_models.dart';

class ListenBrainzService {
  final MusicProviderSettings settings;
  final String _baseUrl = 'https://api.listenbrainz.org/1';

  ListenBrainzService(this.settings);

  Future<List<Map<String, dynamic>>> getRecommendations() async {
    if (!settings.enableListenBrainz || settings.lbUserToken.isEmpty) return [];

    // This is a simplified example of getting recommendations
    final url = '$_baseUrl/stats/user/${settings.mbUserAgent}/recommendations/top-recordings';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Token ${settings.lbUserToken}',
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['recommendations'] ?? []);
      }
    } catch (e) {
      print('ListenBrainz Recs Error: $e');
    }
    return [];
  }

  Future<void> submitListen(MusicTrack track) async {
    if (!settings.enableListenBrainz || settings.lbUserToken.isEmpty || !settings.lbEnableHistorySync) return;

    final url = '$_baseUrl/submit-listens';
    final body = {
      'listen_type': 'single',
      'payload': [
        {
          'track_metadata': {
            'artist_name': track.artistName,
            'track_name': track.title,
            'release_name': track.albumName,
          },
        }
      ],
    };

    try {
      await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Token ${settings.lbUserToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      print('ListenBrainz Submit Error: $e');
    }
  }
}
