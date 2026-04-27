import 'package:flutter/material.dart';
import '../services/download_service.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadService _downloadService = DownloadService();
  List<DownloadTask> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeDownloads();
  }

  Future<void> _initializeDownloads() async {
    await _downloadService.initialize();
    _downloadService.onTaskListChanged = () {
      setState(() {
        _tasks = _downloadService.tasks;
      });
    };
    _downloadService.onProgress = (_, __, ___, ____) {
      setState(() {
        _tasks = _downloadService.tasks;
      });
    };
    setState(() {
      _tasks = _downloadService.tasks;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _downloadService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Downloads',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Manage browser downloads and open the download folder.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'Download directory: ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                ),
              ),
              Expanded(
                child: Text(
                  _downloadService.downloadDirectory,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.56),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _downloadService.openDownloadDirectory,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: const Text('Open Folder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2B2B34),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1C).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
              child: _buildContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_for_offline_rounded,
                size: 44, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              'No downloads yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.download_rounded,
                  size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              const Text(
                'Download Tasks',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_tasks.any((t) => t.status == DownloadStatus.completed))
                TextButton(
                  onPressed: () async {
                    await _downloadService.clearCompleted();
                  },
                  child: const Text(
                    'Clear Completed',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _tasks.length,
            itemBuilder: (context, index) {
              return _buildTaskTile(_tasks[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTaskTile(DownloadTask task) {
    IconData statusIcon;
    Color statusColor;
    String statusText;
    Widget actionWidget;

    switch (task.status) {
      case DownloadStatus.pending:
        statusIcon = Icons.hourglass_empty_rounded;
        statusColor = Colors.orange;
        statusText = 'Pending';
        actionWidget = IconButton(
          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
          onPressed: () => _downloadService.removeTask(task.id),
        );
        break;
      case DownloadStatus.downloading:
        statusIcon = Icons.downloading_rounded;
        statusColor = const Color(0xFF0A84FF);
        statusText = '${(task.progress * 100).round()}%';
        actionWidget = IconButton(
          icon: const Icon(Icons.cancel_rounded, size: 18, color: Colors.white54),
          onPressed: () => _downloadService.cancelDownload(task.id),
        );
        break;
      case DownloadStatus.completed:
        statusIcon = Icons.check_circle_rounded;
        statusColor = const Color(0xFF42E355);
        statusText = 'Completed';
        actionWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.folder_open_rounded, size: 18, color: Colors.white54),
              tooltip: 'Open Folder',
              onPressed: () => _downloadService.openDownloadDirectory(),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
              onPressed: () => _downloadService.removeTask(task.id),
            ),
          ],
        );
        break;
      case DownloadStatus.failed:
        statusIcon = Icons.error_rounded;
        statusColor = Colors.red;
        statusText = 'Failed';
        actionWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white54),
              tooltip: 'Retry',
              onPressed: () => _downloadService.retryDownload(task.id),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
              onPressed: () => _downloadService.removeTask(task.id),
            ),
          ],
        );
        break;
      case DownloadStatus.cancelled:
        statusIcon = Icons.cancel_rounded;
        statusColor = Colors.white54;
        statusText = 'Cancelled';
        actionWidget = IconButton(
          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
          onPressed: () => _downloadService.removeTask(task.id),
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon, size: 20, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  task.url,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(color: statusColor.withValues(alpha: 0.8), fontSize: 12),
                ),
                if (task.status == DownloadStatus.downloading)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: task.progress,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF0A84FF)),
                        minHeight: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          actionWidget,
        ],
      ),
    );
  }
}
