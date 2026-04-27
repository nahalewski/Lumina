import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../themes/sakura_theme.dart';

class TvSideNav extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const TvSideNav({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  State<TvSideNav> createState() => _TvSideNavState();
}

class _TvSideNavState extends State<TvSideNav> {
  bool _isExpanded = false;
  final FocusScopeNode _focusScopeNode = FocusScopeNode();

  @override
  void dispose() {
    _focusScopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        setState(() {
          _isExpanded = hasFocus;
        });
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isMobile = MediaQuery.of(context).size.width < 600;
          final double expandedWidth = isMobile ? 220 : 280;
          // Always show collapsed icons (72px) so nav is never invisible
          final double collapsedWidth = isMobile ? 72 : 100;
          
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            width: _isExpanded ? expandedWidth : collapsedWidth,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  decoration: BoxDecoration(
                    color: SakuraTheme.background.withValues(alpha: 0.8),
                    border: Border(
                      right: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 50,
                        offset: const Offset(20, 0),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 60),
                        // Logo / Brand
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cinema',
                                style: TextStyle(
                                  fontSize: isMobile ? 24 : 32,
                                  fontWeight: FontWeight.bold,
                                  color: SakuraTheme.sakuraPink,
                                  shadows: [
                                    Shadow(
                                      color: SakuraTheme.sakuraPink.withValues(alpha: 0.4),
                                      blurRadius: 15,
                                    ),
                                  ],
                                ),
                              ),
                              if (_isExpanded)
                                Text(
                                  'Premium',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: SakuraTheme.sakuraPink.withValues(alpha: 0.6),
                                    letterSpacing: 2,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 60),
                        // Nav Items
                        FocusScope(
                          node: _focusScopeNode,
                          child: Column(
                            children: [
                              _TvNavItem(
                                icon: Icons.movie_rounded,
                                label: 'Movies',
                                isSelected: widget.selectedIndex == 7,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(7),
                              ),
                              _TvNavItem(
                                icon: Icons.tv_rounded,
                                label: 'TV Shows',
                                isSelected: widget.selectedIndex == 8,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(8),
                              ),
                              const Divider(color: Colors.white10, height: 16),
                              _TvNavItem(
                                icon: Icons.live_tv_rounded,
                                label: 'Live TV',
                                isSelected: widget.selectedIndex == 0,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(0),
                              ),
                              _TvNavItem(
                                icon: Icons.grid_view_rounded,
                                label: 'TV Guide',
                                isSelected: widget.selectedIndex == 1,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(1),
                              ),
                              _TvNavItem(
                                icon: Icons.movie_filter_rounded,
                                label: 'IPTV Movies',
                                isSelected: widget.selectedIndex == 2,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(2),
                              ),
                              _TvNavItem(
                                icon: Icons.video_library_rounded,
                                label: 'IPTV Series',
                                isSelected: widget.selectedIndex == 3,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(3),
                              ),
                              const Divider(color: Colors.white10, height: 16),
                              _TvNavItem(
                                icon: Icons.menu_book_rounded,
                                label: 'E-books',
                                isSelected: widget.selectedIndex == 4,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(4),
                              ),
                              _TvNavItem(
                                icon: Icons.auto_stories_rounded,
                                label: 'Manga',
                                isSelected: widget.selectedIndex == 5,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(5),
                              ),
                              _TvNavItem(
                                icon: Icons.collections_bookmark_rounded,
                                label: 'Comics',
                                isSelected: widget.selectedIndex == 6,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(6),
                              ),
                              const Divider(color: Colors.white10, height: 16),
                              _TvNavItem(
                                icon: Icons.play_circle_outline_rounded,
                                label: 'Playing',
                                isSelected: widget.selectedIndex == 9,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(9),
                              ),
                              _TvNavItem(
                                icon: Icons.settings_rounded,
                                label: 'Settings',
                                isSelected: widget.selectedIndex == 10,
                                isExpanded: _isExpanded,
                                onTap: () => widget.onItemSelected(10),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                        // User Profile at bottom
                        _buildUserProfile(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUserProfile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SakuraTheme.sakuraPink.withValues(alpha: 0.2)),
            ),
            child: const CircleAvatar(
              backgroundColor: SakuraTheme.surfaceContainer,
              child: Icon(Icons.person_rounded, color: SakuraTheme.sakuraPink),
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Alex Mercer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: SakuraTheme.onSurface,
                  ),
                ),
                Text(
                  'SUBSCRIBER',
                  style: TextStyle(
                    fontSize: 10,
                    color: SakuraTheme.sakuraPink.withValues(alpha: 0.5),
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ],

        ],
      ),
    );
  }
}

class _TvNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  const _TvNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_TvNavItem> createState() => _TvNavItemState();
}

class _TvNavItemState extends State<_TvNavItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        setState(() {
          _isFocused = hasFocus;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && 
            (event.logicalKey == LogicalKeyboardKey.enter || 
             event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 64,
        width: double.infinity,
        decoration: BoxDecoration(
          border: widget.isSelected 
            ? const Border(left: BorderSide(color: SakuraTheme.sakuraPink, width: 4))
            : null,
          gradient: widget.isSelected 
            ? LinearGradient(
                colors: [SakuraTheme.sakuraPink.withValues(alpha: 0.1), Colors.transparent],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
          color: _isFocused ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 28,
              color: (widget.isSelected || _isFocused)
                  ? SakuraTheme.sakuraPink
                  : Colors.white.withValues(alpha: 0.5),
            ),
            if (widget.isExpanded) ...[
              const SizedBox(width: 20),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: (widget.isSelected || _isFocused)
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
