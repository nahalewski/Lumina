import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/iptv_pip_provider.dart';
import '../screens/iptv_player_screen.dart';

class IptvPipOverlay extends StatelessWidget {
  const IptvPipOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<IptvPipProvider>(
      builder: (context, pip, child) {
        if (!pip.pipActive || pip.currentMedia == null) {
          return const SizedBox.shrink();
        }

        return Positioned(
          bottom: 24,
          right: 24,
          child: GestureDetector(
            onTap: () {
              if (pip.currentMedia != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => IptvPlayerScreen(media: pip.currentMedia!),
                  ),
                );
              }
            },
            child: Container(
              width: 312,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.78),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 18, spreadRadius: 2),
              ],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: pip.currentMedia!.logo.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: pip.currentMedia!.logo,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _fallbackIcon(),
                          )
                        : _fallbackIcon(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pip.currentMedia!.name,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pip.currentMedia!.isLive ? 'Live TV' : pip.currentMedia!.group,
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _ActionChip(
                            icon: pip.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            label: pip.isPlaying ? 'Pause' : 'Play',
                            onTap: () => pip.togglePlayPause(),
                          ),
                          const SizedBox(width: 8),
                          _ActionChip(
                            icon: Icons.close_rounded,
                            label: 'Stop',
                            onTap: () => pip.closePip(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 60,
                  color: Colors.white.withOpacity(0.08),
                ),
                const SizedBox(width: 8),
                Icon(Icons.open_in_full_rounded, color: Colors.white70, size: 22),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackIcon() {
    return Container(
      color: Colors.white12,
      child: const Center(
        child: Icon(Icons.live_tv_rounded, color: Colors.white30, size: 30),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
