import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'cache_service.dart';

enum IptvType { live, movie, series }

class IptvMedia {
  final String name;
  final String logo;
  final String url;
  final String group;
  final IptvType type;
  final String? tvgId;
  final String? tvgName;
  final DateTime? addedDate;

  IptvMedia({
    required this.name,
    required this.logo,
    required this.url,
    required this.group,
    this.type = IptvType.live,
    this.tvgId,
    this.tvgName,
    this.addedDate,
  });

  bool get isLive => type == IptvType.live;
  bool get isMovie => type == IptvType.movie;
  bool get isSeries => type == IptvType.series;

  IptvMedia copyWith({
    String? name,
    String? logo,
    String? url,
    String? group,
    IptvType? type,
    String? tvgId,
    String? tvgName,
    DateTime? addedDate,
  }) {
    return IptvMedia(
      name: name ?? this.name,
      logo: logo ?? this.logo,
      url: url ?? this.url,
      group: group ?? this.group,
      type: type ?? this.type,
      tvgId: tvgId ?? this.tvgId,
      tvgName: tvgName ?? this.tvgName,
      addedDate: addedDate ?? this.addedDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'logo': logo,
        'url': url,
        'group': group,
        'type': type.index,
        'tvgId': tvgId,
        'tvgName': tvgName,
        'addedDate': addedDate?.toIso8601String(),
      };

  factory IptvMedia.fromJson(Map<String, dynamic> json) => IptvMedia(
        name: json['name'] as String? ?? 'Unknown Media',
        logo: json['logo'] as String? ?? '',
        url: json['url'] as String? ?? '',
        group: json['group'] as String? ?? 'General',
        type: IptvType.values[json['type'] as int? ?? 0],
        tvgId: json['tvgId'] as String?,
        tvgName: json['tvgName'] as String?,
        addedDate: DateTime.tryParse(json['addedDate'] as String? ?? ''),
      );
}

class EpgEntry {
  final String channelId;
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;

  EpgEntry({
    required this.channelId,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
  });

  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'title': title,
        'description': description,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      };

  factory EpgEntry.fromJson(Map<String, dynamic> json) => EpgEntry(
        channelId: json['channelId'] as String? ?? '',
        title: json['title'] as String? ?? 'Unknown',
        description: json['description'] as String? ?? '',
        start:
            DateTime.tryParse(json['start'] as String? ?? '') ?? DateTime.now(),
        end: DateTime.tryParse(json['end'] as String? ?? '') ?? DateTime.now(),
      );
}

class IptvService {
  static const String _envServer = String.fromEnvironment('IPTV_SERVER');
  static const String _envPort = String.fromEnvironment('IPTV_PORT');
  static const String _envUsername = String.fromEnvironment('IPTV_USERNAME');
  static const String _envPassword = String.fromEnvironment('IPTV_PASSWORD');

  static String get defaultServer => _readStaticEnv('IPTV_SERVER', _envServer);
  static String get defaultPort =>
      _readStaticEnv('IPTV_PORT', _envPort, fallback: '443');
  static String get defaultUsername =>
      _readStaticEnv('IPTV_USERNAME', _envUsername);
  static String get defaultPassword =>
      _readStaticEnv('IPTV_PASSWORD', _envPassword);

  late String _server = _readEnv('IPTV_SERVER', _envServer);
  late String _port = _readEnv('IPTV_PORT', _envPort, fallback: '443');
  late String _username = _readEnv('IPTV_USERNAME', _envUsername);
  late String _password = _readEnv('IPTV_PASSWORD', _envPassword);

  /// Persistent HTTP client with cookie support
  final http.Client _client = http.Client();
  final CacheService _cache = CacheService.instance;

  String get server => _server;
  String get port => _port;
  String get username => _username;
  String get password => _password;

  String _readEnv(String key, String dartDefineValue, {String fallback = ''}) {
    return _readStaticEnv(key, dartDefineValue, fallback: fallback);
  }

  static String _readStaticEnv(String key, String dartDefineValue,
      {String fallback = ''}) {
    if (dartDefineValue.isNotEmpty) return dartDefineValue;
    return Platform.environment[key] ?? fallback;
  }

  void updateCredentials({
    required String server,
    required String port,
    required String username,
    required String password,
  }) {
    _server = server;
    _port = port;
    _username = username;
    _password = password;
  }

  /// M3U URL from the provider
  String get m3uUrl =>
      "https://$_server:$_port/get.php?username=$_username&password=$_password&type=m3u_plus&output=hls";

  /// Alternative M3U URL without output=hls
  String get m3uUrlAlt =>
      "https://$_server:$_port/get.php?username=$_username&password=$_password&type=m3u_plus";

  String get epgUrl =>
      "https://$_server:$_port/xmltv.php?username=$_username&password=$_password";

  String get playerApiUrl =>
      "https://$_server:$_port/player_api.php?username=$_username&password=$_password";

  /// Full browser-like headers to bypass Cloudflare bot protection
  Map<String, String> get _browserHeaders => {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate',
        'Referer': 'https://$_server/',
        'Connection': 'keep-alive',
        'DNT': '1',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Sec-Ch-Ua':
            '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
        'Sec-Ch-Ua-Mobile': '?0',
        'Sec-Ch-Ua-Platform': '"macOS"',
      };

  /// Check if the IPTV server is reachable
  Future<bool> checkServerReachable() async {
    try {
      final url = m3uUrl;
      final response = await _client
          .get(Uri.parse(url), headers: _browserHeaders)
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      print("IPTV server not reachable: $e");
      return false;
    }
  }

  /// Fetch and parse the M3U playlist
  Future<List<IptvMedia>> fetchMedia({bool forceRefresh = false}) async {
    final cacheKey = 'media:$_server:$_port:$_username';
    if (!forceRefresh) {
      final cached = await _cache.readJson<List<dynamic>>('iptv', cacheKey);
      if (cached != null) {
        return cached
            .map((e) => IptvMedia.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    }
    try {
      // Try primary URL first with overall timeout
      String content =
          await _fetchUrl(m3uUrl).timeout(const Duration(seconds: 40));
      if (content.isEmpty) {
        // Try alternative URL
        print("IPTV: Primary URL returned empty, trying alternative...");
        content =
            await _fetchUrl(m3uUrlAlt).timeout(const Duration(seconds: 40));
      }
      if (content.isEmpty) {
        print("IPTV: Both URLs returned empty content");
        return [];
      }
      // Validate content (check for #EXTM3U)
      if (!content.trim().startsWith('#EXTM3U')) {
        print("IPTV: Invalid M3U content received. Possibly blocked by VPN or redirected.");
        if (content.length > 200) {
          print("IPTV Content Snippet: ${content.substring(0, 200)}");
        } else {
          print("IPTV Content: $content");
        }
        return [];
      }
      final parsed = await _enrichWithXtreamArtwork(_parseM3U(content));
      await _cache.writeJson(
          'iptv', cacheKey, parsed.map((e) => e.toJson()).toList());
      return parsed;
    } on TimeoutException {
      print("IPTV: Fetch timed out");
    } catch (e) {
      print("Error fetching IPTV media: $e");
    }
    return [];
  }

  Future<List<IptvMedia>> _enrichWithXtreamArtwork(
      List<IptvMedia> media) async {
    try {
      final cacheKey = 'xtream_artwork:$_server:$_port:$_username';
      final cached =
          await _cache.readJson<Map<String, dynamic>>('iptv', cacheKey);
      final artwork = cached ?? await _fetchXtreamArtworkMap();
      if (cached == null && artwork.isNotEmpty) {
        await _cache.writeJson('iptv', cacheKey, artwork);
      }
      if (artwork.isEmpty) return media;

      return media.map((item) {
        if (item.logo.trim().isNotEmpty) return item;
        final keys = <String>[
          _normalizeArtworkKey(item.name),
          if (item.tvgName != null) _normalizeArtworkKey(item.tvgName!),
          _normalizeArtworkKey(_seriesNameFromEpisode(item.name, item.group)),
        ];
        for (final key in keys) {
          final logo = artwork[key];
          if (logo is String && logo.trim().isNotEmpty) {
            return item.copyWith(logo: logo.trim());
          }
        }
        return item;
      }).toList();
    } catch (e) {
      print('IPTV: Xtream artwork enrichment failed: $e');
      return media;
    }
  }

  Future<Map<String, dynamic>> _fetchXtreamArtworkMap() async {
    final artwork = <String, dynamic>{};
    await _mergeXtreamArtwork(
      artwork,
      '$playerApiUrl&action=get_vod_streams',
      nameKeys: const ['name', 'title'],
      logoKeys: const ['stream_icon', 'cover', 'movie_image'],
    );
    await _mergeXtreamArtwork(
      artwork,
      '$playerApiUrl&action=get_series',
      nameKeys: const ['name', 'title'],
      logoKeys: const ['cover', 'cover_big', 'series_icon'],
    );
    return artwork;
  }

  Future<void> _mergeXtreamArtwork(
    Map<String, dynamic> artwork,
    String url, {
    required List<String> nameKeys,
    required List<String> logoKeys,
  }) async {
    final response = await _client
        .get(Uri.parse(url), headers: _browserHeaders)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200 || response.body.isEmpty) return;
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return;
    for (final item in decoded) {
      if (item is! Map) continue;
      final name = _firstString(item, nameKeys);
      final logo = _firstString(item, logoKeys);
      if (name == null || logo == null || logo.trim().isEmpty) continue;
      artwork[_normalizeArtworkKey(name)] = logo;
    }
  }

  String? _firstString(Map item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String _normalizeArtworkKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\bs\d{1,2}\s*e\d{1,3}\b'), '')
        .replaceAll(RegExp(r'\b\d{1,2}x\d{1,3}\b'), '')
        .replaceAll(RegExp(r'\bseason\s*\d+\b'), '')
        .replaceAll(RegExp(r'\bepisode\s*\d+\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  String _seriesNameFromEpisode(String name, String group) {
    final patterns = [
      RegExp(r'^(.+?)\s+S\d+\s*E\d+', caseSensitive: false),
      RegExp(r'^(.+?)\s+\d+x\d+', caseSensitive: false),
      RegExp(r'^(.+?)\s+Season\s*\d+\s*Episode\s*\d+', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(name);
      if (match != null) return match.group(1)!.trim();
    }
    return group;
  }

  /// Fetch a URL and return the body as a string
  Future<String> _fetchUrl(String url) async {
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: _browserHeaders,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      print("IPTV: Fetch error: $e");
    }
    return '';
  }

  List<IptvMedia> _parseM3U(String content) {
    final List<IptvMedia> mediaList = [];
    final lines = LineSplitter.split(content).toList();
    print("IPTV: Parsing ${lines.length} lines");

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('#EXTINF:')) {
        final metadata = lines[i];
        final nameMatch = RegExp(r',(.+)$').firstMatch(metadata);
        final logoMatch = RegExp(r'tvg-logo="([^"]+)"').firstMatch(metadata);
        final groupMatch =
            RegExp(r'group-title="([^"]+)"').firstMatch(metadata);
        final tvgIdMatch = RegExp(r'tvg-id="([^"]+)"').firstMatch(metadata);
        final tvgNameMatch = RegExp(r'tvg-name="([^"]+)"').firstMatch(metadata);
        final typeMatch = RegExp(r'tvg-type="([^"]+)"').firstMatch(metadata);

        final name = nameMatch?.group(1) ?? "Unknown Media";
        final logo = logoMatch?.group(1) ?? "";
        final group = groupMatch?.group(1) ?? "General";
        final tvgId = tvgIdMatch?.group(1);
        final tvgName = tvgNameMatch?.group(1);
        final typeStr = typeMatch?.group(1)?.toLowerCase() ?? "";

        if (i + 1 < lines.length) {
          final url = lines[i + 1];
          if (!url.startsWith('#')) {
            // Determine type
            IptvType type = IptvType.live;
            if (typeStr == 'movie' ||
                group.toLowerCase().contains('movie') ||
                group.toLowerCase().contains('vod')) {
              type = IptvType.movie;
            } else if (typeStr == 'series' ||
                group.toLowerCase().contains('series') ||
                group.toLowerCase().contains('tv shows')) {
              type = IptvType.series;
            } else if (url.contains('/movie/')) {
              type = IptvType.movie;
            } else if (url.contains('/series/')) {
              type = IptvType.series;
            } else if (!url.contains('/live/')) {
              // Heuristic: if it's not live, check extensions
              final lowerUrl = url.toLowerCase();
              if (lowerUrl.endsWith('.mp4') ||
                  lowerUrl.endsWith('.mkv') ||
                  lowerUrl.endsWith('.avi')) {
                type = IptvType.movie;
              }
            }

            // Fake an added date for "Recently Added" sorting (last 100 items are usually newer)
            // In a real app, you'd parse a 'added-date' tag if available.
            DateTime? addedDate;
            if (type != IptvType.live) {
              addedDate =
                  DateTime.now().subtract(Duration(minutes: mediaList.length));
            }

            mediaList.add(IptvMedia(
              name: name,
              logo: logo,
              url: url,
              group: group,
              type: type,
              tvgId: tvgId,
              tvgName: tvgName,
              addedDate: addedDate,
            ));
          }
        }
      }
    }
    return mediaList;
  }

  Future<List<EpgEntry>> fetchEpg({bool forceRefresh = false}) async {
    final cacheKey = 'epg:$_server:$_port:$_username';
    if (!forceRefresh) {
      final cached = await _cache.readJson<List<dynamic>>('epg', cacheKey);
      if (cached != null) {
        return cached
            .map((e) => EpgEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    }
    try {
      final url = epgUrl;
      final response =
          await _client.get(Uri.parse(url), headers: _browserHeaders);

      if (response.statusCode == 200) {
        String body;
        if (response.bodyBytes.length > 2 &&
            response.bodyBytes[0] == 0x1F &&
            response.bodyBytes[1] == 0x8B) {
          final decoded = gzip.decode(response.bodyBytes);
          body = utf8.decode(decoded);
        } else {
          body = response.body;
        }
        final parsed = _parseEpg(body);
        await _cache.writeJson(
            'epg', cacheKey, parsed.map((e) => e.toJson()).toList());
        return parsed;
      }
    } catch (e) {
      print("Error fetching EPG: $e");
    }
    return [];
  }

  List<EpgEntry> _parseEpg(String xml) {
    final List<EpgEntry> entries = [];
    try {
      final programRegex = RegExp(
        r'<programme\s+start="([^"]+)"\s+stop="([^"]+)"\s+channel="([^"]+)"\s*>'
        r'.*?<title[^>]*>(.*?)</title>'
        r'(?:.*?<desc[^>]*>(.*?)</desc>)?',
        dotAll: true,
      );
      final matches = programRegex.allMatches(xml);
      for (final match in matches) {
        try {
          entries.add(EpgEntry(
            channelId: match.group(3) ?? '',
            title: match.group(4)?.trim() ?? 'Unknown',
            description: match.group(5)?.trim() ?? '',
            start: _parseEpgTime(match.group(1) ?? ''),
            end: _parseEpgTime(match.group(2) ?? ''),
          ));
        } catch (e) {
          // Skip malformed entries
        }
      }
    } catch (e) {
      print("Error parsing EPG XML: $e");
    }
    return entries;
  }

  DateTime _parseEpgTime(String time) {
    try {
      final cleaned = time.split(' ')[0];
      return DateTime.parse(
        '${cleaned.substring(0, 4)}-'
        '${cleaned.substring(4, 6)}-'
        '${cleaned.substring(6, 8)} '
        '${cleaned.substring(8, 10)}:'
        '${cleaned.substring(10, 12)}:'
        '${cleaned.substring(12, 14)}',
      );
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Save a debug log to the user's desktop with the raw HTTP response
  Future<String> saveDebugLog() async {
    final log = StringBuffer();
    log.writeln("=== IPTV Debug Log ===");
    log.writeln("Generated: ${DateTime.now()}");
    log.writeln("");

    // Log credentials (mask password)
    log.writeln("Server: $_server");
    log.writeln("Port: $_port");
    log.writeln("Username: $_username");
    log.writeln("");

    // Test primary URL
    log.writeln("--- Primary M3U URL ---");
    log.writeln("URL: $m3uUrl");
    try {
      final response = await http
          .get(Uri.parse(m3uUrl), headers: _browserHeaders)
          .timeout(const Duration(seconds: 30));
      log.writeln("HTTP Status: ${response.statusCode}");
      log.writeln("Response Body (${response.body.length} bytes):");
      log.writeln(response.body.substring(
          0, response.body.length > 5000 ? 5000 : response.body.length));
    } catch (e) {
      log.writeln("ERROR: $e");
    }

    // Write to desktop
    final home = Platform.environment['HOME'] ?? '/tmp';
    final actualPath =
        "$home/Desktop/iptv_debug_${DateTime.now().millisecondsSinceEpoch}.txt";
    await File(actualPath).writeAsString(log.toString());
    return actualPath;
  }
}
