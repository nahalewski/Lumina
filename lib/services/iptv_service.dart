import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

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
}

class IptvService {
  // Default hardcoded credentials
  static const String defaultServer = 'primevip.day';
  static const String defaultPort = '443';
  static const String defaultUsername = '258389404';
  static const String defaultPassword = '046347913';


  String _server = defaultServer;
  String _port = defaultPort;
  String _username = defaultUsername;
  String _password = defaultPassword;

  /// Persistent HTTP client with cookie support
  final http.Client _client = http.Client();

  String get server => _server;
  String get port => _port;
  String get username => _username;
  String get password => _password;

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

  /// Full browser-like headers to bypass Cloudflare bot protection
  Map<String, String> get _browserHeaders => {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'gzip, deflate',
    'Referer': 'https://primevip.day/',
    'Connection': 'keep-alive',
    'DNT': '1',
    'Upgrade-Insecure-Requests': '1',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-User': '?1',
    'Sec-Ch-Ua': '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
    'Sec-Ch-Ua-Mobile': '?0',
    'Sec-Ch-Ua-Platform': '"macOS"',
  };


  /// Check if the IPTV server is reachable
  Future<bool> checkServerReachable() async {
    try {
      final url = m3uUrl;
      final response = await _client.get(Uri.parse(url), headers: _browserHeaders).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      print("IPTV server not reachable: $e");
      return false;
    }
  }


  /// Fetch and parse the M3U playlist
  Future<List<IptvMedia>> fetchMedia() async {
    try {
      // Try primary URL first with overall timeout
      String content = await _fetchUrl(m3uUrl).timeout(const Duration(seconds: 40));
      if (content.isEmpty) {
        // Try alternative URL
        print("IPTV: Primary URL returned empty, trying alternative...");
        content = await _fetchUrl(m3uUrlAlt).timeout(const Duration(seconds: 40));
      }
      if (content.isEmpty) {
        print("IPTV: Both URLs returned empty content");
        return [];
      }
      return _parseM3U(content);
    } on TimeoutException {
      print("IPTV: Fetch timed out");
    } catch (e) {
      print("Error fetching IPTV media: $e");
    }
    return [];
  }

  /// Fetch a URL and return the body as a string
  Future<String> _fetchUrl(String url) async {
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: _browserHeaders,
      ).timeout(const Duration(seconds: 30));

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
        final groupMatch = RegExp(r'group-title="([^"]+)"').firstMatch(metadata);
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
              if (lowerUrl.endsWith('.mp4') || lowerUrl.endsWith('.mkv') || lowerUrl.endsWith('.avi')) {
                type = IptvType.movie;
              }
            }

            // Fake an added date for "Recently Added" sorting (last 100 items are usually newer)
            // In a real app, you'd parse a 'added-date' tag if available.
            DateTime? addedDate;
            if (type != IptvType.live) {
              addedDate = DateTime.now().subtract(Duration(minutes: mediaList.length));
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

  Future<List<EpgEntry>> fetchEpg() async {
    try {
      final url = epgUrl;
      final response = await _client.get(Uri.parse(url), headers: _browserHeaders);

      if (response.statusCode == 200) {
        String body;
        if (response.bodyBytes.length > 2 && response.bodyBytes[0] == 0x1F && response.bodyBytes[1] == 0x8B) {
          final decoded = gzip.decode(response.bodyBytes);
          body = utf8.decode(decoded);
        } else {
          body = response.body;
        }
        return _parseEpg(body);
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
      final response = await http.get(Uri.parse(m3uUrl), headers: _browserHeaders).timeout(const Duration(seconds: 30));
      log.writeln("HTTP Status: ${response.statusCode}");
      log.writeln("Response Body (${response.body.length} bytes):");
      log.writeln(response.body.substring(0, response.body.length > 5000 ? 5000 : response.body.length));
    } catch (e) {
      log.writeln("ERROR: $e");
    }

    // Write to desktop
    final home = Platform.environment['HOME'] ?? '/tmp';
    final actualPath = "$home/Desktop/iptv_debug_${DateTime.now().millisecondsSinceEpoch}.txt";
    await File(actualPath).writeAsString(log.toString());
    return actualPath;
  }
}
