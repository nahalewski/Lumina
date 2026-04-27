import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/iptv_provider.dart';
import '../services/iptv_service.dart';
import 'iptv_player_screen.dart';

class IptvLiveScreen extends StatefulWidget {
  const IptvLiveScreen({super.key});

  @override
  State<IptvLiveScreen> createState() => _IptvLiveScreenState();
}

class _IptvLiveScreenState extends State<IptvLiveScreen> with TickerProviderStateMixin {
  String _searchQuery = '';
  bool _isGuideView = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  final List<String> _filterOptions = [
    'USA',
    'Latino',
    'Sports',
    'Movies',
    'XXX',
    'News',
    'Kids'
  ];
  final Set<String> _selectedFilters = {};

  @override
  Widget build(BuildContext context) {
    return Consumer<IptvProvider>(
      builder: (context, provider, _) {
        return Column(
          children: [
            // Tab Bar
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFFE9B3FF),
              unselectedLabelColor: Colors.white54,
              indicatorColor: const Color(0xFFE9B3FF),
              tabs: const [
                Tab(text: 'Live'),
                Tab(text: 'Movies'),
                Tab(text: 'Series'),
              ],
            ),
            
            // Header with View Toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.live_tv_rounded,
                        color: Color(0xFFFF4444), size: 22),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isGuideView ? 'TV Guide' : 'Live Channels',
                        style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      Text(
                        _isGuideView
                            ? 'Timeline of what\'s on'
                            : 'Browse by category',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // View Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _ViewToggleBtn(
                          icon: Icons.grid_view_rounded,
                          isSelected: !_isGuideView,
                          onTap: () => setState(() => _isGuideView = false),
                        ),
                        _ViewToggleBtn(
                          icon: Icons.view_timeline_rounded,
                          isSelected: _isGuideView,
                          onTap: () => setState(() => _isGuideView = true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white54),
                    onPressed: () {
                      provider.loadMedia(forceRefresh: true);
                      provider.loadEpg(forceRefresh: true);
                    },
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search channels...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.white24),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white24, size: 18),
                                onPressed: () =>
                                    setState(() => _searchQuery = ''),
                              ),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _filterOptions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final filter = _filterOptions[index];
                        final selected = _selectedFilters.contains(filter);
                        return ChoiceChip(
                          label: Text(filter,
                              style: TextStyle(
                                  color:
                                      selected ? Colors.black : Colors.white)),
                          selected: selected,
                          selectedColor: const Color(0xFFAAC7FF),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          onSelected: (_) {
                            setState(() {
                              if (selected) {
                                _selectedFilters.remove(filter);
                              } else {
                                _selectedFilters.add(filter);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Live TV
                  _KeepAliveWrapper(
                    child: provider.isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFFF4444)))
                        : _isGuideView
                            ? IptvGuideTimeline(
                                provider: provider,
                                channels:
                                    _filteredChannels(provider.liveChannels),
                              )
                            : _buildCategoryView(provider),
                  ),

                  // Movies
                  _KeepAliveWrapper(
                    child: provider.isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFFF4444)))
                        : _buildCategoryViewWithData(provider.movies),
                  ),

                  // Series
                  _KeepAliveWrapper(
                    child: provider.isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFFF4444)))
                        : _buildCategoryViewWithData(provider.tvShows),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<IptvMedia> _filteredChannels(List<IptvMedia> channels) {
    final query = _searchQuery.trim().toLowerCase();

    return channels.where((channel) {
      if (_selectedFilters.isNotEmpty) {
        final channelGroup = channel.group.toLowerCase();
        final channelName =
            channel.tvgName?.toLowerCase() ?? channel.name.toLowerCase();
        final matchesFilter = _selectedFilters.any((filter) {
          final lower = filter.toLowerCase();
          return channelGroup.contains(lower) || channelName.contains(lower);
        });
        if (!matchesFilter) return false;
      }

      if (query.isEmpty) return true;
      final lowerName =
          channel.tvgName?.toLowerCase() ?? channel.name.toLowerCase();
      return lowerName.contains(query) ||
          channel.group.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildCategoryView(IptvProvider provider) {
    return _buildCategoryViewWithData(provider.liveChannels);
  }
  
  Widget _buildCategoryViewWithData(List<IptvMedia> mediaList) {
    final filtered = _filteredChannels(mediaList);

    final Map<String, List<IptvMedia>> categoryMap = {};
    for (final item in filtered) {
      categoryMap.putIfAbsent(item.group, () => []);
      categoryMap[item.group]!.add(item);
    }
    final sortedCategories = categoryMap.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
        final categoryItems = categoryMap[category]!;
        return _CategoryRow(
            category: category, channels: categoryItems, provider: Provider.of<IptvProvider>(context, listen: false));
      },
    );
  }
}

class _ViewToggleBtn extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewToggleBtn(
      {required this.icon, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFE9B3FF).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon,
            size: 20,
            color: isSelected ? const Color(0xFFE9B3FF) : Colors.white24),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String category;
  final List<IptvMedia> channels;
  final IptvProvider provider;

  const _CategoryRow(
      {required this.category, required this.channels, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(category,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final channel = channels[index];
                return _ChannelCard(channel: channel, provider: provider);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final IptvMedia channel;
  final IptvProvider provider;

  const _ChannelCard({required this.channel, required this.provider});

  @override
  Widget build(BuildContext context) {
    final currentProgram = provider.getCurrentProgram(channel.tvgId);
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => IptvPlayerScreen(media: channel)));
      },
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8)),
                  child: channel.logo.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                              imageUrl: channel.logo, fit: BoxFit.contain))
                      : const Icon(Icons.live_tv, color: Colors.white12),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(channel.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
              ],
            ),
            const Spacer(),
            if (currentProgram != null) ...[
              Text(currentProgram.title,
                  style: const TextStyle(
                      color: Color(0xFFE9B3FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              _buildProgress(currentProgram),
            ] else
              const Text('No Guide',
                  style: TextStyle(color: Colors.white12, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(EpgEntry entry) {
    final now = DateTime.now();
    final total = entry.end.difference(entry.start).inMinutes;
    final elapsed = now.difference(entry.start).inMinutes;
    final progress = (elapsed / total).clamp(0.0, 1.0);
    return LinearProgressIndicator(
        value: progress,
        backgroundColor: Colors.white10,
        valueColor: const AlwaysStoppedAnimation(Color(0xFFE9B3FF)),
        minHeight: 2,
        borderRadius: BorderRadius.circular(2));
  }
}

/// The Timeline Guide View
class IptvGuideTimeline extends StatefulWidget {
  final IptvProvider provider;
  final List<IptvMedia> channels;
  const IptvGuideTimeline(
      {super.key, required this.provider, required this.channels});

  @override
  State<IptvGuideTimeline> createState() => _IptvGuideTimelineState();
}

class _IptvGuideTimelineState extends State<IptvGuideTimeline> {
  late DateTime _startTime;
  final double _pixelsPerMinute = 2.8;
  final double _channelRailWidth = 206;
  final double _rowHeight = 76;
  final ScrollController _programVerticalController = ScrollController();
  final ScrollController _channelVerticalController = ScrollController();
  final ScrollController _programHorizontalController = ScrollController();
  final ScrollController _timeHorizontalController = ScrollController();
  bool _syncingVertical = false;
  bool _syncingHorizontal = false;

  @override
  void initState() {
    super.initState();
    // Start timeline 3 hours ago so the user can scrub back and forward.
    _startTime = DateTime.now().subtract(const Duration(hours: 3));
    // Round to nearest 30 mins
    _startTime = DateTime(
      _startTime.year,
      _startTime.month,
      _startTime.day,
      _startTime.hour,
      (_startTime.minute / 30).floor() * 30,
    );
    _programVerticalController.addListener(_syncChannelRail);
    _channelVerticalController.addListener(_syncProgramRows);
    _programHorizontalController.addListener(_syncTimeHeader);
    _timeHorizontalController.addListener(_syncProgramTimeline);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToNow());
  }

  @override
  void dispose() {
    _programVerticalController
      ..removeListener(_syncChannelRail)
      ..dispose();
    _channelVerticalController
      ..removeListener(_syncProgramRows)
      ..dispose();
    _programHorizontalController
      ..removeListener(_syncTimeHeader)
      ..dispose();
    _timeHorizontalController
      ..removeListener(_syncProgramTimeline)
      ..dispose();
    super.dispose();
  }

  void _syncChannelRail() {
    if (_syncingVertical || !_channelVerticalController.hasClients) return;
    _syncingVertical = true;
    _channelVerticalController.jumpTo(
      _programVerticalController.offset.clamp(
        0.0,
        _channelVerticalController.position.maxScrollExtent,
      ),
    );
    _syncingVertical = false;
  }

  void _syncProgramRows() {
    if (_syncingVertical || !_programVerticalController.hasClients) return;
    _syncingVertical = true;
    _programVerticalController.jumpTo(
      _channelVerticalController.offset.clamp(
        0.0,
        _programVerticalController.position.maxScrollExtent,
      ),
    );
    _syncingVertical = false;
  }

  void _syncTimeHeader() {
    if (_syncingHorizontal || !_timeHorizontalController.hasClients) return;
    _syncingHorizontal = true;
    _timeHorizontalController.jumpTo(
      _programHorizontalController.offset.clamp(
        0.0,
        _timeHorizontalController.position.maxScrollExtent,
      ),
    );
    _syncingHorizontal = false;
  }

  void _syncProgramTimeline() {
    if (_syncingHorizontal || !_programHorizontalController.hasClients) return;
    _syncingHorizontal = true;
    _programHorizontalController.jumpTo(
      _timeHorizontalController.offset.clamp(
        0.0,
        _programHorizontalController.position.maxScrollExtent,
      ),
    );
    _syncingHorizontal = false;
  }

  void _scrollTimeline(int minutes) {
    if (!_programHorizontalController.hasClients) return;
    final target =
        (_programHorizontalController.offset + minutes * _pixelsPerMinute)
            .clamp(0.0, _programHorizontalController.position.maxScrollExtent);
    _programHorizontalController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToNow() {
    if (!_programHorizontalController.hasClients) return;
    final nowOffset =
        DateTime.now().difference(_startTime).inMinutes * _pixelsPerMinute;
    final target = (nowOffset - 240).clamp(
      0.0,
      _programHorizontalController.position.maxScrollExtent,
    );
    _programHorizontalController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final channels = widget.channels;
    if (channels.isEmpty) {
      return const Center(
        child: Text(
          'No live channels found',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
          child: _buildGuideToolbar(),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFFE9B3FF).withValues(alpha: 0.16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE9B3FF).withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Column(
                  children: [
                    SizedBox(
                      height: 46,
                      child: Row(
                        children: [
                          _buildChannelCorner(),
                          Expanded(child: _buildTimeHeader()),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(
                            width: _channelRailWidth,
                            child: ListView.builder(
                              controller: _channelVerticalController,
                              itemExtent: _rowHeight,
                              itemCount: channels.length,
                              itemBuilder: (context, index) {
                                return _buildChannelRowHeader(
                                  channels[index],
                                  index,
                                );
                              },
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
        ),
      ],
    );
  }

  Widget _buildGuideToolbar() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE9B3FF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFE9B3FF).withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: Color(0xFFE9B3FF),
                size: 17,
              ),
              const SizedBox(width: 8),
              Text(
                'Now: ${DateFormat('h:mm a').format(DateTime.now())}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        _TimelineButton(
          icon: Icons.keyboard_arrow_left_rounded,
          label: 'Back',
          onTap: () => _scrollTimeline(-120),
        ),
        const SizedBox(width: 8),
        _TimelineButton(
          icon: Icons.my_location_rounded,
          label: 'Now',
          onTap: _jumpToNow,
        ),
        const SizedBox(width: 8),
        _TimelineButton(
          icon: Icons.keyboard_arrow_right_rounded,
          label: 'Forward',
          onTap: () => _scrollTimeline(120),
        ),
      ],
    );
  }

  Widget _buildChannelCorner() {
    return Container(
      width: _channelRailWidth,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF221820).withValues(alpha: 0.92),
        border: Border(
          right: BorderSide(
            color: const Color(0xFFE9B3FF).withValues(alpha: 0.18),
          ),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: const Row(
        children: [
          Text(
            'CH',
            style: TextStyle(
              color: Color(0xFFE9B3FF),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          SizedBox(width: 12),
          Text(
            'Channels',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramGrid(List<IptvMedia> channels) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => false,
      child: SingleChildScrollView(
        controller: _programHorizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 12 * 60 * _pixelsPerMinute,
          child: Stack(
            children: [
              ListView.builder(
                controller: _programVerticalController,
                itemExtent: _rowHeight,
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  return _buildTimelineRow(channels[index]);
                },
              ),
              Positioned(
                left: DateTime.now().difference(_startTime).inMinutes *
                    _pixelsPerMinute,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9B3FF),
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFFE9B3FF).withValues(alpha: 0.45),
                          blurRadius: 14,
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

  Widget _buildTimeHeader() {
    return ListView.builder(
      controller: _timeHorizontalController,
      scrollDirection: Axis.horizontal,
      itemCount: 24, // 12 hours in 30 min increments
      itemBuilder: (context, index) {
        final time = _startTime.add(Duration(minutes: index * 30));
        return Container(
          width: 30 * _pixelsPerMinute,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF181316).withValues(alpha: 0.82),
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Text(
            DateFormat('h:mm a').format(time),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelRowHeader(IptvMedia channel, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
          right: BorderSide(
            color: const Color(0xFFE9B3FF).withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        color: index.isEven
            ? Colors.white.withValues(alpha: 0.025)
            : Colors.white.withValues(alpha: 0.015),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE9B3FF).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFE9B3FF).withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFFFFD7F5),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (channel.logo.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 32,
                height: 32,
                color: Colors.black.withValues(alpha: 0.24),
                child: CachedNetworkImage(
                  imageUrl: channel.logo,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.live_tv, size: 20),
                ),
              ),
            )
          else
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.live_tv, size: 20, color: Colors.white24),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(channel.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(channel.group,
                    style: const TextStyle(color: Colors.white24, fontSize: 9),
                    maxLines: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineRow(IptvMedia channel) {
    final programs = widget.provider.getEpgForChannel(channel.tvgId);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Stack(
        children: [
          ...List.generate(24, (index) {
            return Positioned(
              left: index * 30 * _pixelsPerMinute,
              top: 0,
              bottom: 0,
              child: Container(
                width: 1,
                color: Colors.white.withValues(alpha: 0.035),
              ),
            );
          }),
          if (programs.isEmpty) _buildNoGuideBubble(channel),
          ...programs.map((p) => _positionProgram(p, channel)),
        ],
      ),
    );
  }

  Widget _positionProgram(EpgEntry entry, IptvMedia channel) {
    final startDiff = entry.start.difference(_startTime).inMinutes;
    final duration = entry.end.difference(entry.start).inMinutes;
    if (startDiff + duration < 0 || startDiff > 12 * 60) {
      return const SizedBox.shrink();
    }

    final left = startDiff.clamp(0, 12 * 60) * _pixelsPerMinute;
    final visibleDuration = duration - (startDiff < 0 ? startDiff.abs() : 0);

    return Positioned(
      left: left.toDouble(),
      width: (visibleDuration * _pixelsPerMinute - 8).clamp(86.0, 560.0),
      top: 9,
      bottom: 9,
      child: _buildProgramBubble(entry, channel),
    );
  }

  Widget _buildNoGuideBubble(IptvMedia channel) {
    return Positioned(
      left: 12,
      top: 12,
      bottom: 12,
      width: 260,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: channel)),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: const Text(
            'No guide data',
            style: TextStyle(
              color: Colors.white30,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgramBubble(EpgEntry entry, IptvMedia channel) {
    final now = DateTime.now();
    final isNow = entry.start.isBefore(now) && entry.end.isAfter(now);
    final isPast = entry.end.isBefore(now);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => IptvPlayerScreen(media: channel)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isNow
              ? const Color(0xFFE9B3FF).withValues(alpha: 0.18)
              : isPast
                  ? Colors.white.withValues(alpha: 0.035)
                  : const Color(0xFFAAC7FF).withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isNow
                ? const Color(0xFFFFD7F5).withValues(alpha: 0.52)
                : Colors.white.withValues(alpha: 0.07),
          ),
          boxShadow: isNow
              ? [
                  BoxShadow(
                    color: const Color(0xFFE9B3FF).withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              entry.title,
              style: TextStyle(
                color: isPast ? Colors.white54 : Colors.white,
                fontSize: 11,
                fontWeight: isNow ? FontWeight.w900 : FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              '${DateFormat('h:mm').format(entry.start)} - ${DateFormat('h:mm a').format(entry.end)}',
              style: TextStyle(
                color: isNow
                    ? const Color(0xFFFFD7F5)
                    : Colors.white.withValues(alpha: 0.28),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TimelineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFFE9B3FF)),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
