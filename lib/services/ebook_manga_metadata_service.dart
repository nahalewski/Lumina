import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cache_service.dart';

enum DocumentLibraryType { ebooks, manga, comics }

class DocumentMetadata {
  final String? title;
  final String? series;
  final List<String> authors;
  final String? summary;
  final String? coverUrl;
  final String? localCoverPath;
  final List<String> tags;
  final double? rating;
  final String? source;
  final String? volume;
  final String? chapter;
  final String? isbn;
  final String? publisher;
  final List<String> writers;
  final List<String> artists;
  final String? detailUrl;

  const DocumentMetadata({
    this.title,
    this.series,
    this.authors = const [],
    this.summary,
    this.coverUrl,
    this.localCoverPath,
    this.tags = const [],
    this.rating,
    this.source,
    this.volume,
    this.chapter,
    this.isbn,
    this.publisher,
    this.writers = const [],
    this.artists = const [],
    this.detailUrl,
  });

  bool get hasUsefulData =>
      title != null ||
      series != null ||
      summary != null ||
      coverUrl != null ||
      localCoverPath != null ||
      authors.isNotEmpty ||
      writers.isNotEmpty ||
      artists.isNotEmpty ||
      publisher != null ||
      tags.isNotEmpty ||
      rating != null;

  DocumentMetadata merge(DocumentMetadata other) {
    return DocumentMetadata(
      title: title ?? other.title,
      series: series ?? other.series,
      authors: authors.isNotEmpty ? authors : other.authors,
      summary: summary ?? other.summary,
      coverUrl: coverUrl ?? other.coverUrl,
      localCoverPath: localCoverPath ?? other.localCoverPath,
      tags: tags.isNotEmpty ? tags : other.tags,
      rating: rating ?? other.rating,
      source: source ?? other.source,
      volume: volume ?? other.volume,
      chapter: chapter ?? other.chapter,
      isbn: isbn ?? other.isbn,
      publisher: publisher ?? other.publisher,
      writers: writers.isNotEmpty ? writers : other.writers,
      artists: artists.isNotEmpty ? artists : other.artists,
      detailUrl: detailUrl ?? other.detailUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'series': series,
        'authors': authors,
        'summary': summary,
        'coverUrl': coverUrl,
        'localCoverPath': localCoverPath,
        'tags': tags,
        'rating': rating,
        'source': source,
        'volume': volume,
        'chapter': chapter,
        'isbn': isbn,
        'publisher': publisher,
        'writers': writers,
        'artists': artists,
        'detailUrl': detailUrl,
      };

  factory DocumentMetadata.fromJson(Map<String, dynamic> json) =>
      DocumentMetadata(
        title: json['title'] as String?,
        series: json['series'] as String?,
        authors: List<String>.from(json['authors'] ?? const []),
        summary: json['summary'] as String?,
        coverUrl: json['coverUrl'] as String?,
        localCoverPath: json['localCoverPath'] as String?,
        tags: List<String>.from(json['tags'] ?? const []),
        rating: (json['rating'] as num?)?.toDouble(),
        source: json['source'] as String?,
        volume: json['volume'] as String?,
        chapter: json['chapter'] as String?,
        isbn: json['isbn'] as String?,
        publisher: json['publisher'] as String?,
        writers: List<String>.from(json['writers'] ?? const []),
        artists: List<String>.from(json['artists'] ?? const []),
        detailUrl: json['detailUrl'] as String?,
      );
}

abstract class DocumentMetadataProvider {
  String get key;
  String get label;
  bool get supportsBooks => false;
  bool get supportsManga => false;
  bool get supportsComics => false;

  Future<List<DocumentMetadata>> searchByTitle(String title);
  Future<List<DocumentMetadata>> searchByISBN(String isbn) async => const [];
  Future<List<DocumentMetadata>> searchBySeries(String series) =>
      searchByTitle(series);
  Future<String?> getCover(DocumentMetadata metadata) async =>
      metadata.coverUrl;
  Future<DocumentMetadata?> getMetadata(String id) async => null;
  Future<double?> getRatings(DocumentMetadata metadata) async =>
      metadata.rating;
}

class EbookMangaMetadataService {
  static final EbookMangaMetadataService instance =
      EbookMangaMetadataService._();

  EbookMangaMetadataService._()
      : _providers = [
          GoogleBooksMetadataProvider(),
          OpenLibraryCoversMetadataProvider(),
          OpenLibraryMetadataProvider(),
          ProjectGutenbergMetadataProvider(),
          MangaDexMetadataProvider(),
          JikanMetadataProvider(),
          MetaChanMetadataProvider(),
          MangaVerseMetadataProvider(),
          ComicVineMetadataProvider(),
        ];

  final List<DocumentMetadataProvider> _providers;
  final CacheService _cache = CacheService.instance;

  Future<DocumentMetadata> enrichFile(
    File file, {
    required bool isManga,
    bool isComics = false,
    bool forceRefresh = false,
    required Map<String, bool> providerToggles,
  }) async {
    final stat = await file.stat();
    final cacheKey =
        '${file.path}:${stat.modified.millisecondsSinceEpoch}:metadata-v3';
    if (!forceRefresh) {
      final cached = await _cache.readJson<Map<String, dynamic>>(
        'document_metadata',
        cacheKey,
      );
      if (cached != null) return DocumentMetadata.fromJson(cached);
    }

    final embeddedMetadata = await _extractEmbeddedMetadata(file);
    var metadata = embeddedMetadata.merge(_metadataFromFilename(file.path));
    final lookupText = metadata.series ?? metadata.title;

    if (lookupText != null && lookupText.trim().isNotEmpty) {
      for (final provider in _providers) {
        if (!(providerToggles[provider.key] ?? false)) continue;
        if (isComics && !provider.supportsComics) continue;
        if (isManga && !provider.supportsManga) continue;
        if (!isManga && !isComics && !provider.supportsBooks) continue;
        try {
          var matches = <DocumentMetadata>[];
          if (!isManga &&
              !isComics &&
              metadata.isbn != null &&
              metadata.isbn!.trim().isNotEmpty) {
            matches = await provider
                .searchByISBN(metadata.isbn!)
                .timeout(const Duration(seconds: 12));
          }
          if (matches.isEmpty) {
            matches = await provider
                .searchByTitle(lookupText)
                .timeout(const Duration(seconds: 12));
          }
          if (matches.isNotEmpty) {
            final shouldPreferProvider = isComics ||
                (!isManga &&
                    !isComics &&
                    embeddedMetadata.title == null &&
                    embeddedMetadata.isbn == null);
            metadata = shouldPreferProvider
                ? matches.first.merge(metadata)
                : metadata.merge(matches.first);
            if (metadata.coverUrl != null && metadata.localCoverPath == null) {
              final coverPath =
                  await _cache.cachedArtworkPath(metadata.coverUrl!);
              if (coverPath != null) {
                metadata = metadata.merge(
                  DocumentMetadata(localCoverPath: coverPath),
                );
              }
            }
            if (metadata.summary != null && metadata.coverUrl != null) break;
          }
        } catch (_) {}
      }
    }

    await _cache.writeJson('document_metadata', cacheKey, metadata.toJson());
    return metadata;
  }

  Future<void> organizeDocumentFiles(
    String rootPath,
    Map<String, bool> providerToggles,
    DocumentLibraryType type,
  ) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return;

    final isManga = type == DocumentLibraryType.manga;
    final isComics = type == DocumentLibraryType.comics;
    final isEbooks = type == DocumentLibraryType.ebooks;

    final files = await root
        .list(recursive: false)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) {
          final ext = p.extension(file.path).toLowerCase();
          if (isManga || isComics) {
            return ['.cbz', '.cbr', '.pdf', '.jpg', '.jpeg', '.png', '.webp', '.zip', '.rar'].contains(ext);
          } else {
            return ['.epub', '.pdf', '.mobi', '.azw3', '.txt', '.md'].contains(ext);
          }
        })
        .toList();

    for (final file in files) {
      final metadata = await enrichFile(
        file,
        isManga: isManga,
        isComics: isComics,
        providerToggles: providerToggles,
      );

      String? folderName;

      if (isManga || isComics) {
        folderName = metadata.series;
        if (folderName == null || folderName.trim().isEmpty) {
          final title = metadata.title ?? p.basenameWithoutExtension(file.path);
          final match = RegExp(
            r'^(.*?)(?:\s+v(?:ol(?:ume)?)?\.?\s*\d+)?(?:\s+ch(?:apter)?\.?\s*\d+)?(?:\s+#\d+)?$',
            caseSensitive: false,
          ).firstMatch(title.replaceAll(RegExp(r'[_\.]+'), ' '));
          folderName = match?.group(1)?.trim() ?? title.trim();
        }
      } else if (isEbooks) {
        // Prefer Series, then Author
        folderName = metadata.series;
        if (folderName == null || folderName.trim().isEmpty) {
          if (metadata.authors.isNotEmpty) {
            folderName = metadata.authors.first;
          } else {
            folderName = metadata.title ?? p.basenameWithoutExtension(file.path);
          }
        }
      }

      if (folderName == null || folderName.trim().isEmpty) continue;

      // Sanitize folder name
      folderName = folderName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
      if (folderName!.isEmpty) continue;

      final targetDir = Directory(p.join(rootPath, folderName));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final targetPath = p.join(targetDir.path, p.basename(file.path));
      if (file.path != targetPath) {
        try {
          await file.rename(targetPath);
        } catch (e) {
          await file.copy(targetPath);
          await file.delete();
        }
      }
    }
  }

  Future<List<DocumentMetadata>> searchByTitle(
    String title, {
    required bool isManga,
    required Map<String, bool> providerToggles,
  }) =>
      _search((provider) => provider.searchByTitle(title), isManga,
          providerToggles);

  Future<List<DocumentMetadata>> searchByISBN(
    String isbn, {
    required Map<String, bool> providerToggles,
  }) =>
      _search(
          (provider) => provider.searchByISBN(isbn), false, providerToggles);

  Future<List<DocumentMetadata>> searchBySeries(
    String series, {
    required bool isManga,
    required Map<String, bool> providerToggles,
  }) =>
      _search((provider) => provider.searchBySeries(series), isManga,
          providerToggles);

  Future<List<DocumentMetadata>> _search(
    Future<List<DocumentMetadata>> Function(DocumentMetadataProvider provider)
        action,
    bool isManga,
    Map<String, bool> providerToggles, {
    bool isComics = false,
  }) async {
    final results = <DocumentMetadata>[];
    for (final provider in _providers) {
      if (!(providerToggles[provider.key] ?? false)) continue;
      if (isComics && !provider.supportsComics) continue;
      if (isManga && !provider.supportsManga) continue;
      if (!isManga && !isComics && !provider.supportsBooks) continue;
      try {
        results.addAll(await action(provider));
      } catch (_) {}
    }
    return results;
  }

  Future<DocumentMetadata> _extractEmbeddedMetadata(File file) async {
    final lower = file.path.toLowerCase();
    if (lower.endsWith('.cbz') || lower.endsWith('.epub')) {
      try {
        final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
        final xmlEntry = archive.files.where((entry) {
          final name = entry.name.toLowerCase();
          return lower.endsWith('.cbz')
              ? name.endsWith('comicinfo.xml')
              : name.endsWith('.opf');
        }).firstOrNull;
        final xml = xmlEntry == null
            ? null
            : utf8.decode(xmlEntry.content as List<int>, allowMalformed: true);
        final coverPath = await _extractFirstImageCover(file.path, archive);
        final parsed =
            lower.endsWith('.cbz') ? _parseComicInfo(xml) : _parseEpubOpf(xml);
        return parsed.merge(DocumentMetadata(localCoverPath: coverPath));
      } catch (_) {}
    }
    return const DocumentMetadata();
  }

  Future<String?> _extractFirstImageCover(
      String sourcePath, Archive archive) async {
    final image = archive.files.where((entry) {
      final name = entry.name.toLowerCase();
      return entry.isFile &&
          (name.endsWith('.jpg') ||
              name.endsWith('.jpeg') ||
              name.endsWith('.png') ||
              name.endsWith('.webp'));
    }).firstOrNull;
    if (image == null) return null;
    final ext =
        p.extension(image.name).isEmpty ? '.jpg' : p.extension(image.name);
    final digest = sha1.convert(utf8.encode('$sourcePath:${image.name}'));
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'cache', 'document_covers'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final out = File(p.join(dir.path, '$digest$ext'));
    if (!await out.exists()) {
      await out.writeAsBytes(image.content as List<int>);
    }
    return out.path;
  }

  DocumentMetadata _parseComicInfo(String? xml) {
    if (xml == null || xml.isEmpty) return const DocumentMetadata();
    final tags = _tag(xml, 'Genre')
        ?.split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    return DocumentMetadata(
      title: _tag(xml, 'Title'),
      series: _tag(xml, 'Series'),
      authors: [
        if (_tag(xml, 'Writer') != null) _tag(xml, 'Writer')!,
        if (_tag(xml, 'Penciller') != null) _tag(xml, 'Penciller')!,
      ],
      summary: _tag(xml, 'Summary'),
      tags: tags ?? const [],
      volume: _tag(xml, 'Volume'),
      chapter: _tag(xml, 'Number'),
    );
  }

  DocumentMetadata _parseEpubOpf(String? xml) {
    if (xml == null || xml.isEmpty) return const DocumentMetadata();
    return DocumentMetadata(
      title: _tag(xml, 'dc:title') ?? _tag(xml, 'title'),
      authors: [
        if (_tag(xml, 'dc:creator') != null) _tag(xml, 'dc:creator')!,
      ],
      summary: _tag(xml, 'dc:description') ?? _tag(xml, 'description'),
      isbn: _isbnFromText(xml),
    );
  }

  DocumentMetadata _metadataFromFilename(String path) {
    final name = p.basenameWithoutExtension(path);
    final seriesMatch = RegExp(
      r'^(.*?)(?:\s+v(?:ol(?:ume)?)?\.?\s*(\d+))?(?:\s+ch(?:apter)?\.?\s*(\d+))?$',
      caseSensitive: false,
    ).firstMatch(name.replaceAll(RegExp(r'[_\.]+'), ' '));
    return DocumentMetadata(
      title: name.replaceAll(RegExp(r'[_\.]+'), ' ').trim(),
      series: seriesMatch?.group(1)?.trim(),
      volume: seriesMatch?.group(2),
      chapter: seriesMatch?.group(3),
      isbn: _isbnFromText(name),
    );
  }

  String? _tag(String xml, String tag) {
    final match =
        RegExp('<$tag[^>]*>(.*?)</$tag>', caseSensitive: false, dotAll: true)
            .firstMatch(xml);
    if (match == null) return null;
    return _decodeXml(match.group(1)!.trim()).trim();
  }

  String _decodeXml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  String? _isbnFromText(String text) {
    final match =
        RegExp(r'(97[89][-\s]?)?\d[-\s]?\d{2,5}[-\s]?\d{2,7}[-\s]?[\dXx]')
            .firstMatch(text);
    return match?.group(0)?.replaceAll(RegExp(r'[\s-]'), '');
  }
}

class GoogleBooksMetadataProvider extends DocumentMetadataProvider {
  @override
  String get key => 'googleBooks';
  @override
  String get label => 'Google Books';
  @override
  bool get supportsBooks => true;

  String get _apiKey {
    const defined = String.fromEnvironment('GOOGLE_BOOKS_API_KEY');
    if (defined.isNotEmpty) return defined;
    return Platform.environment['GOOGLE_BOOKS_API_KEY'] ??
        dotenv.env['GOOGLE_BOOKS_API_KEY'] ??
        '';
  }

  @override
  Future<List<DocumentMetadata>> searchByTitle(String title) async {
    final params = {
      'q': 'intitle:$title',
      'maxResults': '5',
      if (_apiKey.isNotEmpty) 'key': _apiKey,
    };
    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', params);
    return _parse(await http.get(uri));
  }

  @override
  Future<List<DocumentMetadata>> searchByISBN(String isbn) async {
    final params = {
      'q': 'isbn:$isbn',
      'maxResults': '5',
      if (_apiKey.isNotEmpty) 'key': _apiKey,
    };
    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', params);
    return _parse(await http.get(uri));
  }

  List<DocumentMetadata> _parse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) return [];
    final items = (jsonDecode(response.body)['items'] as List?) ?? const [];
    return items.map((item) {
      final info = Map<String, dynamic>.from(item['volumeInfo'] ?? const {});
      final images = Map<String, dynamic>.from(info['imageLinks'] ?? const {});
      return DocumentMetadata(
        title: info['title'] as String?,
        authors: List<String>.from(info['authors'] ?? const []),
        summary: info['description'] as String?,
        coverUrl: (images['extraLarge'] ??
            images['large'] ??
            images['medium'] ??
            images['thumbnail']) as String?,
        tags: List<String>.from(info['categories'] ?? const []),
        rating: (info['averageRating'] as num?)?.toDouble(),
        source: label,
      );
    }).toList();
  }
}

class OpenLibraryCoversMetadataProvider extends DocumentMetadataProvider {
  @override
  String get key => 'openLibraryCovers';
  @override
  String get label => 'Open Library Covers';
  @override
  bool get supportsBooks => true;

  @override
  Future<List<DocumentMetadata>> searchByTitle(String title) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'title': title,
      'limit': '5',
      'fields': 'title,author_name,isbn,cover_i,cover_edition_key,subject',
    });
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) return [];
    final docs = (jsonDecode(response.body)['docs'] as List?) ?? const [];
    return docs
        .map((doc) {
          final data = Map<String, dynamic>.from(doc as Map);
          final isbn = (data['isbn'] as List?)?.firstOrNull?.toString();
          final coverId = data['cover_i']?.toString();
          final olid = data['cover_edition_key']?.toString();
          return DocumentMetadata(
            title: data['title'] as String?,
            authors: List<String>.from(data['author_name'] ?? const []),
            isbn: isbn,
            coverUrl: _coverUrl(isbn: isbn, coverId: coverId, olid: olid),
            tags:
                List<String>.from(data['subject'] ?? const []).take(8).toList(),
            source: label,
          );
        })
        .where((metadata) => metadata.coverUrl != null)
        .toList();
  }

  @override
  Future<List<DocumentMetadata>> searchByISBN(String isbn) async {
    final clean = isbn.replaceAll(RegExp(r'[\s-]'), '');
    if (clean.isEmpty) return const [];
    return [
      DocumentMetadata(
        isbn: clean,
        coverUrl: _coverUrl(isbn: clean),
        source: label,
      ),
    ];
  }

  String? _coverUrl({String? isbn, String? coverId, String? olid}) {
    if (coverId != null && coverId.isNotEmpty) {
      return 'https://covers.openlibrary.org/b/id/$coverId-L.jpg';
    }
    if (isbn != null && isbn.isNotEmpty) {
      return 'https://covers.openlibrary.org/b/isbn/$isbn-L.jpg';
    }
    if (olid != null && olid.isNotEmpty) {
      return 'https://covers.openlibrary.org/b/olid/$olid-L.jpg';
    }
    return null;
  }
}

class OpenLibraryMetadataProvider extends DocumentMetadataProvider {
  @override
  String get key => 'openLibrary';
  @override
  String get label => 'Open Library';
  @override
  bool get supportsBooks => true;

  @override
  Future<List<DocumentMetadata>> searchByTitle(String title) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'title': title,
      'limit': '5',
    });
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) return [];
    final docs = (jsonDecode(response.body)['docs'] as List?) ?? const [];
    return docs.map((doc) {
      final data = Map<String, dynamic>.from(doc as Map);
      final coverId = data['cover_i'];
      return DocumentMetadata(
        title: data['title'] as String?,
        authors: List<String>.from(data['author_name'] ?? const []),
        coverUrl: coverId == null
            ? null
            : 'https://covers.openlibrary.org/b/id/$coverId-L.jpg',
        tags: List<String>.from(data['subject'] ?? const []).take(8).toList(),
        source: label,
      );
    }).toList();
  }
}

class ProjectGutenbergMetadataProvider extends DocumentMetadataProvider {
  @override
  String get key => 'projectGutenberg';
  @override
  String get label => 'Project Gutenberg';
  @override
  bool get supportsBooks => true;

  @override
  Future<List<DocumentMetadata>> searchByTitle(String title) async {
    final uri = Uri.https('gutendex.com', '/books', {'search': title});
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) return [];
    final results = (jsonDecode(response.body)['results'] as List?) ?? const [];
    return results.take(5).map((item) {
      final data = Map<String, dynamic>.from(item as Map);
      final formats = Map<String, dynamic>.from(data['formats'] ?? const {});
      final authors = (data['authors'] as List? ?? const [])
          .map((a) => Map<String, dynamic>.from(a as Map)['name'].toString())
          .toList();
      return DocumentMetadata(
        title: data['title'] as String?,
        authors: authors,
        coverUrl: formats['image/jpeg'] as String?,
        tags: List<String>.from(data['subjects'] ?? const []).take(8).toList(),
        source: label,
      );
    }).toList();
  }
}

class MangaDexMetadataProvider extends DocumentMetadataProvider {
  @override
  String get key => 'mangaDex';
  @override
  String get label => 'MangaDex';
  @override
  bool get supportsManga => true;

  @override
  Future<List<DocumentMetadata>> searchByTitle(String title) async {
    final uri = Uri.https('api.mangadex.org', '/manga', {
      'title': title,
      'limit': '5',
      'includes[]': ['cover_art', 'author', 'artist'],
    });
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) return [];
    final results = (jsonDecode(response.body)['data'] as List?) ?? const [];
    return results.map((item) {
      final data = Map<String, dynamic>.from(item as Map);
      final id = data['id'] as String?;
      final attrs = Map<String, dynamic>.from(data['attributes'] ?? const {});
      final titleMap = Map<String, dynamic>.from(attrs['title'] ?? const {});
      final descMap =
          Map<String, dynamic>.from(attrs['description'] ?? const {});
      
      final relationships = List<Map<String, dynamic>>.from(data['relationships'] ?? const []);
      
      final authors = relationships
          .where((rel) => rel['type'] == 'author')
          .map((rel) => Map<String, dynamic>.from(rel['attributes'] ?? const {})['name'] as String?)
          .whereType<String>()
          .toList();
          
      final artists = relationships
          .where((rel) => rel['type'] == 'artist')
          .map((rel) => Map<String, dynamic>.from(rel['attributes'] ?? const {})['name'] as String?)
          .whereType<String>()
          .toList();

      final tags = (attrs['tags'] as List? ?? const [])
          .map((tag) {
            final tagAttrs = Map<String, dynamic>.from(
                (tag as Map)['attributes'] ?? const {});
            final name =
                Map<String, dynamic>.from(tagAttrs['name'] ?? const {});
            return (name['en'] ?? '').toString();
          })
          .where((tag) => tag.isNotEmpty)
          .toList();
          
      final cover = relationships.where((rel) => rel['type'] == 'cover_art').firstOrNull;
      final fileName = cover == null
          ? null
          : Map<String, dynamic>.from(cover['attributes'] ?? const {})['fileName'] as String?;
          
      return DocumentMetadata(
        title: (titleMap['en'] ?? titleMap.values.firstOrNull) as String?,
        series: (titleMap['en'] ?? titleMap.values.firstOrNull) as String?,
        authors: authors,
        artists: artists,
        summary: (descMap['en'] ?? descMap.values.firstOrNull) as String?,
        coverUrl: id == null || fileName == null
            ? null
            : 'https://uploads.mangadex.org/covers/$id/$fileName',
        tags: tags,
        source: label,
      );
    }).toList();
  }
}

class JikanMetadataProvider extends DocumentMetadataProvider {
  @override
  String get key => 'jikan';
  @override
  String get label => 'Jikan';
  @override
  bool get supportsManga => true;

  @override
  Future<List<DocumentMetadata>> searchByTitle(String title) async {
    final uri = Uri.https('api.jikan.moe', '/v4/manga', {
      'q': title,
      'limit': '5',
    });
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) return [];
    final results = (jsonDecode(response.body)['data'] as List?) ?? const [];
    return results.map((item) {
      final data = Map<String, dynamic>.from(item as Map);
      final images = Map<String, dynamic>.from(data['images'] ?? const {});
      final jpg = Map<String, dynamic>.from(images['jpg'] ?? const {});
      final authors = (data['authors'] as List? ?? const [])
          .map((a) => Map<String, dynamic>.from(a as Map)['name'].toString())
          .toList();
      final genres = (data['genres'] as List? ?? const [])
          .map((g) => Map<String, dynamic>.from(g as Map)['name'].toString())
          .toList();
      return DocumentMetadata(
        title: data['title'] as String?,
        series: data['title'] as String?,
        authors: authors,
        summary: data['synopsis'] as String?,
        coverUrl: (jpg['large_image_url'] ?? jpg['image_url']) as String?,
        tags: genres,
        rating: (data['score'] as num?)?.toDouble(),
        source: label,
      );
    }).toList();
  }
}

class MetaChanMetadataProvider extends DocumentMetadataProvider {
  @override
  String get key => 'metaChan';
  @override
  String get label => 'MetaChan';
  @override
  bool get supportsManga => true;

  @override
  Future<List<DocumentMetadata>> searchByTitle(String title) async => const [];
}

class MangaVerseMetadataProvider extends DocumentMetadataProvider {
  @override
  String get key => 'mangaVerse';
  @override
  String get label => 'MangaVerse';
  @override
  bool get supportsManga => true;

  @override
  Future<List<DocumentMetadata>> searchByTitle(String title) async => const [];
}

class ComicVineMetadataProvider extends DocumentMetadataProvider {
  @override
  String get key => 'comicVine';
  @override
  String get label => 'Comic Vine';
  @override
  bool get supportsComics => true;

  String get _apiKey {
    const defined = String.fromEnvironment('COMIC_VINE_API_KEY');
    if (defined.isNotEmpty) return defined;
    return Platform.environment['COMIC_VINE_API_KEY'] ??
        dotenv.env['COMIC_VINE_API_KEY'] ??
        '';
  }

  @override
  Future<List<DocumentMetadata>> searchByTitle(String title) async {
    final key = _apiKey.trim();
    if (key.isEmpty) return const [];

    final uri = Uri.https('comicvine.gamespot.com', '/api/search/', {
      'api_key': key,
      'format': 'json',
      'resources': 'issue,volume',
      'query': title,
      'limit': '5',
      'field_list':
          'name,issue_number,cover_date,deck,description,image,volume,publisher,start_year,api_detail_url,site_detail_url',
    });
    final response = await http.get(
      uri,
      headers: const {
        HttpHeaders.userAgentHeader: 'LuminaMedia/1.0',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'];
    if (results is! List) return const [];

    final items = <DocumentMetadata>[];
    for (final raw in results.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final detail = await _issueDetail(item);
      items.add(_metadataFromComicVineItem(item, detail));
    }
    return items;
  }

  Future<Map<String, dynamic>?> _issueDetail(Map<String, dynamic> item) async {
    final detailUrl = item['api_detail_url']?.toString();
    final key = _apiKey.trim();
    if (detailUrl == null || detailUrl.isEmpty || key.isEmpty) return null;
    try {
      final uri = Uri.parse(detailUrl).replace(queryParameters: {
        'api_key': key,
        'format': 'json',
        'field_list':
            'name,issue_number,cover_date,deck,description,image,volume,publisher,person_credits,site_detail_url',
      });
      final response = await http.get(
        uri,
        headers: const {
          HttpHeaders.userAgentHeader: 'LuminaMedia/1.0',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'];
      if (results is! Map) return null;
      final detail = Map<String, dynamic>.from(results);
      final publisher = await _volumePublisher(detail);
      if (publisher != null) {
        detail['publisher'] = publisher;
      }
      return detail;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _volumePublisher(
    Map<String, dynamic> detail,
  ) async {
    final volume = _mapOrEmpty(detail['volume']);
    final detailUrl = volume['api_detail_url']?.toString();
    final key = _apiKey.trim();
    if (detailUrl == null || detailUrl.isEmpty || key.isEmpty) return null;
    try {
      final uri = Uri.parse(detailUrl).replace(queryParameters: {
        'api_key': key,
        'format': 'json',
        'field_list': 'publisher,start_year',
      });
      final response = await http.get(
        uri,
        headers: const {
          HttpHeaders.userAgentHeader: 'LuminaMedia/1.0',
        },
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'];
      if (results is! Map) return null;
      final publisher = _mapOrEmpty(results['publisher']);
      if (publisher.isEmpty) return null;
      if (results['start_year'] != null) {
        publisher['start_year'] = results['start_year'].toString();
      }
      return publisher;
    } catch (_) {
      return null;
    }
  }

  DocumentMetadata _metadataFromComicVineItem(
    Map<String, dynamic> item,
    Map<String, dynamic>? detail,
  ) {
    final source = detail ?? item;
    final image =
        Map<String, dynamic>.from(source['image'] ?? item['image'] ?? const {});
    final volume = Map<String, dynamic>.from(
        source['volume'] ?? item['volume'] ?? const {});
    final publisher = _mapOrEmpty(source['publisher'] ?? item['publisher']);
    final issueNumber =
        (source['issue_number'] ?? item['issue_number'])?.toString();
    final volumeName = volume['name']?.toString();
    final rawName = (source['name'] ?? item['name'])?.toString();
    final credits = _credits(source['person_credits']);
    final title = (rawName == null || rawName.trim().isEmpty)
        ? [
            if (volumeName != null) volumeName,
            if (issueNumber != null && issueNumber.isNotEmpty) '#$issueNumber',
          ].join(' ')
        : rawName;
    final summary = _plainText(
      source['deck']?.toString() ??
          item['deck']?.toString() ??
          source['description']?.toString() ??
          item['description']?.toString(),
    );

    return DocumentMetadata(
      title: title.trim().isEmpty ? volumeName : title.trim(),
      series: volumeName,
      summary: summary,
      coverUrl: (image['super_url'] ??
              image['original_url'] ??
              image['screen_url'] ??
              image['medium_url'])
          ?.toString(),
      tags: [
        if (_publisherName(item, volume, publisher) != null)
          _publisherName(item, volume, publisher)!,
        if (publisher['start_year'] != null)
          publisher['start_year'].toString()
        else if (item['start_year'] != null)
          item['start_year'].toString(),
      ],
      publisher: _publisherName(item, volume, publisher),
      writers: credits.writers,
      artists: credits.artists,
      volume: volumeName,
      chapter: issueNumber,
      detailUrl:
          (source['site_detail_url'] ?? item['site_detail_url'])?.toString(),
      source: label,
    );
  }

  Map<String, dynamic> _mapOrEmpty(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  String? _publisherName(
    Map item,
    Map<String, dynamic> volume,
    Map<String, dynamic> publisher,
  ) {
    final direct = publisher['name']?.toString();
    if (direct != null && direct.trim().isNotEmpty) return direct;
    final volumePublisher =
        _mapOrEmpty(volume['publisher'])['name']?.toString();
    if (volumePublisher != null && volumePublisher.trim().isNotEmpty) {
      return volumePublisher;
    }
    return null;
  }

  ({List<String> writers, List<String> artists}) _credits(dynamic value) {
    if (value is! List) return (writers: const [], artists: const []);
    final writers = <String>[];
    final artists = <String>[];
    for (final raw in value.whereType<Map>()) {
      final credit = Map<String, dynamic>.from(raw);
      final name = credit['name']?.toString();
      if (name == null || name.trim().isEmpty) continue;
      final role =
          (credit['role'] ?? credit['type'] ?? '').toString().toLowerCase();
      if (role.contains('writer') || role.contains('script')) {
        writers.add(name);
      } else if (role.contains('artist') ||
          role.contains('pencil') ||
          role.contains('inker') ||
          role.contains('color') ||
          role.contains('letter') ||
          role.contains('cover')) {
        artists.add(name);
      } else {
        artists.add(name);
      }
    }
    return (
      writers: writers.toSet().take(8).toList(),
      artists: artists.toSet().take(8).toList(),
    );
  }

  String? _plainText(String? html) {
    if (html == null || html.trim().isEmpty) return null;
    return html
        .replaceAll(
            RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
