import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/iptv_provider.dart';
import '../services/iptv_service.dart';
import 'iptv_player_screen.dart';

// Sakura-themed palette for program blocks (one per channel slot, cycles)
const List<Color> _kChannelColors = [
  Color(0xFFE9B3FF), // sakura purple
  Color(0xFFAAC7FF), // periwinkle
  Color(0xFFFFD7F5), // rose pink
  Color(0xFFFFB4AB), // coral
  Color(0xFFB8EAA8), // mint
  Color(0xFFFFD580), // golden
  Color(0xFF94D4E9), // sky teal
  Color(0xFFF0C0D4), // blush
  Color(0xFFD4B8EA), // lavender
  Color(0xFFA8DEBB), // seafoam
];

Color _colorForIndex(int i) => _kChannelColors[i % _kChannelColors.length];

// ─── Main Screen ─────────────────────────────────────────────────────────────

class IptvLiveScreen extends StatefulWidget {
  const IptvLiveScreen({super.key});

  @override
  State<IptvLiveScreen> createState() => _IptvLiveScreenState();
}

class _IptvLiveScreenState extends State<IptvLiveScreen> {
  String? _selectedCategory;
  bool _showDebugLog = false;
  String _searchQuery = '';
  bool _isCategoriesView = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<IptvProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFE9B3FF)));
        }

        final channels = provider.liveChannels;
        final categoryMap = <String, List<IptvMedia>>{};
        for (final ch in channels) {
          categoryMap.putIfAbsent(ch.group, () => []).add(ch);
        }
        final allCategories = categoryMap.keys.toList()..sort();

        // If no category is selected, we show the category grid by default (IMG_0121)
        if (_isCategoriesView || _selectedCategory == null) {
          return _CategoryGrid(
            categories: allCategories,
            categoryMap: categoryMap,
            provider: provider,
            onCategorySelected: (cat) {
              setState(() {
                _selectedCategory = cat;
                _isCategoriesView = false;
              });
            },
          );
        }

        // Otherwise show the Guide View (IMG_0120)
        final selectedChannels = _selectedCategory == 'All Channels'
            ? channels
            : (categoryMap[_selectedCategory] ?? []);
            
        final filteredChannels = _searchQuery.isEmpty
            ? selectedChannels
            : selectedChannels
                .where((c) =>
                    c.name.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();

        return Column(
          children: [
            _IptvGuideHeader(
              selectedCategory: _selectedCategory!,
              onCategoryTap: () => setState(() => _isCategoriesView = true),
              searchQuery: _searchQuery,
              onSearchChanged: (v) => setState(() => _searchQuery = v),
              showDebugLog: _showDebugLog,
              onToggleDebug: () => setState(() => _showDebugLog = !_showDebugLog),
            ),
            if (_showDebugLog) _IptvDebugWindow(provider: provider),
            Expanded(
              child: IptvGuideTimeline(
                provider: provider,
                channels: filteredChannels,
                category: _selectedCategory!,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Category Grid (Live channels) ───────────────────────────────────────────

class _CategoryGrid extends StatefulWidget {
  final List<String> categories;
  final Map<String, List<IptvMedia>> categoryMap;
  final IptvProvider provider;
  final Function(String) onCategorySelected;

  const _CategoryGrid({
    required this.categories,
    required this.categoryMap,
    required this.provider,
    required this.onCategorySelected,
  });

  @override
  State<_CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends State<_CategoryGrid> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? widget.categories
        : widget.categories
            .where((c) => c.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Column(
      children: [
        // Header (Matches Premium Style)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Live TV',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  _HeaderButton(
                    label: 'Full Guide',
                    icon: Icons.grid_view_rounded,
                    onTap: () => widget.onCategorySelected('All Channels'),
                    isPrimary: true,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38),
                    onPressed: () => widget.provider.loadMedia(forceRefresh: true),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search categories...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.3), size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 20, 12),
          child: Row(
            children: [
              const Text(
                'Categories',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9B3FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.categories.length}',
                  style: const TextStyle(color: Color(0xFFE9B3FF), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        // Grid (Matches Image 0121 card style)
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisExtent: 64,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final cat = filtered[index];
              return _CategoryCard(
                category: cat,
                onTap: () => widget.onCategorySelected(cat),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String category;
  final VoidCallback onTap;

  const _CategoryCard({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Text(
          category,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _IptvGuideHeader extends StatelessWidget {
  final String selectedCategory;
  final VoidCallback onCategoryTap;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final bool showDebugLog;
  final VoidCallback onToggleDebug;

  const _IptvGuideHeader({
    required this.selectedCategory,
    required this.onCategoryTap,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.showDebugLog,
    required this.onToggleDebug,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0B0F),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          // Today Selector (Left)
          _HeaderButton(
            label: 'Today',
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: () {}, // Date picker placeholder
          ),
          const Spacer(),
          
          // Category Dropdown (Center)
          _HeaderButton(
            label: selectedCategory,
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: onCategoryTap,
            isPrimary: true,
          ),
          
          const Spacer(),
          
          // Search (Right)
          Container(
            width: 220,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(19),
            ),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search by program name...',
                hintStyle: const TextStyle(color: Colors.white24),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white24, size: 18),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              showDebugLog ? Icons.bug_report_rounded : Icons.bug_report_outlined,
              color: showDebugLog ? const Color(0xFFE9B3FF) : Colors.white24,
              size: 20,
            ),
            onPressed: onToggleDebug,
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _HeaderButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFFE9B3FF).withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPrimary ? const Color(0xFFE9B3FF).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? const Color(0xFFE9B3FF) : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            Icon(icon, color: isPrimary ? const Color(0xFFE9B3FF) : Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Category EPG Page ────────────────────────────────────────────────────────

class CategoryEpgPage extends StatefulWidget {
  final String category;
  final List<String> allCategories;
  final Map<String, List<IptvMedia>> channelsByCategory;
  final IptvProvider provider;

  const CategoryEpgPage({
    super.key,
    required this.category,
    required this.allCategories,
    required this.channelsByCategory,
    required this.provider,
  });

  @override
  State<CategoryEpgPage> createState() => _CategoryEpgPageState();
}

class _CategoryEpgPageState extends State<CategoryEpgPage> {
  late String _selectedCategory;
  bool _showSearch = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.category;
  }

  List<IptvMedia> get _channels {
    final all = widget.channelsByCategory[_selectedCategory] ?? [];
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            (c.tvgName?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B0F),
      body: Column(
        children: [
          // ── Custom header ───────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF131016),
                border: Border(
                  bottom: BorderSide(
                      color: const Color(0xFFE9B3FF).withValues(alpha: 0.12)),
                ),
              ),
              child: Row(
                children: [
                  // Back
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white70, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),

                  // Category selector
                  Expanded(
                    child: GestureDetector(
                      onTap: _showCategoryPicker,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              _selectedCategory,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Manrope',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded,
                              color: Color(0xFFE9B3FF), size: 20),
                        ],
                      ),
                    ),
                  ),

                  // Search toggle
                  IconButton(
                    icon: Icon(
                      _showSearch
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                      color: Colors.white54,
                    ),
                    onPressed: () => setState(() {
                      _showSearch = !_showSearch;
                      if (!_showSearch) _search = '';
                    }),
                  ),
                ],
              ),
            ),
          ),

          // Search field
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search channels…',
                    hintStyle: TextStyle(color: Colors.white30),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.white24),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ),

          // EPG timeline
          Expanded(
            child: IptvGuideTimeline(
              provider: widget.provider,
              channels: _channels,
              category: _selectedCategory,
            ),
          ),
        ],
      ),
    );
  }

  void _showCategoryPicker() {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategoryPickerSheet(
        categories: widget.allCategories,
        selected: _selectedCategory,
      ),
    ).then((cat) {
      if (cat != null && mounted) setState(() => _selectedCategory = cat);
    });
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  final List<String> categories;
  final String selected;
  const _CategoryPickerSheet(
      {required this.categories, required this.selected});

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final cats = _q.isEmpty
        ? widget.categories
        : widget.categories
            .where((c) => c.toLowerCase().contains(_q.toLowerCase()))
            .toList();
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Filter categories…',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: Colors.white24),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final cat = cats[i];
              final selected = cat == widget.selected;
              return ListTile(
                dense: true,
                title: Text(
                  cat,
                  style: TextStyle(
                    color: selected ? const Color(0xFFE9B3FF) : Colors.white,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.normal,
                  ),
                ),
                trailing: selected
                    ? const Icon(Icons.check_rounded,
                        color: Color(0xFFE9B3FF), size: 18)
                    : null,
                onTap: () => Navigator.of(context).pop(cat),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Media category grid (Movies / Series) ───────────────────────────────────

class _MediaCategoryGrid extends StatefulWidget {
  final List<IptvMedia> items;
  final IptvProvider provider;

  const _MediaCategoryGrid({required this.items, required this.provider});

  @override
  State<_MediaCategoryGrid> createState() => _MediaCategoryGridState();
}

class _MediaCategoryGridState extends State<_MediaCategoryGrid> {
  String _search = '';
  String? _selectedCategory;

  Map<String, List<IptvMedia>> get _categoryMap {
    final map = <String, List<IptvMedia>>{};
    for (final item in widget.items) {
      map.putIfAbsent(item.group, () => []).add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedCategory != null) {
      final items = _categoryMap[_selectedCategory!] ?? [];
      return _MediaItemList(
        category: _selectedCategory!,
        items: items,
        provider: widget.provider,
        onBack: () => setState(() => _selectedCategory = null),
      );
    }

    final allCats = _categoryMap.keys.toList()..sort();
    final filtered = _search.isEmpty
        ? allCats
        : allCats
            .where((c) => c.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search categories…',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: Colors.white24),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white24, size: 18),
                        onPressed: () => setState(() => _search = ''),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              const Text('Categories',
                  style: TextStyle(
                      fontFamily: 'Manrope',
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9B3FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('${filtered.length}',
                    style: const TextStyle(
                        color: Color(0xFFE9B3FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisExtent: 64,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final category = filtered[index];
              return _CategoryCard(
                category: category,
                onTap: () => setState(() => _selectedCategory = category),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MediaItemList extends StatelessWidget {
  final String category;
  final List<IptvMedia> items;
  final IptvProvider provider;
  final VoidCallback onBack;

  const _MediaItemList({
    required this.category,
    required this.items,
    required this.provider,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: const Color(0xFFE9B3FF).withValues(alpha: 0.12)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white70, size: 20),
                onPressed: onBack,
              ),
              Text(
                category,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Manrope',
                ),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: item.logo.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: item.logo,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.movie_rounded,
                              color: Colors.white24),
                        ),
                      )
                    : const Icon(Icons.movie_rounded, color: Colors.white24),
                title: Text(item.name,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: item.tvgName != null && item.tvgName != item.name
                    ? Text(item.tvgName!,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11))
                    : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => IptvPlayerScreen(media: item)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── EPG Timeline Guide ───────────────────────────────────────────────────────

class IptvGuideTimeline extends StatefulWidget {
  final IptvProvider provider;
  final List<IptvMedia> channels;
  final String category;

  const IptvGuideTimeline({
    super.key,
    required this.provider,
    required this.channels,
    this.category = '',
  });

  @override
  State<IptvGuideTimeline> createState() => _IptvGuideTimelineState();
}

class _IptvGuideTimelineState extends State<IptvGuideTimeline> {
  late DateTime _startTime;
  final double _pixelsPerMinute = 3.5; // Slightly wider for better readability
  final double _channelRailWidth = 180;
  final double _rowHeight = 84;

  final ScrollController _programV = ScrollController();
  final ScrollController _channelV = ScrollController();
  final ScrollController _programH = ScrollController();
  final ScrollController _timeH = ScrollController();
  bool _syncV = false;
  bool _syncH = false;

  @override
  void initState() {
    super.initState();
    _startTime = _roundedTime(DateTime.now().subtract(const Duration(hours: 3)));
    _programV.addListener(_onProgramV);
    _channelV.addListener(_onChannelV);
    _programH.addListener(_onProgramH);
    _timeH.addListener(_onTimeH);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToNow());
  }

  DateTime _roundedTime(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day, dt.hour,
        (dt.minute / 30).floor() * 30);
  }

  @override
  void dispose() {
    _programV
      ..removeListener(_onProgramV)
      ..dispose();
    _channelV
      ..removeListener(_onChannelV)
      ..dispose();
    _programH
      ..removeListener(_onProgramH)
      ..dispose();
    _timeH
      ..removeListener(_onTimeH)
      ..dispose();
    super.dispose();
  }

  void _onProgramV() {
    if (_syncV || !_channelV.hasClients) return;
    _syncV = true;
    _channelV.jumpTo(
        _programV.offset.clamp(0.0, _channelV.position.maxScrollExtent));
    _syncV = false;
  }

  void _onChannelV() {
    if (_syncV || !_programV.hasClients) return;
    _syncV = true;
    _programV.jumpTo(
        _channelV.offset.clamp(0.0, _programV.position.maxScrollExtent));
    _syncV = false;
  }

  void _onProgramH() {
    if (_syncH || !_timeH.hasClients) return;
    _syncH = true;
    _timeH.jumpTo(_programH.offset.clamp(0.0, _timeH.position.maxScrollExtent));
    _syncH = false;
  }

  void _onTimeH() {
    if (_syncH || !_programH.hasClients) return;
    _syncH = true;
    _programH
        .jumpTo(_timeH.offset.clamp(0.0, _programH.position.maxScrollExtent));
    _syncH = false;
  }


  void _jumpToNow() {
    if (!_programH.hasClients) return;
    final offset = DateTime.now().difference(_startTime).inMinutes *
        _pixelsPerMinute;
    _programH.jumpTo(
        (offset - 200).clamp(0.0, _programH.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final channels = widget.channels;
    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tv_off_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text(
              widget.category.isEmpty
                  ? 'No channels found'
                  : 'No channels in ${widget.category}',
              style:
                  const TextStyle(color: Colors.white38, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Guide Grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D0B0F),
              ),
              child: Column(
                children: [
                  // Time header row (Matches Image 0120 top)
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF131016),
                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                    ),
                    child: Row(
                      children: [
                        _buildCorner(),
                        Expanded(child: _buildTimeHeader()),
                      ],
                    ),
                  ),
                  // Channel rail + programs
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: _channelRailWidth,
                          child: ListView.builder(
                            controller: _channelV,
                            itemExtent: _rowHeight,
                            itemCount: channels.length,
                            itemBuilder: (context, i) =>
                                _buildChannelHeader(channels[i], i),
                          ),
                        ),
                        Expanded(child: _buildProgramGrid(channels)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildCorner() {
    return Container(
      width: _channelRailWidth,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF131016),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'CHANNELS',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeHeader() {
    return ListView.builder(
      controller: _timeH,
      scrollDirection: Axis.horizontal,
      itemCount: 48, // 24 hours
      itemBuilder: (context, i) {
        final t = _startTime.add(Duration(minutes: i * 30));
        return Container(
          width: 30 * _pixelsPerMinute,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Text(
            DateFormat('h:mm a').format(t).toLowerCase(),
            style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2),
          ),
        );
      },
    );
  }

  Widget _buildChannelHeader(IptvMedia channel, int index) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: channel)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0B0F),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            right: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        child: Row(
          children: [
            // Channel logo (IMG_0120 style)
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: channel.logo.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: channel.logo,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.live_tv_rounded,
                          size: 24,
                          color: Colors.white24),
                    )
                  : const Icon(Icons.live_tv_rounded,
                      size: 24, color: Colors.white24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(channel.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildProgramGrid(List<IptvMedia> channels) {
    final totalWidth = 48 * 30 * _pixelsPerMinute; // 24 hours
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => false,
      child: SingleChildScrollView(
        controller: _programH,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          child: Stack(
            children: [
              ListView.builder(
                controller: _programV,
                itemExtent: _rowHeight,
                itemCount: channels.length,
                itemBuilder: (context, i) =>
                    _buildProgramRow(channels[i], i),
              ),
              // "Now" line (Sakura Glow)
              Positioned(
                left: DateTime.now().difference(_startTime).inMinutes *
                    _pixelsPerMinute,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9B3FF),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE9B3FF).withValues(alpha: 0.8),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgramRow(IptvMedia channel, int channelIndex) {
    final programs = widget.provider.getEpgForChannel(channel.tvgId);
    final accentColor = _colorForIndex(channelIndex);

    return Container(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
      ),
      child: Stack(
        children: [
          // 30-min grid lines
          ...List.generate(24, (i) => Positioned(
                left: i * 30 * _pixelsPerMinute,
                top: 0,
                bottom: 0,
                child: Container(
                    width: 1,
                    color: Colors.white.withValues(alpha: 0.03)),
              )),
          if (programs.isEmpty)
            _noGuideBubble(channel, accentColor)
          else
            ...programs.map((p) => _programBubble(p, channel, accentColor)),
        ],
      ),
    );
  }

  Widget _noGuideBubble(IptvMedia channel, Color accent) {
    return Positioned(
      left: 8,
      top: 10,
      bottom: 10,
      width: 220,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: channel)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.15)),
          ),
          child: const Text('No guide data',
              style: TextStyle(
                  color: Colors.white30,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _programBubble(
      EpgEntry entry, IptvMedia channel, Color accentColor) {
    final now = DateTime.now();
    final isLive = entry.start.isBefore(now) && entry.end.isAfter(now);
    final isPast = entry.end.isBefore(now);

    final startDiff = entry.start.difference(_startTime).inMinutes;
    final duration = entry.end.difference(entry.start).inMinutes;
    if (startDiff + duration < 0 || startDiff > 12 * 60) {
      return const SizedBox.shrink();
    }

    final left = startDiff.clamp(0, 48 * 30) * _pixelsPerMinute;
    final visibleDur = duration - (startDiff < 0 ? -startDiff : 0);
    final width = (visibleDur * _pixelsPerMinute - 4).clamp(40.0, 1000.0);

    return Positioned(
      left: left.toDouble(),
      width: width,
      top: 6,
      bottom: 6,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: channel)),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: isLive
                ? accentColor.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isLive
                  ? accentColor.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.06),
              width: isLive ? 1.2 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      style: TextStyle(
                        color: isPast ? Colors.white30 : Colors.white,
                        fontSize: 12,
                        fontWeight:
                            isLive ? FontWeight.w800 : FontWeight.w600,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isLive) ...[
                    const SizedBox(width: 6),
                    _badge('LIVE', accentColor),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('h:mm a').format(entry.start)} - ${DateFormat('h:mm a').format(entry.end)}',
                style: TextStyle(
                  color: isLive
                      ? accentColor.withValues(alpha: 0.7)
                      : Colors.white24,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}


// ─── Keep-alive wrapper ───────────────────────────────────────────────────────

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _IptvDebugWindow extends StatefulWidget {
  final IptvProvider provider;
  const _IptvDebugWindow({required this.provider});

  @override
  State<_IptvDebugWindow> createState() => _IptvDebugWindowState();
}

class _IptvDebugWindowState extends State<_IptvDebugWindow> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(_IptvDebugWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.provider.debugLogs;

    return Container(
      height: 200,
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9B3FF).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, size: 14, color: Color(0xFFE9B3FF)),
                const SizedBox(width: 8),
                const Text(
                  'IPTV DEBUG CONSOLE',
                  style: TextStyle(
                    color: Color(0xFFE9B3FF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => widget.provider.clearLogs(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('CLEAR', style: TextStyle(color: Colors.white24, fontSize: 10)),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    log,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
