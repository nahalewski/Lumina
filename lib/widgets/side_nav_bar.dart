import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/media_provider.dart';

/// Lumina Media sidebar navigation - glassmorphism design
class SideNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const SideNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        color: const Color(0xFF131315).withValues(alpha: 0.4),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Logo
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFAAC7FF), Color(0xFFE9B3FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: Color(0xFF002957),
                          size: 18,
                        ),
                      ),
                      Consumer<MediaProvider>(
                        builder: (context, provider, _) {
                          bool isActive = provider.processingStatus.values
                              .any((s) => s != 'Done' && s != 'Error');
                          if (!isActive) return const SizedBox.shrink();

                          return Positioned(
                            top: -1,
                            right: -1,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0A84FF),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0xFF1A1A1C), width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0A84FF)
                                        .withValues(alpha: 0.5),
                                    blurRadius: 4,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lumina',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'MEDIA',
                        style: TextStyle(
                          fontSize: 10,
                          color: const Color(0xFFAAC7FF).withValues(alpha: 0.8),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Navigation items
            _NavItem(
              icon: Icons.movie_rounded,
              label: 'Movies',
              isSelected: selectedIndex == 0,
              onTap: () => onItemSelected(0),
            ),
            _NavItem(
              icon: Icons.tv_rounded,
              label: 'TV Shows',
              isSelected: selectedIndex == 2,
              onTap: () => onItemSelected(2),
            ),
            _NavItem(
              icon: Icons.public_rounded,
              label: 'Web Browser',
              isSelected: selectedIndex == 1,
              onTap: () => onItemSelected(1),
            ),
            Consumer<MediaProvider>(
              builder: (context, provider, _) {
                if (!provider.settings.showNsfwTab) {
                  return const SizedBox.shrink();
                }

                return _NavItem(
                  icon: Icons.lock_open_rounded,
                  label: 'Not Safe for Work',
                  isSelected: selectedIndex == 11,
                  onTap: () => onItemSelected(11),
                );
              },
            ),
            _NavItem(
              icon: Icons.play_circle_filled_rounded,
              label: 'Now Playing',
              isSelected: selectedIndex == 4,
              onTap: () => onItemSelected(4),
            ),
            _NavItem(
              icon: Icons.library_music_rounded,
              label: 'Music Library',
              isSelected: selectedIndex == 9,
              onTap: () => onItemSelected(9),
            ),
            _NavItem(
              icon: Icons.menu_book_rounded,
              label: 'E-books',
              isSelected: selectedIndex == 12,
              onTap: () => onItemSelected(12),
            ),
            _NavItem(
              icon: Icons.auto_stories_rounded,
              label: 'Manga',
              isSelected: selectedIndex == 13,
              onTap: () => onItemSelected(13),
            ),
            _NavItem(
              icon: Icons.collections_bookmark_rounded,
              label: 'Comics',
              isSelected: selectedIndex == 14,
              onTap: () => onItemSelected(14),
            ),
            _NavItem(
              icon: Icons.smart_display_rounded,
              label: 'YouTube',
              isSelected: selectedIndex == 16,
              onTap: () => onItemSelected(16),
            ),
            // ─── IPTV Section ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Row(
                children: [
                  Text(
                    'IPTV',
                    style: TextStyle(
                      fontSize: 10,
                      color: const Color(0xFFAAC7FF).withValues(alpha: 0.5),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Divider(
                          color: Colors.white.withValues(alpha: 0.05),
                          height: 1)),
                ],
              ),
            ),
            _NavItem(
              icon: Icons.live_tv_rounded,
              label: 'Live TV',
              isSelected: selectedIndex == 6,
              onTap: () => onItemSelected(6),
            ),
            _NavItem(
              icon: Icons.movie_rounded,
              label: 'Movies',
              isSelected: selectedIndex == 7,
              onTap: () => onItemSelected(7),
            ),
            _NavItem(
              icon: Icons.tv_rounded,
              label: 'TV Shows',
              isSelected: selectedIndex == 8,
              onTap: () => onItemSelected(8),
            ),
            _NavItem(
              icon: Icons.manage_accounts_rounded,
              label: 'User Management',
              isSelected: selectedIndex == 10,
              onTap: () => onItemSelected(10),
            ),
            _NavItem(
              icon: Icons.download_rounded,
              label: 'Downloads',
              isSelected: selectedIndex == 15,
              onTap: () => onItemSelected(15),
            ),
            const SizedBox(height: 16),
            // Settings
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 8),
                  _NavItem(
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    isSelected: selectedIndex == 3,
                    onTap: () => onItemSelected(3),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFE9B3FF).withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(
                      color: const Color(0xFFE9B3FF).withValues(alpha: 0.2),
                      width: 0.5)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? const Color(0xFFE9B3FF)
                      : Colors.white.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 0.2,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
