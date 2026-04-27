import 'dart:convert';
import 'package:http/http.dart' as http;

class CoverArtArchiveService {
  final String _baseUrl = 'https://coverartarchive.org';

  Future<String?> getReleaseGroupCover(String mbid) async {
    final url = '$_baseUrl/release-group/$mbid';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final images = data['images'] as List;
        if (images.isNotEmpty) {
          return images.first['image'];
        }
      }
    } catch (e) {
      // Quietly fail as this is a fallback
    }
    return null;
  }

  Future<String?> getReleaseCover(String mbid) async {
    final url = '$_baseUrl/release/$mbid';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final images = data['images'] as List;
        if (images.isNotEmpty) {
          return images.first['image'];
        }
      }
    } catch (e) {
      // Quietly fail
    }
    return null;
  }
}
