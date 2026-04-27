import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows_webview;
import 'package:provider/provider.dart';
import '../services/download_service.dart';
import '../providers/media_provider.dart';

class WebBrowserScreen extends StatefulWidget {
  const WebBrowserScreen({super.key});

  @override
  State<WebBrowserScreen> createState() => _WebBrowserScreenState();
}

class _WebBrowserScreenState extends State<WebBrowserScreen> {
  WebViewController? _controller;
  windows_webview.WebviewController? _windowsController;
  final List<StreamSubscription<dynamic>> _windowsSubscriptions = [];
  final TextEditingController _urlController =
      TextEditingController(text: 'https://www.google.com');
  DownloadService? _downloadService;
  static const String _homeUrl = 'https://www.google.com/webhp?igu=1';

  bool _isLoading = true;
  double _progress = 0;
  String? _detectedVideoUrl;
  double _downloadProgress = 0;
  bool _isDownloading = false;
  bool _showDownloadManager = false;
  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'VideoSniffer',
          onMessageReceived: (message) {
            if (message.message.startsWith('http')) {
              setState(() {
                _detectedVideoUrl = message.message;
              });
            }
          },
        )
        ..addJavaScriptChannel(
          'DownloadInterceptor',
          onMessageReceived: (message) {
            _handleDownloadIntercepted(message.message);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              setState(() {
                _progress = progress / 100.0;
              });
              _injectVideoSniffer();
              _injectDownloadInterceptor();
            },
            onPageStarted: (url) {
              setState(() {
                _isLoading = true;
                _urlController.text = url;
                _detectedVideoUrl = null;
              });
            },
            onPageFinished: (url) {
              setState(() {
                _isLoading = false;
              });
              _injectVideoSniffer();
              _injectDownloadInterceptor();
            },
          ),
        )
        ..loadRequest(Uri.parse(_homeUrl));
    } else if (Platform.isWindows) {
      _initializeWindowsWebView();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_downloadService == null) {
      _downloadService = Provider.of<DownloadService>(context);
      _downloadService!.onProgress = (taskId, progress, received, total) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
          });
        }
      };
    }
  }

  Future<void> _initializeWindowsWebView() async {
    final controller = windows_webview.WebviewController();
    _windowsController = controller;

    try {
      await controller.initialize();
      await controller.setBackgroundColor(Colors.white);
      await controller.setPopupWindowPolicy(
        windows_webview.WebviewPopupWindowPolicy.deny,
      );

      _windowsSubscriptions.add(controller.url.listen((url) {
        if (!mounted) return;
        setState(() {
          _urlController.text = url;
        });
      }));
      _windowsSubscriptions.add(controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() {
          _isLoading = state == windows_webview.LoadingState.loading;
          _progress = _isLoading ? 0.6 : 1;
        });
      }));

      await controller.loadUrl(_homeUrl);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Windows browser could not start: ${e.message ?? e.code}',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _injectVideoSniffer() {
    _controller?.runJavaScript('''
      (function() {
        function checkVideos() {
          const videos = document.querySelectorAll('video');
          for (const v of videos) {
            if (v.src && v.src.startsWith('http')) {
              VideoSniffer.postMessage(v.src);
              return;
            }
            const sources = v.querySelectorAll('source');
            for (const s of sources) {
              if (s.src && s.src.startsWith('http')) {
                VideoSniffer.postMessage(s.src);
                return;
              }
            }
          }
        }
        checkVideos();
        setInterval(checkVideos, 3000);
      })();
    ''');
  }

  void _injectDownloadInterceptor() {
    _controller?.runJavaScript('''
      (function() {
        // Intercept anchor clicks that look like downloads
        document.addEventListener('click', function(e) {
          const link = e.target.closest('a');
          if (!link) return;
          
          const href = link.getAttribute('href');
          if (!href) return;
          
          // Check if it looks like a downloadable file
          const downloadExts = /[.](mp4|mkv|avi|mov|webm|mp3|wav|flac|zip|rar|7z|tar|gz|pdf|srt|ass|ssa|txt|jpg|png|gif|exe|dmg|apk|iso)\$/i;
          const hasDownloadAttr = link.hasAttribute('download');
          const isDownloadLink = hasDownloadAttr || downloadExts.test(href);
          
          if (isDownloadLink) {
            e.preventDefault();
            e.stopPropagation();
            // Resolve relative URLs
            const fullUrl = new URL(href, window.location.href).href;
            DownloadInterceptor.postMessage(JSON.stringify({
              url: fullUrl,
              fileName: link.getAttribute('download') || href.split('/').pop() || 'download'
            }));
          }
        }, true);
        
        // Also intercept form submissions that might be downloads
        document.addEventListener('submit', function(e) {
          const form = e.target;
          const action = form.getAttribute('action');
          if (action && action.includes('download')) {
            // Don't prevent, just notify
            const fullUrl = new URL(action, window.location.href).href;
            DownloadInterceptor.postMessage(JSON.stringify({
              url: fullUrl,
              fileName: action.split('/').pop() || 'download'
            }));
          }
        }, true);
        
        // Watch for dynamically created download links
        const observer = new MutationObserver(function(mutations) {
          mutations.forEach(function(mutation) {
            mutation.addedNodes.forEach(function(node) {
              if (node.nodeType === 1) {
                const links = node.querySelectorAll ? node.querySelectorAll('a[download]') : [];
                links.forEach(function(link) {
                  const href = link.getAttribute('href');
                  if (href) {
                    const fullUrl = new URL(href, window.location.href).href;
                    DownloadInterceptor.postMessage(JSON.stringify({
                      url: fullUrl,
                      fileName: link.getAttribute('download') || href.split('/').pop() || 'download'
                    }));
                  }
                });
              }
            });
          });
        });
        observer.observe(document.body, { childList: true, subtree: true });
      })();
    ''');
  }

  void _handleDownloadIntercepted(String message) {
    try {
      // Try parsing as JSON first
      try {
        final json = jsonDecode(message) as Map<String, dynamic>;
        final url = json['url'] as String?;
        final fileName = json['fileName'] as String?;
        if (url != null) {
          _promptDownload(url, fileName: fileName);
          return;
        }
      } catch (_) {
        // Not JSON, treat as plain URL
        if (message.startsWith('http')) {
          _promptDownload(message);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[BrowserScreen] Error handling intercepted download: $e');
    }
  }

  void _promptDownload(String url, {String? fileName}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Download File',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'URL: $url',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Text(
              'File: ${fileName ?? _downloadService!.extractFileName(url)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(
              'Save to: ${_downloadService!.downloadDirectory}',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startDownloadFromUrl(url, fileName: fileName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A84FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _startDownloadFromUrl(String url, {String? fileName}) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final isMp3 = (fileName ?? _downloadService!.extractFileName(url))
          .toLowerCase()
          .endsWith('.mp3');
      String? customDir;
      
      if (isMp3) {
        final provider = Provider.of<MediaProvider>(context, listen: false);
        customDir = provider.settings.musicSavePath;
      }

      await _downloadService!.startDownload(url, 
          fileName: fileName, 
          customSaveDir: customDir);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Download started: ${fileName ?? _downloadService!.extractFileName(url)}'),
            backgroundColor: const Color(0xFF0A84FF),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _startDownload() async {
    if (_detectedVideoUrl == null || _controller == null) return;

    final provider = Provider.of<MediaProvider>(context, listen: false);
    final title = await _controller!.getTitle() ?? 'Downloaded_Anime';
    final fileName = '${title.replaceAll(RegExp(r'[^\w\s\-]'), '_')}.mp4';

    await _startDownloadFromUrl(_detectedVideoUrl!, fileName: fileName);

    // Trigger a library refresh
    provider.scanLibrary();
  }

  void _loadUrl() {
    String url = _urlController.text;
    if (url.isEmpty) return;

    // If it doesn't look like a URL, search google
    if (!url.contains('.') || url.contains(' ')) {
      url = 'https://www.google.com/search?q=${Uri.encodeComponent(url)}';
    } else if (!url.startsWith('http')) {
      url = 'https://$url';
    }
    _loadBrowserUrl(url);
  }

  Future<void> _loadBrowserUrl(String url) async {
    if (_controller != null) {
      await _controller!.loadRequest(Uri.parse(url));
      return;
    }
    if (_windowsController?.value.isInitialized == true) {
      await _windowsController!.loadUrl(url);
    }
  }

  Future<void> _goBack() async {
    if (_controller != null) {
      await _controller!.goBack();
    } else {
      await _windowsController?.goBack();
    }
  }

  Future<void> _goForward() async {
    if (_controller != null) {
      await _controller!.goForward();
    } else {
      await _windowsController?.goForward();
    }
  }

  Future<void> _reload() async {
    if (_controller != null) {
      await _controller!.reload();
    } else {
      await _windowsController?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeDownloads = _downloadService!.activeDownloadCount;

    return Column(
      children: [
        // Address bar with Glassmorphism
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _buildNavButton(Icons.arrow_back_ios_new_rounded, _goBack),
                  _buildNavButton(Icons.arrow_forward_ios_rounded, _goForward),
                  _buildNavButton(Icons.refresh_rounded, _reload),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: TextField(
                        controller: _urlController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search or enter URL',
                          hintStyle: const TextStyle(
                              color: Colors.white24, fontSize: 13),
                          border: InputBorder.none,
                          prefixIcon: const Icon(Icons.search_rounded,
                              size: 16, color: Colors.white24),
                          suffixIcon: _detectedVideoUrl != null
                              ? IconButton(
                                  icon: const Icon(
                                      Icons.download_for_offline_rounded,
                                      color: Color(0xFFE9B3FF)),
                                  onPressed:
                                      _isDownloading ? null : _startDownload,
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _loadUrl(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Download Manager Button
                  Stack(
                    children: [
                      _buildNavButton(
                        Icons.download_rounded,
                        () => setState(
                            () => _showDownloadManager = !_showDownloadManager),
                        color: _showDownloadManager
                            ? const Color(0xFF0A84FF)
                            : Colors.white70,
                      ),
                      if (activeDownloads > 0)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF0A84FF),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$activeDownloads',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  _buildQuickLink('AnimeNexus', 'https://anime.nexus'),
                  _buildQuickLink('AnimeKai', 'https://animekai.to/home'),
                ],
              ),
              const SizedBox(height: 8),
              // Progress Bar (Page or Download)
              if (_isLoading || _isDownloading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _isDownloading ? _downloadProgress : _progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    valueColor: AlwaysStoppedAnimation(_isDownloading
                        ? const Color(0xFF42E355)
                        : theme.colorScheme.primary),
                    minHeight: 2,
                  ),
                )
              else
                const SizedBox(height: 2),
            ],
          ),
        ),
        // Download Manager Panel
        if (_showDownloadManager) _buildDownloadManager(),
        // Web view
        Expanded(
          child: Container(
            color: Colors.white, // Web content background
            child: _buildBrowserView(),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadManager() {
    final tasks = _downloadService!.tasks;

    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1C),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.download_rounded,
                    size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                const Text(
                  'Downloads',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (tasks.any((t) => t.status == DownloadStatus.completed))
                  TextButton(
                    onPressed: () => _downloadService!.clearCompleted(),
                    child: const Text('Clear Completed',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                IconButton(
                  icon: const Icon(Icons.folder_open_rounded,
                      size: 18, color: Colors.white54),
                  onPressed: () => _downloadService!.openDownloadDirectory(),
                  tooltip: 'Open Downloads Folder',
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: Colors.white54),
                  onPressed: () => setState(() => _showDownloadManager = false),
                ),
              ],
            ),
          ),
          // Task list
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_for_offline_rounded,
                            size: 32,
                            color: Colors.white.withValues(alpha: 0.1)),
                        const SizedBox(height: 8),
                        Text(
                          'No downloads yet',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _buildDownloadTaskTile(task);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadTaskTile(DownloadTask task) {
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
          icon:
              const Icon(Icons.close_rounded, size: 16, color: Colors.white38),
          onPressed: () => _downloadService!.removeTask(task.id),
        );
        break;
      case DownloadStatus.downloading:
        statusIcon = Icons.downloading_rounded;
        statusColor = const Color(0xFF0A84FF);
        statusText = '${(task.progress * 100).round()}%';
        actionWidget = IconButton(
          icon:
              const Icon(Icons.cancel_rounded, size: 16, color: Colors.white38),
          onPressed: () => _downloadService!.cancelDownload(task.id),
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
              icon: const Icon(Icons.folder_open_rounded,
                  size: 16, color: Colors.white38),
              onPressed: () => _downloadService!.openDownloadDirectory(),
              tooltip: 'Show in Finder',
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  size: 16, color: Colors.white38),
              onPressed: () => _downloadService!.removeTask(task.id),
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
              icon: const Icon(Icons.refresh_rounded,
                  size: 16, color: Colors.white38),
              onPressed: () => _downloadService!.retryDownload(task.id),
              tooltip: 'Retry',
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  size: 16, color: Colors.white38),
              onPressed: () => _downloadService!.removeTask(task.id),
            ),
          ],
        );
        break;
      case DownloadStatus.cancelled:
        statusIcon = Icons.cancel_rounded;
        statusColor = Colors.white38;
        statusText = 'Cancelled';
        actionWidget = IconButton(
          icon:
              const Icon(Icons.close_rounded, size: 16, color: Colors.white38),
          onPressed: () => _downloadService!.removeTask(task.id),
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(statusIcon, size: 18, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (task.status == DownloadStatus.downloading)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor:
                          const AlwaysStoppedAnimation(Color(0xFF0A84FF)),
                      minHeight: 3,
                    ),
                  )
                else
                  Text(
                    statusText,
                    style: TextStyle(
                        color: statusColor.withValues(alpha: 0.7),
                        fontSize: 11),
                  ),
              ],
            ),
          ),
          if (task.status == DownloadStatus.downloading)
            Text(
              statusText,
              style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          const SizedBox(width: 4),
          actionWidget,
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onPressed,
      {Color? color}) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      color: color ?? Colors.white70,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
    );
  }

  Widget _buildQuickLink(String label, String url) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: TextButton(
        onPressed: () => _loadBrowserUrl(url),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final subscription in _windowsSubscriptions) {
      subscription.cancel();
    }
    _windowsController?.dispose();
    _urlController.dispose();
    // Note: Don't dispose global download service here
    super.dispose();
  }

  Widget _buildBrowserView() {
    if (_controller != null) {
      return WebViewWidget(controller: _controller!);
    }

    if (_windowsController?.value.isInitialized == true) {
      return windows_webview.Webview(_windowsController!);
    }

    return const Center(
      child: CircularProgressIndicator(color: Color(0xFFE9B3FF)),
    );
  }
}
