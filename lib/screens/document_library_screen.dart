import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import '../providers/media_provider.dart';
import '../providers/remote_media_provider.dart';
import '../services/ebook_manga_metadata_service.dart';
import 'manga_detail_screen.dart';

class DocumentItem {
  final String id;
  final String title;
  final String fileName;
  final String? path;
  final String? url;
  final Map<String, String> headers;
  final String extension;
  final String? coverUrl;
  final String? localCoverPath;
  final String? series;
  final String? publisher;
  final String? summary;
  final List<String> authors;
  final String? isbn;
  final String? volume;
  final String? issue;
  final List<String> writers;
  final List<String> artists;
  final String? detailUrl;
  final List<String> tags;
  final double? rating;

  const DocumentItem({
    required this.id,
    required this.title,
    required this.fileName,
    required this.extension,
    this.path,
    this.url,
    this.headers = const {},
    this.coverUrl,
    this.localCoverPath,
    this.series,
    this.publisher,
    this.summary,
    this.authors = const [],
    this.isbn,
    this.volume,
    this.issue,
    this.writers = const [],
    this.artists = const [],
    this.detailUrl,
    this.tags = const [],
    this.rating,
  });

  factory DocumentItem.fromJson(
    Map<String, dynamic> json,
    String baseUrl,
    Map<String, String> headers,
  ) {
    final type = json['type'] as String? ?? 'ebook';
    final id = json['id'] as String;
    return DocumentItem(
      id: id,
      title: json['title'] as String? ?? 'Untitled',
      fileName: json['fileName'] as String? ?? 'document',
      extension: json['extension'] as String? ?? '',
      coverUrl: json['coverUrl'] as String?,
      series: json['series'] as String?,
      publisher: json['publisher'] as String?,
      summary: json['summary'] as String?,
      authors: List<String>.from(json['authors'] ?? const []),
      isbn: json['isbn'] as String?,
      volume: json['volume'] as String?,
      issue: json['issue'] as String? ?? json['chapter'] as String?,
      writers: List<String>.from(json['writers'] ?? const []),
      artists: List<String>.from(json['artists'] ?? const []),
      detailUrl: json['detailUrl'] as String?,
      tags: List<String>.from(json['tags'] ?? const []),
      rating: (json['rating'] as num?)?.toDouble(),
      url: '$baseUrl/api/documents/$type/$id/stream',
      headers: headers,
    );
  }
}

class DocumentLibraryScreen extends StatefulWidget {
  final DocumentLibraryType type;
  const DocumentLibraryScreen({super.key, required this.type});

  @override
  State<DocumentLibraryScreen> createState() => _DocumentLibraryScreenState();
}

class _DocumentLibraryScreenState extends State<DocumentLibraryScreen> {
  late Future<List<DocumentItem>> _itemsFuture;
  _ComicGroupMode _comicGroupMode = _ComicGroupMode.publisher;
  _MangaGroupMode _mangaGroupMode = _MangaGroupMode.series;
  String _comicFilter = 'All';
  String? _loadedStorageKey;

  bool get _isManga => widget.type == DocumentLibraryType.manga;
  bool get _isComics => widget.type == DocumentLibraryType.comics;
  bool get _isGraphicLibrary => _isManga || _isComics;
  String get _remoteType =>
      _isManga ? 'manga' : (_isComics ? 'comic' : 'ebook');

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItems();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = _storageKey();
    if (_loadedStorageKey != key) {
      _loadedStorageKey = key;
      _itemsFuture = _loadItems();
    }
  }

  String _storageKey() {
    if (Platform.isAndroid) {
      final provider = Provider.of<RemoteMediaProvider>(context);
      return '${provider.baseUrl ?? ''}:$_remoteType';
    }
    final provider = Provider.of<MediaProvider>(context);
    final rootPath = _isManga
        ? provider.settings.mangaStoragePath
        : _isComics
            ? provider.settings.comicsStoragePath
            : provider.settings.ebookStoragePath;
    return '${widget.type.name}:${rootPath ?? ''}';
  }

  Future<List<DocumentItem>> _loadItems({bool forceRefresh = false}) async {
    if (Platform.isAndroid) {
      final provider = Provider.of<RemoteMediaProvider>(context, listen: false);
      final docs = await provider.fetchDocumentJson(
        _remoteType,
        forceRefresh: forceRefresh && !_isManga,
      );
      final baseUrl = provider.baseUrl;
      if (baseUrl == null) return [];
      final headers = provider.authHeaders;
      return docs
          .map((doc) => DocumentItem.fromJson(
              Map<String, dynamic>.from(doc as Map), baseUrl, headers))
          .toList();
    }

    final provider = Provider.of<MediaProvider>(context, listen: false);
    final rootPath = _isManga
        ? provider.settings.mangaStoragePath
        : _isComics
            ? provider.settings.comicsStoragePath
            : provider.settings.ebookStoragePath;
    if (rootPath == null || rootPath.isEmpty) return [];
    final root = Directory(rootPath);
    if (!await root.exists()) return [];
    final extensions = _isGraphicLibrary
        ? const [
            '.cbz',
            '.cbr',
            '.pdf',
            '.jpg',
            '.jpeg',
            '.png',
            '.webp',
            '.gif'
          ]
        : const ['.epub', '.pdf', '.txt', '.md', '.markdown', '.log'];
    final files = await root
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => extensions.any(file.path.toLowerCase().endsWith))
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final service = EbookMangaMetadataService.instance;
    final items = <DocumentItem>[];
    for (final file in files) {
      final name = file.path.split(Platform.pathSeparator).last;
      final metadata = await service.enrichFile(
        file,
        isManga: _isManga,
        isComics: _isComics,
        forceRefresh: forceRefresh && !_isManga,
        providerToggles: provider.settings.documentMetadataToggles,
      );
      items.add(DocumentItem(
        id: base64Url.encode(utf8.encode(file.path)),
        title: metadata.title ?? name.replaceAll(RegExp(r'\.[^.]+$'), ''),
        fileName: name,
        extension: name.split('.').last.toLowerCase(),
        path: file.path,
        coverUrl: metadata.coverUrl,
        localCoverPath: metadata.localCoverPath,
        series: metadata.series,
        publisher: metadata.publisher,
        summary: metadata.summary,
        authors: metadata.authors,
        isbn: metadata.isbn,
        volume: metadata.volume,
        issue: metadata.chapter,
        writers: metadata.writers,
        artists: metadata.artists,
        detailUrl: metadata.detailUrl,
        tags: metadata.tags,
        rating: metadata.rating,
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final title = _isManga
        ? 'Manga'
        : _isComics
            ? 'Comics'
            : 'E-books';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
          child: Row(
            children: [
              Icon(
                  _isGraphicLibrary
                      ? Icons.auto_stories_rounded
                      : Icons.menu_book_rounded,
                  color: const Color(0xFFE9B3FF),
                  size: 28),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Manrope',
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                tooltip: _isComics
                    ? 'Refresh Comic Vine metadata'
                    : 'Refresh library',
                onPressed: () => setState(
                  () => _itemsFuture = _loadItems(forceRefresh: !_isManga),
                ),
              ),
            ],
          ),
        ),
        if (_isManga)
          _MangaControls(
            groupMode: _mangaGroupMode,
            onChanged: (mode) => setState(() => _mangaGroupMode = mode),
          ),
        if (_isComics)
          FutureBuilder<List<DocumentItem>>(
            future: _itemsFuture,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <DocumentItem>[];
              return _ComicControls(
                items: items,
                groupMode: _comicGroupMode,
                selectedFilter: _comicFilter,
                onGroupModeChanged: (mode) => setState(() {
                  _comicGroupMode = mode;
                  _comicFilter = 'All';
                }),
                onFilterChanged: (filter) =>
                    setState(() => _comicFilter = filter),
              );
            },
          ),
        Expanded(
          child: FutureBuilder<List<DocumentItem>>(
            future: _itemsFuture,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <DocumentItem>[];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    _isGraphicLibrary
                        ? 'No ${_isComics ? 'comic' : 'manga'} files found. Add CBZ, CBR, PDF or image files.'
                        : 'No readable e-books found. Add EPUB, PDF, TXT or MD files.',
                    style: const TextStyle(color: Colors.white38),
                  ),
                );
              }
              if (_isComics) {
                return _ComicsLibraryView(
                  items: _filteredComics(items),
                  groupMode: _comicGroupMode,
                  onOpen: (item) => _openDocument(item, items),
                );
              }
              if (_isManga && _mangaGroupMode == _MangaGroupMode.series) {
                return _MangaSeriesView(
                  items: items,
                  onOpenSeries: (series, volumes) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MangaDetailScreen(
                          seriesRepresentative: volumes.first,
                          volumes: volumes,
                        ),
                      ),
                    );
                  },
                );
              }
              return _DocumentGrid(
                items: items,
                isGraphicLibrary: _isGraphicLibrary,
                isComics: _isComics,
                showFullArtwork: !_isManga,
                onOpen: (item) => _openDocument(item, items),
              );
            },
          ),
        ),
      ],
    );
  }

  List<DocumentItem> _filteredComics(List<DocumentItem> items) {
    if (_comicFilter == 'All') return items;
    return items.where((item) => _groupValue(item) == _comicFilter).toList();
  }

  String _groupValue(DocumentItem item) {
    switch (_comicGroupMode) {
      case _ComicGroupMode.publisher:
        return item.publisher ?? 'Unknown Publisher';
      case _ComicGroupMode.volume:
        return item.series ?? item.volume ?? 'Unknown Volume';
    }
  }

  void _openDocument(DocumentItem item, List<DocumentItem> items) {
    if (_isComics) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ComicDetailScreen(
            item: item,
            items: items,
            initialIndex:
                items.indexWhere((candidate) => candidate.id == item.id),
          ),
        ),
      );
      return;
    }

    if (!_isManga) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(
            item: item,
            items: items,
            initialIndex:
                items.indexWhere((candidate) => candidate.id == item.id),
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentReaderScreen(
          item: item,
          type: widget.type,
          mangaItems: _isGraphicLibrary ? items : const [],
          initialIndex:
              items.indexWhere((candidate) => candidate.id == item.id),
        ),
      ),
    );
  }
}

enum _ComicGroupMode { publisher, volume }
enum _MangaGroupMode { series, flat }

class _MangaControls extends StatelessWidget {
  final _MangaGroupMode groupMode;
  final ValueChanged<_MangaGroupMode> onChanged;

  const _MangaControls({required this.groupMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      child: SegmentedButton<_MangaGroupMode>(
        segments: const [
          ButtonSegment(
            value: _MangaGroupMode.series,
            icon: Icon(Icons.collections_bookmark_rounded, size: 16),
            label: Text('Series'),
          ),
          ButtonSegment(
            value: _MangaGroupMode.flat,
            icon: Icon(Icons.grid_view_rounded, size: 16),
            label: Text('All Files'),
          ),
        ],
        selected: {groupMode},
        onSelectionChanged: (value) => onChanged(value.first),
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(Colors.white),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? const Color(0xFFE9B3FF).withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04);
          }),
        ),
      ),
    );
  }
}

class _MangaSeriesView extends StatelessWidget {
  final List<DocumentItem> items;
  final Function(String series, List<DocumentItem> volumes) onOpenSeries;

  const _MangaSeriesView({required this.items, required this.onOpenSeries});

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<DocumentItem>>{};
    for (final item in items) {
      final key = item.series ?? 'Ungrouped';
      groups.putIfAbsent(key, () => []).add(item);
    }
    
    final seriesNames = groups.keys.toList()..sort();

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.62,
        crossAxisSpacing: 20,
        mainAxisSpacing: 32,
      ),
      itemCount: seriesNames.length,
      itemBuilder: (context, index) {
        final name = seriesNames[index];
        final volumes = groups[name]!;
        final representative = volumes.first;

        return InkWell(
          onTap: () => onOpenSeries(name, volumes),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _DocumentCover(
                        item: representative,
                        isManga: true,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${volumes.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  fontFamily: 'Manrope',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${volumes.length} volumes',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ComicControls extends StatelessWidget {
  final List<DocumentItem> items;
  final _ComicGroupMode groupMode;
  final String selectedFilter;
  final ValueChanged<_ComicGroupMode> onGroupModeChanged;
  final ValueChanged<String> onFilterChanged;

  const _ComicControls({
    required this.items,
    required this.groupMode,
    required this.selectedFilter,
    required this.onGroupModeChanged,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filters = {'All', ...items.map(_valueFor).where((v) => v.isNotEmpty)}
        .toList()
      ..sort();
    filters.remove('All');
    filters.insert(0, 'All');
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
      child: Row(
        children: [
          SegmentedButton<_ComicGroupMode>(
            segments: const [
              ButtonSegment(
                value: _ComicGroupMode.publisher,
                icon: Icon(Icons.business_rounded, size: 16),
                label: Text('Publisher'),
              ),
              ButtonSegment(
                value: _ComicGroupMode.volume,
                icon: Icon(Icons.collections_bookmark_rounded, size: 16),
                label: Text('Volume'),
              ),
            ],
            selected: {groupMode},
            onSelectionChanged: (value) => onGroupModeChanged(value.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.all(Colors.white),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? const Color(0xFFE9B3FF).withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.04);
              }),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters.map((filter) {
                  final selected = selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: selected,
                      onSelected: (_) => onFilterChanged(filter),
                      selectedColor:
                          const Color(0xFFAAC7FF).withValues(alpha: 0.18),
                      backgroundColor: Colors.white.withValues(alpha: 0.04),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.white60,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _valueFor(DocumentItem item) {
    switch (groupMode) {
      case _ComicGroupMode.publisher:
        return item.publisher ?? 'Unknown Publisher';
      case _ComicGroupMode.volume:
        return item.series ?? item.volume ?? 'Unknown Volume';
    }
  }
}

class _ComicsLibraryView extends StatelessWidget {
  final List<DocumentItem> items;
  final _ComicGroupMode groupMode;
  final ValueChanged<DocumentItem> onOpen;

  const _ComicsLibraryView({
    required this.items,
    required this.groupMode,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<DocumentItem>>{};
    for (final item in items) {
      final key = groupMode == _ComicGroupMode.publisher
          ? item.publisher ?? 'Unknown Publisher'
          : item.series ?? item.volume ?? 'Unknown Volume';
      groups.putIfAbsent(key, () => []).add(item);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final comics = entry.value
          ..sort((a, b) {
            final issueA = int.tryParse(a.issue ?? '') ?? 999999;
            final issueB = int.tryParse(b.issue ?? '') ?? 999999;
            final issueCompare = issueA.compareTo(issueB);
            return issueCompare != 0
                ? issueCompare
                : a.title.compareTo(b.title);
          });
        return Padding(
          padding: const EdgeInsets.only(bottom: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${comics.length}',
                    style: const TextStyle(color: Colors.white38),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 282,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: comics.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, comicIndex) {
                    final item = comics[comicIndex];
                    return SizedBox(
                      width: 164,
                      child: _DocumentCard(
                        item: item,
                        isManga: true,
                        showFullArtwork: true,
                        onTap: () => onOpen(item),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DocumentGrid extends StatelessWidget {
  final List<DocumentItem> items;
  final bool isGraphicLibrary;
  final bool isComics;
  final bool showFullArtwork;
  final ValueChanged<DocumentItem> onOpen;

  const _DocumentGrid({
    required this.items,
    required this.isGraphicLibrary,
    required this.isComics,
    required this.showFullArtwork,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.72,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _DocumentCard(
          item: item,
          isManga: isGraphicLibrary,
          showFullArtwork: showFullArtwork || isComics,
          onTap: () => onOpen(item),
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final DocumentItem item;
  final bool isManga;
  final bool showFullArtwork;
  final VoidCallback onTap;

  const _DocumentCard({
    required this.item,
    required this.isManga,
    required this.showFullArtwork,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _DocumentCover(
                item: item,
                isManga: isManga,
                fit: showFullArtwork ? BoxFit.contain : BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.rating != null || item.tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.rating != null
                  ? '★ ${item.rating!.toStringAsFixed(1)}'
                  : item.tags.first,
              style: const TextStyle(color: Color(0xFFE9B3FF), fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _DocumentCover extends StatelessWidget {
  final DocumentItem item;
  final bool isManga;
  final BoxFit fit;
  const _DocumentCover({
    required this.item,
    required this.isManga,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    if (item.localCoverPath != null &&
        File(item.localCoverPath!).existsSync()) {
      return _framed(Image.file(File(item.localCoverPath!), fit: fit));
    }
    if (item.coverUrl != null) {
      return _framed(CachedNetworkImage(imageUrl: item.coverUrl!, fit: fit));
    }
    final imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
    if (item.url != null && imageExtensions.contains(item.extension)) {
      return _framed(
        CachedNetworkImage(
          imageUrl: item.url!,
          httpHeaders: item.headers,
          fit: fit,
        ),
      );
    }
    if (item.path != null && imageExtensions.contains(item.extension)) {
      return _framed(Image.file(File(item.path!), fit: fit));
    }
    return Icon(
      isManga ? Icons.auto_stories_rounded : Icons.menu_book_rounded,
      color: const Color(0xFFE9B3FF),
      size: 48,
    );
  }

  Widget _framed(Widget child) {
    if (fit != BoxFit.contain) return child;
    return ColoredBox(
      color: const Color(0xFF111114),
      child: SizedBox.expand(child: child),
    );
  }
}

class ComicDetailScreen extends StatelessWidget {
  final DocumentItem item;
  final List<DocumentItem> items;
  final int initialIndex;

  const ComicDetailScreen({
    super.key,
    required this.item,
    required this.items,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    final readableIndex = initialIndex < 0 ? 0 : initialIndex;
    return Scaffold(
      backgroundColor: const Color(0xFF101012),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: const Color(0xFF101012),
            expandedHeight: 360,
            pinned: true,
            title: Text(item.title),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _DocumentCover(
                    item: item,
                    isManga: true,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.12),
                          const Color(0xFF101012),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: 128,
                            height: 194,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _DocumentCover(
                                item: item,
                                isManga: true,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    if (item.publisher != null) item.publisher,
                                    if (item.series != null) item.series,
                                    if (item.issue != null)
                                      'Issue #${item.issue}',
                                  ].whereType<String>().join(' | '),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => DocumentReaderScreen(
                                          item: item,
                                          type: DocumentLibraryType.comics,
                                          mangaItems: items,
                                          initialIndex: readableIndex,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.menu_book_rounded),
                                  label: const Text('Read Comic'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE9B3FF),
                                    foregroundColor: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 26, 32, 42),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _ComicInfoSection(
                  title: 'Synopsis',
                  body:
                      item.summary ?? 'No synopsis found from Comic Vine yet.',
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _InfoPill(label: 'Publisher', value: item.publisher),
                    _InfoPill(
                        label: 'Volume', value: item.series ?? item.volume),
                    _InfoPill(
                      label: 'Issue',
                      value: item.issue == null ? null : '#${item.issue}',
                    ),
                    _InfoPill(
                        label: 'Source',
                        value: item.detailUrl == null ? null : 'Comic Vine'),
                  ],
                ),
                const SizedBox(height: 26),
                _CreditBlock(title: 'Writers', people: item.writers),
                const SizedBox(height: 18),
                _CreditBlock(title: 'Artists', people: item.artists),
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.tags
                        .map((tag) => Chip(
                              label: Text(tag),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.06),
                              labelStyle:
                                  const TextStyle(color: Colors.white70),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class BookDetailScreen extends StatelessWidget {
  final DocumentItem item;
  final List<DocumentItem> items;
  final int initialIndex;

  const BookDetailScreen({
    super.key,
    required this.item,
    required this.items,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    final readableIndex = initialIndex < 0 ? 0 : initialIndex;
    final authors = item.authors.isNotEmpty
        ? item.authors
        : item.writers.isNotEmpty
            ? item.writers
            : const <String>[];
    final source = item.detailUrl == null
        ? null
        : item.detailUrl!.contains('openlibrary.org')
            ? 'Open Library'
            : 'Google Books';

    return Scaffold(
      backgroundColor: const Color(0xFF101012),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: const Color(0xFF101012),
            expandedHeight: 360,
            pinned: true,
            title: Text(item.title),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _DocumentCover(
                    item: item,
                    isManga: false,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          const Color(0xFF101012),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: 128,
                            height: 194,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _DocumentCover(
                                item: item,
                                isManga: false,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  authors.isEmpty
                                      ? item.fileName
                                      : authors.join(', '),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => DocumentReaderScreen(
                                          item: item,
                                          type: DocumentLibraryType.ebooks,
                                          mangaItems: items,
                                          initialIndex: readableIndex,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.menu_book_rounded),
                                  label: const Text('Read Book'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE9B3FF),
                                    foregroundColor: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 26, 32, 42),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _ComicInfoSection(
                  title: 'Synopsis',
                  body: item.summary ?? 'No synopsis found for this book yet.',
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _InfoPill(
                      label: 'Author',
                      value: authors.isEmpty ? null : authors.join(', '),
                    ),
                    _InfoPill(label: 'ISBN', value: item.isbn),
                    _InfoPill(
                      label: 'Format',
                      value: item.extension.toUpperCase(),
                    ),
                    _InfoPill(label: 'Source', value: source),
                  ],
                ),
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.tags
                        .map((tag) => Chip(
                              label: Text(tag),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.06),
                              labelStyle:
                                  const TextStyle(color: Colors.white70),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComicInfoSection extends StatelessWidget {
  final String title;
  final String body;

  const _ComicInfoSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String? value;

  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(value!, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class _CreditBlock extends StatelessWidget {
  final String title;
  final List<String> people;

  const _CreditBlock({required this.title, required this.people});

  @override
  Widget build(BuildContext context) {
    return _ComicInfoSection(
      title: title,
      body: people.isEmpty ? 'No $title listed.' : people.join(', '),
    );
  }
}

class DocumentReaderScreen extends StatelessWidget {
  final DocumentItem item;
  final DocumentLibraryType type;
  final List<DocumentItem> mangaItems;
  final int initialIndex;

  const DocumentReaderScreen({
    super.key,
    required this.item,
    required this.type,
    this.mangaItems = const [],
    this.initialIndex = 0,
  });

  bool get _isManga =>
      type == DocumentLibraryType.manga || type == DocumentLibraryType.comics;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101012),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101012),
        title: Text(item.title),
      ),
      body: _isManga ? _buildMangaReader() : _buildBookReader(context),
    );
  }

  Widget _buildMangaReader() {
    return _ComicReaderView(
      item: item,
      pages: mangaItems.isEmpty ? [item] : mangaItems,
      initialIndex: initialIndex,
    );
  }

  Widget _buildBookReader(BuildContext context) {
    return _BookReaderView(item: item);
  }
}

class _BookReaderView extends StatefulWidget {
  final DocumentItem item;

  const _BookReaderView({required this.item});

  @override
  State<_BookReaderView> createState() => _BookReaderViewState();
}

class _BookReaderViewState extends State<_BookReaderView> {
  late Future<_BookReaderData> _dataFuture;
  final PageController _pageController = PageController();
  final PdfViewerController _pdfController = PdfViewerController();
  final FocusNode _focusNode = FocusNode();
  int _pageIndex = 0;
  int _pdfPage = 1;
  int _pdfPageCount = 1;
  int _textPageCount = 1;
  double _fontSize = 18;

  static const _textExtensions = {'epub', 'txt', 'md', 'markdown', 'log'};

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<_BookReaderData> _load() async {
    if (widget.item.extension == 'pdf') {
      if (widget.item.path != null) {
        return _BookReaderData.pdfFile(widget.item.path!);
      }
      if (widget.item.url != null) {
        final response = await http.get(
          Uri.parse(widget.item.url!),
          headers: widget.item.headers,
        );
        if (response.statusCode >= 400) {
          throw Exception('Unable to load PDF (${response.statusCode}).');
        }
        return _BookReaderData.pdfBytes(response.bodyBytes);
      }
    }

    if (!_textExtensions.contains(widget.item.extension)) {
      return const _BookReaderData.unsupported();
    }

    final bytes = widget.item.url != null
        ? (await http.get(Uri.parse(widget.item.url!),
                headers: widget.item.headers))
            .bodyBytes
        : await File(widget.item.path!).readAsBytes();
    final text = widget.item.extension == 'epub'
        ? _readEpubText(bytes)
        : utf8.decode(bytes, allowMalformed: true);
    return _BookReaderData.text(_splitIntoPages(text));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.pageDown ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          _nextPage();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.pageUp ||
            key == LogicalKeyboardKey.gameButtonB) {
          _previousPage();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FutureBuilder<_BookReaderData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'Could not open this book: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.unsupported) {
            return Center(
              child: Text(
                '${widget.item.extension.toUpperCase()} reading is not supported yet.',
                style: const TextStyle(color: Colors.white54),
              ),
            );
          }
          if (data.isPdf) return _buildPdfReader(data);
          return _buildTextReader(data.pages);
        },
      ),
    );
  }

  Widget _buildPdfReader(_BookReaderData data) {
    final viewer = data.pdfPath != null
        ? PdfViewer.file(
            data.pdfPath!,
            controller: _pdfController,
            params: PdfViewerParams(
              onViewerReady: (document, controller) {
                if (mounted) {
                  setState(() => _pdfPageCount = document.pages.length);
                }
              },
              onPageChanged: (page) {
                if (mounted && page != null) setState(() => _pdfPage = page);
              },
            ),
          )
        : PdfViewer.data(
            data.pdfBytes!,
            sourceName: widget.item.url ?? widget.item.fileName,
            controller: _pdfController,
            params: PdfViewerParams(
              onViewerReady: (document, controller) {
                if (mounted) {
                  setState(() => _pdfPageCount = document.pages.length);
                }
              },
              onPageChanged: (page) {
                if (mounted && page != null) setState(() => _pdfPage = page);
              },
            ),
          );

    return Stack(
      children: [
        Positioned.fill(child: viewer),
        Positioned(
          left: 20,
          right: 20,
          bottom: 20,
          child: _BookReaderToolbar(
            pageIndex: _pdfPage - 1,
            pageCount: _pdfPageCount,
            fontSize: _fontSize,
            showFontControls: false,
            onPrevious: _pdfPage <= 1 ? null : _previousPage,
            onNext: _pdfPage >= _pdfPageCount ? null : _nextPage,
            onFontSmaller: _decreaseFont,
            onFontLarger: _increaseFont,
          ),
        ),
      ],
    );
  }

  Widget _buildTextReader(List<String> pages) {
    _textPageCount = pages.isEmpty ? 1 : pages.length;
    if (pages.isEmpty) {
      return const Center(
        child: Text(
          'This book did not contain readable text.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: pages.length,
          onPageChanged: (index) => setState(() => _pageIndex = index),
          itemBuilder: (context, index) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(34, 24, 34, 92),
                  child: Text(
                    pages[index],
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _fontSize,
                      height: 1.65,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 20,
          child: _BookReaderToolbar(
            pageIndex: _pageIndex,
            pageCount: pages.length,
            fontSize: _fontSize,
            onPrevious: _pageIndex == 0 ? null : _previousPage,
            onNext: _pageIndex >= pages.length - 1 ? null : _nextPage,
            onFontSmaller: _decreaseFont,
            onFontLarger: _increaseFont,
          ),
        ),
      ],
    );
  }

  void _previousPage() {
    if (widget.item.extension == 'pdf') {
      if (_pdfPage > 1) {
        _pdfController.goToPage(pageNumber: _pdfPage - 1);
      }
      return;
    }
    if (_pageIndex > 0) _goToTextPage(_pageIndex - 1);
  }

  void _nextPage() {
    if (widget.item.extension == 'pdf') {
      if (_pdfPage < _pdfPageCount) {
        _pdfController.goToPage(pageNumber: _pdfPage + 1);
      }
      return;
    }
    if (_pageIndex < _textPageCount - 1) _goToTextPage(_pageIndex + 1);
  }

  void _goToTextPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _increaseFont() {
    setState(() => _fontSize = (_fontSize + 1).clamp(14, 30).toDouble());
  }

  void _decreaseFont() {
    setState(() => _fontSize = (_fontSize - 1).clamp(14, 30).toDouble());
  }

  String _readEpubText(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final textFiles = archive.files.where((entry) {
      final name = entry.name.toLowerCase();
      return entry.isFile &&
          (name.endsWith('.xhtml') || name.endsWith('.html'));
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final chunks = textFiles.take(80).map((entry) {
      final html =
          utf8.decode(entry.content as List<int>, allowMalformed: true);
      return html
          .replaceAll(
              RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
          .replaceAll(
              RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }).where((text) => text.isNotEmpty);
    return chunks.join('\n\n');
  }

  List<String> _splitIntoPages(String text) {
    final cleaned = text
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (cleaned.isEmpty) return const [];
    final paragraphs = cleaned.split(RegExp(r'\n\s*\n'));
    final pages = <String>[];
    final buffer = StringBuffer();
    const targetLength = 2400;
    for (final paragraph in paragraphs) {
      final next = paragraph.trim();
      if (next.isEmpty) continue;
      if (buffer.length + next.length > targetLength && buffer.isNotEmpty) {
        pages.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.writeln(next);
      buffer.writeln();
    }
    if (buffer.isNotEmpty) pages.add(buffer.toString().trim());
    return pages;
  }
}

class _BookReaderData {
  final List<String> pages;
  final String? pdfPath;
  final Uint8List? pdfBytes;
  final bool unsupported;

  const _BookReaderData.text(this.pages)
      : pdfPath = null,
        pdfBytes = null,
        unsupported = false;

  const _BookReaderData.pdfFile(this.pdfPath)
      : pages = const [],
        pdfBytes = null,
        unsupported = false;

  const _BookReaderData.pdfBytes(this.pdfBytes)
      : pages = const [],
        pdfPath = null,
        unsupported = false;

  const _BookReaderData.unsupported()
      : pages = const [],
        pdfPath = null,
        pdfBytes = null,
        unsupported = true;

  bool get isPdf => pdfPath != null || pdfBytes != null;
}

class _BookReaderToolbar extends StatelessWidget {
  final int pageIndex;
  final int pageCount;
  final double fontSize;
  final bool showFontControls;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onFontSmaller;
  final VoidCallback onFontLarger;

  const _BookReaderToolbar({
    required this.pageIndex,
    required this.pageCount,
    required this.fontSize,
    required this.onPrevious,
    required this.onNext,
    required this.onFontSmaller,
    required this.onFontLarger,
    this.showFontControls = true,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF18181C).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous page',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
              color: Colors.white,
            ),
            SizedBox(
              width: 116,
              child: Text(
                'Page ${pageIndex + 1} of $pageCount',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
              color: Colors.white,
            ),
            if (showFontControls) ...[
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: Colors.white.withValues(alpha: 0.1),
              ),
              IconButton(
                tooltip: 'Smaller text',
                onPressed: onFontSmaller,
                icon: const Icon(Icons.text_decrease_rounded),
                color: Colors.white,
              ),
              Text(
                '${fontSize.round()}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              IconButton(
                tooltip: 'Larger text',
                onPressed: onFontLarger,
                icon: const Icon(Icons.text_increase_rounded),
                color: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComicPage {
  final Uint8List? bytes;
  final DocumentItem? item;

  const _ComicPage.memory(this.bytes) : item = null;
  const _ComicPage.item(this.item) : bytes = null;
}

class _ComicReaderView extends StatefulWidget {
  final DocumentItem item;
  final List<DocumentItem> pages;
  final int initialIndex;

  const _ComicReaderView({
    required this.item,
    required this.pages,
    required this.initialIndex,
  });

  @override
  State<_ComicReaderView> createState() => _ComicReaderViewState();
}

class _ComicReaderViewState extends State<_ComicReaderView> {
  late final PageController _pageController;
  late Future<List<_ComicPage>> _pagesFuture;
  final TransformationController _transform = TransformationController();
  int _pageIndex = 0;
  double _zoom = 1;

  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

  @override
  void initState() {
    super.initState();
    _pageIndex = widget.item.extension == 'cbz'
        ? 0
        : (widget.initialIndex < 0 ? 0 : widget.initialIndex);
    _pageController = PageController(initialPage: _pageIndex);
    _pagesFuture = _loadPages();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<List<_ComicPage>> _loadPages() async {
    if (widget.item.extension == 'cbz') {
      if (widget.item.url == null && widget.item.path == null) return const [];
      final bytes = widget.item.url != null
          ? (await http.get(Uri.parse(widget.item.url!),
                  headers: widget.item.headers))
              .bodyBytes
          : await File(widget.item.path!).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final imageFiles = archive.files.where((entry) {
        final name = entry.name.toLowerCase();
        return entry.isFile &&
            (name.endsWith('.jpg') ||
                name.endsWith('.jpeg') ||
                name.endsWith('.png') ||
                name.endsWith('.webp'));
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _pageIndex = 0;
      return imageFiles
          .map((entry) =>
              _ComicPage.memory(Uint8List.fromList(entry.content as List<int>)))
          .toList();
    }

    if (!_imageExtensions.contains(widget.item.extension)) return const [];
    return widget.pages
        .where((page) => _imageExtensions.contains(page.extension))
        .map((page) => _ComicPage.item(page))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_ComicPage>>(
      future: _pagesFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final pages = snapshot.data!;
        if (pages.isEmpty) {
          return Center(
            child: Text(
              '${widget.item.extension.toUpperCase()} reader support is metadata-only right now.',
              style: const TextStyle(color: Colors.white54),
            ),
          );
        }
        return Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: pages.length,
              onPageChanged: (index) {
                setState(() => _pageIndex = index);
                _setZoom(1);
              },
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  transformationController: _transform,
                  minScale: 0.7,
                  maxScale: 5,
                  child: Center(child: _buildPage(pages[index])),
                );
              },
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: _ReaderToolbar(
                pageIndex: _pageIndex,
                pageCount: pages.length,
                zoom: _zoom,
                onPrevious:
                    _pageIndex == 0 ? null : () => _goToPage(_pageIndex - 1),
                onNext: _pageIndex >= pages.length - 1
                    ? null
                    : () => _goToPage(_pageIndex + 1),
                onZoomOut: () => _setZoom((_zoom - 0.25).clamp(0.75, 5)),
                onZoomIn: () => _setZoom((_zoom + 0.25).clamp(0.75, 5)),
                onResetZoom: () => _setZoom(1),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPage(_ComicPage page) {
    if (page.bytes != null) {
      return Image.memory(page.bytes!, fit: BoxFit.contain);
    }
    final item = page.item!;
    if (item.url != null) {
      return CachedNetworkImage(
        imageUrl: item.url!,
        httpHeaders: item.headers,
        fit: BoxFit.contain,
      );
    }
    return Image.file(File(item.path!), fit: BoxFit.contain);
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _setZoom(double zoom) {
    setState(() => _zoom = zoom.toDouble());
    _transform.value = Matrix4.diagonal3Values(_zoom, _zoom, 1);
  }
}

class _ReaderToolbar extends StatelessWidget {
  final int pageIndex;
  final int pageCount;
  final double zoom;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onResetZoom;

  const _ReaderToolbar({
    required this.pageIndex,
    required this.pageCount,
    required this.zoom,
    required this.onPrevious,
    required this.onNext,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onResetZoom,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF18181C).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous page',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
              color: Colors.white,
            ),
            SizedBox(
              width: 116,
              child: Text(
                'Page ${pageIndex + 1} of $pageCount',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
              color: Colors.white,
            ),
            Container(
              width: 1,
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.white.withValues(alpha: 0.1),
            ),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: onZoomOut,
              icon: const Icon(Icons.zoom_out_rounded),
              color: Colors.white,
            ),
            Text(
              '${(zoom * 100).round()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: onZoomIn,
              icon: const Icon(Icons.zoom_in_rounded),
              color: Colors.white,
            ),
            IconButton(
              tooltip: 'Reset zoom',
              onPressed: onResetZoom,
              icon: const Icon(Icons.center_focus_strong_rounded),
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
