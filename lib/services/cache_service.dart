import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CacheService {
  static const Duration defaultTtl = Duration(hours: 24);
  static final CacheService instance = CacheService._();

  CacheService._();

  Future<Directory> get _cacheDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Directory>> get _cacheRoots async {
    final base = await getApplicationDocumentsDirectory();
    return [
      Directory(p.join(base.path, 'cache')),
      Directory(p.join(base.path, 'artwork_cache')),
    ];
  }

  String keyFor(String value) => sha1.convert(utf8.encode(value)).toString();

  Future<File> _jsonFile(String namespace, String key) async {
    final dir = Directory(p.join((await _cacheDir).path, namespace));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, '${keyFor(key)}.json'));
  }

  Future<T?> readJson<T>(String namespace, String key, {Duration ttl = defaultTtl}) async {
    final file = await _jsonFile(namespace, key);
    if (!await file.exists()) return null;
    final modified = await file.lastModified();
    if (DateTime.now().difference(modified) > ttl) return null;
    return jsonDecode(await file.readAsString()) as T;
  }

  Future<void> writeJson(String namespace, String key, Object? value) async {
    final file = await _jsonFile(namespace, key);
    await file.writeAsString(jsonEncode(value));
  }

  Future<String?> cachedArtworkPath(String url) async {
    if (url.isEmpty) return null;
    final ext = p.extension(Uri.parse(url).path).toLowerCase();
    final safeExt = ['.jpg', '.jpeg', '.png', '.webp'].contains(ext) ? ext : '.jpg';
    final dir = Directory(p.join((await _cacheDir).path, 'artwork'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, '${keyFor(url)}$safeExt'));
    if (await file.exists()) return file.path;

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> clearNamespace(String namespace) async {
    final dir = Directory(p.join((await _cacheDir).path, namespace));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<int> totalSizeBytes() async {
    var total = 0;
    for (final root in await _cacheRoots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    }
    return total;
  }

  Future<void> clearAll() async {
    for (final root in await _cacheRoots) {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  }
}
