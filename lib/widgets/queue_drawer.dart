import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/media_provider.dart';
import '../models/media_model.dart';

/// Slide-out panel showing the playback queue with drag-to-reorder
class QueueDrawer extends StatelessWidget {
  final VoidCallback? onPlayMedia;

  const QueueDrawer({super.key, this.onPlayMedia});

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, provider, _) {
        final queue = provider.playbackQueue;

        return Container(
          width: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF131315),
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.queue_music_rounded, color: Color(0xFFAAC7FF), size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'Up Next',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Manrope',
                      ),
                    ),
                    const Spacer(),
                    if (queue.isNotEmpty)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => provider.clearQueue(),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              'Clear',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Queue items
              if (queue.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.playlist_add_rounded, size: 48, color: Colors.white10),
                        SizedBox(height: 12),
                        Text(
                          'Queue is empty',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tap the queue icon on any episode to add it',
                          style: TextStyle(color: Colors.white24, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: queue.length,
                    onReorder: provider.reorderQueue,
                    itemBuilder: (context, index) {
                      final item = queue[index];
                      return _QueueItem(
                        key: ValueKey(item.id),
                        media: item,
                        index: index,
                        isFirst: index == 0,
                        onRemove: () => provider.removeFromQueue(index),
                        onPlay: () {
                          provider.playMedia(item);
                          onPlayMedia?.call();
                        },
                      );
                    },
                  ),
                ),

              // Bottom: Play All button
              if (queue.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        provider.playMedia(queue.first);
                        onPlayMedia?.call();
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text('Play All (${queue.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A84FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _QueueItem extends StatelessWidget {
  final MediaFile media;
  final int index;
  final bool isFirst;
  final VoidCallback onRemove;
  final VoidCallback onPlay;

  const _QueueItem({
    super.key,
    required this.media,
    required this.index,
    required this.isFirst,
    required this.onRemove,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isFirst
              ? const Color(0xFF0A84FF).withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFirst
                ? const Color(0xFF0A84FF).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isFirst
                  ? const Color(0xFF0A84FF).withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: isFirst ? const Color(0xFF0A84FF) : Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          title: Text(
            media.title,
            style: TextStyle(
              color: isFirst ? const Color(0xFFAAC7FF) : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            media.animeTitle ?? media.extension.toUpperCase(),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPlay,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.play_arrow_rounded, color: Colors.white.withValues(alpha: 0.5), size: 18),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.3), size: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
