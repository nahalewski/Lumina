import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/youtube_provider.dart';
import '../services/youtube_api_service.dart';

class YouTubeScreen extends StatefulWidget {
  const YouTubeScreen({super.key});

  @override
  State<YouTubeScreen> createState() => _YouTubeScreenState();
}

class _YouTubeScreenState extends State<YouTubeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<YouTubeProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<YouTubeProvider>(
      builder: (context, yt, _) {
        // If a video is playing, show the player
        if (yt.nowPlaying != null) {
          return _VideoPlayerView(video: yt.nowPlaying!);
        }

        switch (yt.authState) {
          case YouTubeAuthState.unknown:
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF0000)),
            );
          case YouTubeAuthState.signedOut:
          case YouTubeAuthState.error:
            return _SignInView(error: yt.authError);
          case YouTubeAuthState.signingIn:
            return _DeviceCodeView(
              userCode: yt.deviceUserCode,
              verificationUrl: yt.deviceVerificationUrl,
              secondsRemaining: yt.deviceSecondsRemaining,
            );
          case YouTubeAuthState.signedIn:
            return _MainView();
        }
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//                              Sign-in screen
// ─────────────────────────────────────────────────────────────────────────────

class _SignInView extends StatelessWidget {
  final String? error;
  const _SignInView({this.error});

  @override
  Widget build(BuildContext context) {
    final yt = context.read<YouTubeProvider>();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFF0000).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_display_rounded,
                  color: Color(0xFFFF0000), size: 36),
            ),
            const SizedBox(height: 24),
            const Text(
              'YouTube',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                fontFamily: 'Manrope',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in to access your feed,\nwatch history, and subscriptions.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Text(
                  error!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: yt.startSignIn,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Connect Your YouTube Account'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF0000),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Uses secure Google Device Authorization.\nYou\'ll enter a code on your phone — no password shared with this app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white30, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//                          Device code / pairing screen
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceCodeView extends StatelessWidget {
  final String? userCode;
  final String? verificationUrl;
  final int secondsRemaining;

  const _DeviceCodeView({
    this.userCode,
    this.verificationUrl,
    required this.secondsRemaining,
  });

  @override
  Widget build(BuildContext context) {
    final mins = secondsRemaining ~/ 60;
    final secs = secondsRemaining % 60;
    final timeStr =
        '$mins:${secs.toString().padLeft(2, '0')}';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone_android_rounded,
                color: Color(0xFFAAC7FF), size: 48),
            const SizedBox(height: 24),
            const Text(
              'Activate on your phone',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              verificationUrl ?? 'https://accounts.google.com/device',
              style: const TextStyle(
                  color: Color(0xFFAAC7FF),
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            if (userCode != null) ...[
              const Text(
                'Enter this code:',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFFFF0000).withOpacity(0.4)),
                ),
                child: Text(
                  userCode!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                    fontFamily: 'Courier',
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ] else ...[
              const SizedBox(height: 12),
              const CircularProgressIndicator(color: Color(0xFFFF0000)),
              const SizedBox(height: 12),
            ],
            Text(
              'Waiting for authorization… expires in $timeStr',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 24),
            const Text(
              '1. Open the URL above on your phone\n'
              '2. Sign in to your Google account\n'
              '3. Enter the code — this screen updates automatically',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//                            Main signed-in view
// ─────────────────────────────────────────────────────────────────────────────

class _MainView extends StatefulWidget {
  @override
  State<_MainView> createState() => _MainViewState();
}

class _MainViewState extends State<_MainView> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yt = context.watch<YouTubeProvider>();

    return Column(
      children: [
        // ── Top bar ──────────────────────────────────────────────────────────
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF131315),
            border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(
            children: [
              const Icon(Icons.smart_display_rounded,
                  color: Color(0xFFFF0000), size: 22),
              const SizedBox(width: 10),
              const Text(
                'YouTube',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Manrope',
                ),
              ),
              const SizedBox(width: 32),
              // Tab chips
              _TabChip(
                  label: 'Home',
                  icon: Icons.home_rounded,
                  selected: yt.currentTab == YouTubeTab.home,
                  onTap: () => yt.setTab(YouTubeTab.home)),
              const SizedBox(width: 6),
              _TabChip(
                  label: 'Subscriptions',
                  icon: Icons.subscriptions_rounded,
                  selected: yt.currentTab == YouTubeTab.subscriptions,
                  onTap: () => yt.setTab(YouTubeTab.subscriptions)),
              const SizedBox(width: 6),
              _TabChip(
                  label: 'History',
                  icon: Icons.history_rounded,
                  selected: yt.currentTab == YouTubeTab.history,
                  onTap: () => yt.setTab(YouTubeTab.history)),
              const SizedBox(width: 6),
              _TabChip(
                  label: 'Search',
                  icon: Icons.search_rounded,
                  selected: yt.currentTab == YouTubeTab.search,
                  onTap: () => yt.setTab(YouTubeTab.search)),
              const Spacer(),
              // Search field (always visible)
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search YouTube…',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Colors.white30, size: 18),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none),
                  ),
                  onChanged: (q) {
                    _searchDebounce?.cancel();
                    _searchDebounce =
                        Timer(const Duration(milliseconds: 500), () {
                      yt.setTab(YouTubeTab.search);
                      yt.search(q);
                    });
                  },
                  textInputAction: TextInputAction.search,
                  onSubmitted: (q) {
                    _searchDebounce?.cancel();
                    yt.setTab(YouTubeTab.search);
                    yt.search(q);
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Sign out
              PopupMenuButton<String>(
                icon: const Icon(Icons.account_circle_rounded,
                    color: Colors.white54, size: 22),
                color: const Color(0xFF1E1E22),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'signout',
                    child: const Row(
                      children: [
                        Icon(Icons.logout_rounded,
                            color: Colors.redAccent, size: 16),
                        SizedBox(width: 8),
                        Text('Sign Out',
                            style: TextStyle(
                                color: Colors.redAccent, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'signout') yt.signOut();
                },
              ),
            ],
          ),
        ),

        // ── Content ──────────────────────────────────────────────────────────
        Expanded(
          child: _buildTabContent(yt),
        ),
      ],
    );
  }

  Widget _buildTabContent(YouTubeProvider yt) {
    switch (yt.currentTab) {
      case YouTubeTab.home:
        return _VideoGrid(
          videos: yt.homeFeed,
          loading: yt.loadingHome,
          emptyMessage: 'No videos yet. Make sure you\'re subscribed to channels.',
          onRefresh: () => yt.loadHomeFeed(refresh: true),
        );
      case YouTubeTab.history:
        return _VideoGrid(
          videos: yt.history,
          loading: yt.loadingHistory,
          emptyMessage: 'No watch history available.',
          onRefresh: () => yt.loadHistory(refresh: true),
        );
      case YouTubeTab.subscriptions:
        return _SubscriptionsView();
      case YouTubeTab.search:
        return _VideoGrid(
          videos: yt.searchResults,
          loading: yt.loadingSearch,
          emptyMessage: 'Type something to search YouTube.',
          onRefresh: null,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//                             Video grid
// ─────────────────────────────────────────────────────────────────────────────

class _VideoGrid extends StatelessWidget {
  final List<YouTubeVideo> videos;
  final bool loading;
  final String emptyMessage;
  final VoidCallback? onRefresh;

  const _VideoGrid({
    required this.videos,
    required this.loading,
    required this.emptyMessage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && videos.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF0000)),
      );
    }

    if (videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_rounded,
                size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            Text(emptyMessage,
                style: const TextStyle(color: Colors.white38, fontSize: 14)),
            if (onRefresh != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFAAC7FF),
                  side: const BorderSide(color: Color(0xFFAAC7FF), width: 0.5),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        childAspectRatio: 16 / 11,
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
      ),
      itemCount: videos.length,
      itemBuilder: (context, i) => _VideoCard(video: videos[i]),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final YouTubeVideo video;
  const _VideoCard({required this.video});

  @override
  Widget build(BuildContext context) {
    final yt = context.read<YouTubeProvider>();
    return GestureDetector(
      onTap: () => yt.playVideo(video),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: video.thumbnailUrl ?? video.thumbnailHq,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    memCacheWidth: 480,
                    memCacheHeight: 270,
                    placeholder: (_, __) => Container(color: Colors.white10),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.white10,
                      child: const Icon(Icons.play_circle_outline_rounded,
                          color: Colors.white24, size: 32),
                    ),
                  ),
                ),
                // Duration badge
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      video.durationLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                // Play overlay on hover (simplified)
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => yt.playVideo(video),
                      borderRadius: BorderRadius.circular(10),
                      hoverColor: Colors.black26,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3),
          ),
          const SizedBox(height: 2),
          Text(
            '${video.channelTitle} · ${video.viewCountLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//                          Subscriptions view
// ─────────────────────────────────────────────────────────────────────────────

class _SubscriptionsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final yt = context.watch<YouTubeProvider>();

    if (yt.loadingSubs && yt.subscriptions.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF0000)));
    }

    if (yt.subscriptions.isEmpty) {
      return const Center(
        child: Text('No subscriptions found.',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: yt.subscriptions.length,
      itemBuilder: (context, i) {
        final ch = yt.subscriptions[i];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: ClipOval(
            child: ch.thumbnailUrl != null
                ? CachedNetworkImage(
                    imageUrl: ch.thumbnailUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    memCacheWidth: 88,
                    memCacheHeight: 88,
                  )
                : Container(
                    width: 44,
                    height: 44,
                    color: Colors.white10,
                    child: const Icon(Icons.person_rounded,
                        color: Colors.white38, size: 24),
                  ),
          ),
          title: Text(ch.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          subtitle: ch.description.isNotEmpty
              ? Text(
                  ch.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11),
                )
              : null,
          trailing: const Icon(Icons.chevron_right_rounded,
              color: Colors.white24, size: 20),
          onTap: () {
            // Load channel videos
            yt.setTab(YouTubeTab.home);
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//                            Video player view
// ─────────────────────────────────────────────────────────────────────────────

class _VideoPlayerView extends StatefulWidget {
  final YouTubeVideo video;
  const _VideoPlayerView({required this.video});

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _waitForStream();
  }

  @override
  void didUpdateWidget(_VideoPlayerView old) {
    super.didUpdateWidget(old);
    if (old.video.id != widget.video.id) {
      _controller?.dispose();
      _controller = null;
      _initialized = false;
      _waitForStream();
    }
  }

  void _waitForStream() {
    final yt = context.read<YouTubeProvider>();
    if (yt.streamUrl != null) {
      _initPlayer(yt.streamUrl!);
    }
    // If streamUrl is null, didChangeDependencies will catch it
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final yt = context.read<YouTubeProvider>();
    if (!_initialized && yt.streamUrl != null && _controller == null) {
      _initPlayer(yt.streamUrl!);
    }
  }

  Future<void> _initPlayer(String url) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initialized = true;
      });
      controller.play();
      _scheduleHideControls();
    } catch (e) {
      debugPrint('[YouTube] Player init error: $e');
      controller.dispose();
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer =
        Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onTap() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yt = context.watch<YouTubeProvider>();
    final video = widget.video;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // ── Player area ────────────────────────────────────────────────────
          Expanded(
            flex: 7,
            child: GestureDetector(
              onTap: _onTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Video
                  if (_initialized && _controller != null)
                    Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  else if (yt.streamError != null)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Colors.redAccent, size: 48),
                        const SizedBox(height: 12),
                        Text(yt.streamError!,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13),
                            textAlign: TextAlign.center),
                      ],
                    )
                  else
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (video.thumbnailUrl != null)
                          Opacity(
                            opacity: 0.3,
                            child: CachedNetworkImage(
                              imageUrl: video.thumbnailUrl!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        const SizedBox(height: 24),
                        const CircularProgressIndicator(
                            color: Color(0xFFFF0000)),
                        const SizedBox(height: 16),
                        const Text('Extracting stream…',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 13)),
                      ],
                    ),

                  // Controls overlay
                  if (_showControls && _initialized && _controller != null)
                    _ControlsOverlay(
                      controller: _controller!,
                      video: video,
                      onClose: () {
                        _controller?.pause();
                        yt.stopPlayback();
                      },
                      onTap: _onTap,
                    ),

                  // Back button always visible at top-left
                  Positioned(
                    top: 16,
                    left: 16,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: _CircleButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () {
                          _controller?.pause();
                          yt.stopPlayback();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Info panel ─────────────────────────────────────────────────────
          Container(
            width: 300,
            decoration: BoxDecoration(
              color: const Color(0xFF131315),
              border:
                  Border(left: BorderSide(color: Colors.white.withOpacity(0.06))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.3),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        video.channelTitle,
                        style: const TextStyle(
                            color: Color(0xFFAAC7FF), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${video.viewCountLabel} · ${video.durationLabel}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                // Description
                if (video.description?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      video.description!,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12, height: 1.5),
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsOverlay extends StatefulWidget {
  final VideoPlayerController controller;
  final YouTubeVideo video;
  final VoidCallback onClose;
  final VoidCallback onTap;

  const _ControlsOverlay({
    required this.controller,
    required this.video,
    required this.onClose,
    required this.onTap,
  });

  @override
  State<_ControlsOverlay> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<_ControlsOverlay> {
  Timer? _posTimer;

  @override
  void initState() {
    super.initState();
    _posTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _posTimer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;
    final isPlaying = ctrl.value.isPlaying;
    final progress = dur.inMilliseconds > 0
        ? pos.inMilliseconds / dur.inMilliseconds
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black54,
            Colors.transparent,
            Colors.transparent,
            Colors.black54,
          ],
          stops: const [0, 0.3, 0.7, 1],
        ),
      ),
      child: Column(
        children: [
          const Spacer(),
          // Center play/pause + skip
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CircleButton(
                icon: Icons.replay_10_rounded,
                onTap: () =>
                    ctrl.seekTo(pos - const Duration(seconds: 10)),
              ),
              const SizedBox(width: 24),
              _CircleButton(
                icon: isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 52,
                onTap: () =>
                    isPlaying ? ctrl.pause() : ctrl.play(),
              ),
              const SizedBox(width: 24),
              _CircleButton(
                icon: Icons.forward_10_rounded,
                onTap: () =>
                    ctrl.seekTo(pos + const Duration(seconds: 10)),
              ),
            ],
          ),
          const Spacer(),
          // Progress bar
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(_fmt(pos),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'Courier')),
                Expanded(
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: (v) => ctrl.seekTo(
                        Duration(
                            milliseconds:
                                (v * dur.inMilliseconds).round())),
                    activeColor: const Color(0xFFFF0000),
                    inactiveColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                ),
                Text(_fmt(dur),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'Courier')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black45,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFF0000).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF0000).withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color:
                    selected ? const Color(0xFFFF0000) : Colors.white38),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white38,
                fontSize: 12,
                fontWeight: selected
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
