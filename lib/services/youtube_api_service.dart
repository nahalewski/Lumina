import 'dart:convert';
import 'dart:io';

/// Thin wrapper around the YouTube Data API v3.
/// All methods require a valid OAuth access token.
class YouTubeApiService {
  static const String _base = 'https://www.googleapis.com/youtube/v3';
  final _client = HttpClient();

  // ─── Feed / Home ────────────────────────────────────────────────────────────

  /// Fetches the authenticated user's subscription feed (recent uploads).
  /// Filters out Shorts (duration < 62 seconds).
  Future<List<YouTubeVideo>> getHomeFeed(String token,
      {String? pageToken}) async {
    // Step 1: get subscribed channels
    final subs = await _getSubscribedChannelIds(token);
    if (subs.isEmpty) return [];

    // Step 2: get recent uploads from each channel (parallel, capped at 6)
    final videos = <YouTubeVideo>[];
    final batches = _chunk(subs.take(24).toList(), 6);
    for (final batch in batches) {
      final results = await Future.wait(
        batch.map((channelId) => _getChannelUploads(token, channelId, max: 6)),
      );
      for (final list in results) {
        videos.addAll(list);
      }
    }

    // Sort by publishedAt descending, filter Shorts
    videos.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return videos.where((v) => !v.isShort).toList();
  }

  /// Fetches the authenticated user's watch history playlist.
  Future<List<YouTubeVideo>> getWatchHistory(String token,
      {String? pageToken}) async {
    // The watch history playlist ID is always "HL" for the authenticated user
    // We get it via channels.list mine=true
    try {
      final channelData = await _get(
          '$_base/channels?part=contentDetails&mine=true', token);
      final historyId = channelData['items']?[0]?['contentDetails']
          ?['relatedPlaylists']?['watchHistory'] as String?;
      if (historyId == null) return [];
      return _getPlaylistVideos(token, historyId,
          maxResults: 50, pageToken: pageToken);
    } catch (_) {
      return [];
    }
  }

  /// Fetches the authenticated user's subscriptions.
  Future<List<YouTubeChannel>> getSubscriptions(String token,
      {String? pageToken}) async {
    try {
      final params = 'part=snippet&mine=true&maxResults=50&order=alphabetical'
          '${pageToken != null ? '&pageToken=$pageToken' : ''}';
      final data = await _get('$_base/subscriptions?$params', token);
      final items = (data['items'] as List?) ?? [];
      return items.map((item) {
        final snippet = item['snippet'] as Map<String, dynamic>;
        return YouTubeChannel(
          id: (snippet['resourceId'] as Map)['channelId'] as String? ?? '',
          title: snippet['title'] as String? ?? '',
          thumbnailUrl: _bestThumbnail(snippet['thumbnails']),
          description: snippet['description'] as String? ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Search YouTube for videos. Shorts are filtered by duration < 62s.
  Future<List<YouTubeVideo>> search(String token, String query,
      {String? pageToken}) async {
    try {
      final params = 'part=snippet&type=video&q=${Uri.encodeComponent(query)}'
          '&maxResults=25&videoDuration=medium'  // medium = 4–20 min, excludes Shorts
          '${pageToken != null ? '&pageToken=$pageToken' : ''}';
      final data = await _get('$_base/search?$params', token);
      final items = (data['items'] as List?) ?? [];
      final ids = items
          .map((i) => (i['id'] as Map)['videoId'] as String?)
          .whereType<String>()
          .toList();
      if (ids.isEmpty) return [];
      return _getVideoDetails(token, ids);
    } catch (_) {
      return [];
    }
  }

  /// Fetch videos for a specific channel.
  Future<List<YouTubeVideo>> getChannelVideos(String token, String channelId,
      {String? pageToken}) async {
    return _getChannelUploads(token, channelId, max: 30, pageToken: pageToken);
  }

  // ─── Internal helpers ───────────────────────────────────────────────────────

  Future<List<String>> _getSubscribedChannelIds(String token) async {
    try {
      final data = await _get(
          '$_base/subscriptions?part=snippet&mine=true&maxResults=50', token);
      final items = (data['items'] as List?) ?? [];
      return items
          .map((i) =>
              (i['snippet']?['resourceId'] as Map?)?['channelId'] as String?)
          .whereType<String>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<YouTubeVideo>> _getChannelUploads(String token, String channelId,
      {int max = 10, String? pageToken}) async {
    try {
      // Get uploads playlist id
      final chData = await _get(
          '$_base/channels?part=contentDetails&id=$channelId', token);
      final uploadsId = chData['items']?[0]?['contentDetails']
          ?['relatedPlaylists']?['uploads'] as String?;
      if (uploadsId == null) return [];
      return _getPlaylistVideos(token, uploadsId,
          maxResults: max, pageToken: pageToken);
    } catch (_) {
      return [];
    }
  }

  Future<List<YouTubeVideo>> _getPlaylistVideos(
      String token, String playlistId,
      {int maxResults = 25, String? pageToken}) async {
    try {
      final params =
          'part=snippet,contentDetails&playlistId=$playlistId&maxResults=$maxResults'
          '${pageToken != null ? '&pageToken=$pageToken' : ''}';
      final data = await _get('$_base/playlistItems?$params', token);
      final items = (data['items'] as List?) ?? [];
      final ids = items
          .map((i) =>
              (i['contentDetails'] as Map?)?['videoId'] as String?)
          .whereType<String>()
          .toList();
      if (ids.isEmpty) return [];
      return _getVideoDetails(token, ids);
    } catch (_) {
      return [];
    }
  }

  Future<List<YouTubeVideo>> _getVideoDetails(
      String token, List<String> ids) async {
    try {
      final idParam = ids.take(50).join(',');
      final data = await _get(
          '$_base/videos?part=snippet,contentDetails,statistics&id=$idParam',
          token);
      final items = (data['items'] as List?) ?? [];
      return items
          .map((item) => YouTubeVideo.fromJson(item as Map<String, dynamic>))
          .where((v) => !v.isShort)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> _get(String url, String token) async {
    final request = await _client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 401) throw Exception('Unauthorized');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  String? _bestThumbnail(dynamic thumbnails) {
    if (thumbnails == null) return null;
    final t = thumbnails as Map<String, dynamic>;
    return (t['medium']?['url'] ?? t['default']?['url']) as String?;
  }

  List<List<T>> _chunk<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (int i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return chunks;
  }
}

// ─── Data models ─────────────────────────────────────────────────────────────

class YouTubeVideo {
  final String id;
  final String title;
  final String channelTitle;
  final String channelId;
  final String? thumbnailUrl;
  final DateTime publishedAt;
  final Duration duration;
  final int viewCount;
  final String? description;

  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.channelId,
    this.thumbnailUrl,
    required this.publishedAt,
    required this.duration,
    required this.viewCount,
    this.description,
  });

  String get url => 'https://www.youtube.com/watch?v=$id';
  String get thumbnailHq =>
      'https://i.ytimg.com/vi/$id/hqdefault.jpg';

  /// Shorts are videos under 62 seconds.
  bool get isShort => duration.inSeconds < 62;

  String get durationLabel {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get viewCountLabel {
    if (viewCount >= 1000000) {
      return '${(viewCount / 1000000).toStringAsFixed(1)}M views';
    }
    if (viewCount >= 1000) {
      return '${(viewCount / 1000).toStringAsFixed(0)}K views';
    }
    return '$viewCount views';
  }

  factory YouTubeVideo.fromJson(Map<String, dynamic> json) {
    final snippet = json['snippet'] as Map<String, dynamic>? ?? {};
    final contentDetails =
        json['contentDetails'] as Map<String, dynamic>? ?? {};
    final statistics = json['statistics'] as Map<String, dynamic>? ?? {};

    final thumbnails = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
    final thumbUrl = (thumbnails['maxres']?['url'] ??
        thumbnails['high']?['url'] ??
        thumbnails['medium']?['url'] ??
        thumbnails['default']?['url']) as String?;

    return YouTubeVideo(
      id: json['id'] as String? ?? '',
      title: snippet['title'] as String? ?? '',
      channelTitle: snippet['channelTitle'] as String? ?? '',
      channelId: snippet['channelId'] as String? ?? '',
      thumbnailUrl: thumbUrl,
      publishedAt: DateTime.tryParse(
              snippet['publishedAt'] as String? ?? '') ??
          DateTime.now(),
      duration: _parseDuration(contentDetails['duration'] as String? ?? ''),
      viewCount: int.tryParse(
              statistics['viewCount'] as String? ?? '0') ??
          0,
      description: snippet['description'] as String?,
    );
  }

  static Duration _parseDuration(String iso) {
    // PT4M13S, PT1H2M3S, PT45S
    final pattern = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
    final m = pattern.firstMatch(iso);
    if (m == null) return Duration.zero;
    return Duration(
      hours: int.tryParse(m.group(1) ?? '') ?? 0,
      minutes: int.tryParse(m.group(2) ?? '') ?? 0,
      seconds: int.tryParse(m.group(3) ?? '') ?? 0,
    );
  }
}

class YouTubeChannel {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final String description;

  const YouTubeChannel({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    required this.description,
  });
}
