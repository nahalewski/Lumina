import 'package:flutter/material.dart';
import '../../themes/sakura_theme.dart';

class EpgChannel {
  final String id;
  final String name;
  final String icon;

  EpgChannel({required this.id, required this.name, required this.icon});
}

class EpgProgram {
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final double progress;

  EpgProgram({
    required this.title,
    required this.startTime,
    required this.endTime,
    this.progress = 0.0,
  });

  int get durationInMinutes => endTime.difference(startTime).inMinutes;
}

class TvGuideScreen extends StatefulWidget {
  const TvGuideScreen({super.key});

  @override
  State<TvGuideScreen> createState() => _TvGuideScreenState();
}

class _TvGuideScreenState extends State<TvGuideScreen> {
  double get _channelWidth => MediaQuery.of(context).size.width < 600 ? 120 : 200;
  final double _minuteWidth = 10; // 10px per minute, so 30 mins = 300px
  final ScrollController _horizontalController = ScrollController();

  final List<EpgChannel> _channels = [
    EpgChannel(id: 'S1', name: 'Sakura Cinema', icon: 'S1'),
    EpgChannel(id: 'N24', name: 'Global News', icon: 'N24'),
    EpgChannel(id: 'ART', name: 'Art & History', icon: 'ART'),
    EpgChannel(id: 'D1', name: 'Discovery One', icon: 'D1'),
    EpgChannel(id: 'H1', name: 'HBO Plus', icon: 'H1'),
    EpgChannel(id: 'M1', name: 'Movie Central', icon: 'M1'),
  ];

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      margin: EdgeInsets.all(isMobile ? 12 : 32),
      decoration: BoxDecoration(
        color: SakuraTheme.surfaceContainerLow.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Timeline Header
          _buildTimelineHeader(),
          // Channels & Programs
          Expanded(
            child: ListView.builder(
              itemCount: _channels.length,
              itemBuilder: (context, index) {
                return _buildChannelRow(_channels[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineHeader() {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        color: Colors.black.withValues(alpha: 0.2),
      ),
      child: Row(
        children: [
          Container(
            width: _channelWidth,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width < 600 ? 16 : 32),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: const Text(
              'Channels',
              style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(10, (i) {
                  final time = DateTime(2026, 4, 25, 20, i * 30);
                  return Container(
                    width: 30 * _minuteWidth,
                    alignment: Alignment.center,
                    child: Text(
                      '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: i == 1 ? SakuraTheme.sakuraPink : Colors.white24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelRow(EpgChannel channel) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          // Channel Info
          Container(
            width: _channelWidth,
            padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width < 600 ? 8 : 24),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Row(
              children: [
                if (MediaQuery.of(context).size.width >= 400)
                  Container(
                    width: 44,
                    height: 44,
                  decoration: BoxDecoration(
                    color: SakuraTheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    channel.id,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: SakuraTheme.sakuraPink),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    channel.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Programs
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Ideally this scroll controller would be synced with the header
              child: Row(
                children: [
                  _buildProgramBlock(
                    EpgProgram(
                      title: 'Neon Nights (Live)',
                      startTime: DateTime(2026, 4, 25, 20, 0),
                      endTime: DateTime(2026, 4, 25, 21, 30),
                      progress: 0.65,
                    ),
                    isLive: true,
                  ),
                  _buildProgramBlock(
                    EpgProgram(
                      title: 'The Glass Garden',
                      startTime: DateTime(2026, 4, 25, 21, 30),
                      endTime: DateTime(2026, 4, 25, 23, 0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramBlock(EpgProgram program, {bool isLive = false}) {
    final width = program.durationInMinutes * _minuteWidth;
    
    return Focus(
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: width,
            height: 64,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isLive 
                ? SakuraTheme.sakuraPink.withValues(alpha: isFocused ? 0.3 : 0.2)
                : Colors.white.withValues(alpha: isFocused ? 0.1 : 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLive 
                  ? SakuraTheme.sakuraPink.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.05),
              ),
              boxShadow: isFocused ? [
                BoxShadow(
                  color: SakuraTheme.sakuraPink.withValues(alpha: 0.3),
                  blurRadius: 20,
                )
              ] : [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  program.title,
                  style: TextStyle(
                    color: isLive ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isLive) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: program.progress,
                            child: Container(
                              decoration: BoxDecoration(
                                color: SakuraTheme.sakuraPink,
                                boxShadow: [
                                  BoxShadow(
                                    color: SakuraTheme.sakuraPink.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  )
                                ],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(program.progress * 100).toInt()}%',
                        style: const TextStyle(color: SakuraTheme.sakuraPink, fontSize: 10),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    '${program.startTime.hour}:${program.startTime.minute.toString().padLeft(2, '0')} - ${program.endTime.hour}:${program.endTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.white24, fontSize: 10),
                  ),
              ],
            ),
          );
        }
      ),
    );
  }
}
