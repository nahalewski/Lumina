import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/youtube_auth_service.dart';
import '../services/youtube_api_service.dart';
import '../services/ytdlp_service.dart';

enum YouTubeTab { home, subscriptions, history, search }

enum YouTubeAuthState { unknown, signedOut, signingIn, signedIn, error }

class YouTubeProvider extends ChangeNotifier {
  final YouTubeAuthService _auth = YouTubeAuthService();
  final YouTubeApiService _api = YouTubeApiService();
  final YtDlpService _ytdlp = YtDlpService();

  YouTubeAuthState _authState = YouTubeAuthState.unknown;
  YouTubeTab _currentTab = YouTubeTab.home;

  // Device-flow pairing state
  String? _deviceUserCode;
  String? _deviceVerificationUrl;
  int _deviceSecondsRemaining = 0;
  String? _authError;

  // Feed data
  List<YouTubeVideo> _homeFeed = [];
  List<YouTubeVideo> _history = [];
  List<YouTubeChannel> _subscriptions = [];
  List<YouTubeVideo> _searchResults = [];

  bool _loadingHome = false;
  bool _loadingHistory = false;
  bool _loadingSubs = false;
  bool _loadingSearch = false;

  // Playback
  YouTubeVideo? _nowPlaying;
  String? _streamUrl;
  bool _extractingStream = false;
  String? _streamError;

  // Search
  String _searchQuery = '';

  // ─── Getters ─────────────────────────────────────────────────────────────

  YouTubeAuthState get authState => _authState;
  YouTubeTab get currentTab => _currentTab;
  bool get isSignedIn => _auth.isSignedIn;
  String? get deviceUserCode => _deviceUserCode;
  String? get deviceVerificationUrl => _deviceVerificationUrl;
  int get deviceSecondsRemaining => _deviceSecondsRemaining;
  String? get authError => _authError;

  List<YouTubeVideo> get homeFeed => _homeFeed;
  List<YouTubeVideo> get history => _history;
  List<YouTubeChannel> get subscriptions => _subscriptions;
  List<YouTubeVideo> get searchResults => _searchResults;

  bool get loadingHome => _loadingHome;
  bool get loadingHistory => _loadingHistory;
  bool get loadingSubs => _loadingSubs;
  bool get loadingSearch => _loadingSearch;

  YouTubeVideo? get nowPlaying => _nowPlaying;
  String? get streamUrl => _streamUrl;
  bool get extractingStream => _extractingStream;
  String? get streamError => _streamError;

  String get clientId =>
      dotenv.env['YOUTUBE_CLIENT_ID'] ??
      const String.fromEnvironment('YOUTUBE_CLIENT_ID', defaultValue: '');

  String get clientSecret =>
      dotenv.env['YOUTUBE_CLIENT_SECRET'] ??
      const String.fromEnvironment('YOUTUBE_CLIENT_SECRET', defaultValue: '');

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await _auth.init();
    _authState = _auth.isSignedIn
        ? YouTubeAuthState.signedIn
        : YouTubeAuthState.signedOut;
    notifyListeners();
    if (_auth.isSignedIn) _loadCurrentTab();
  }

  // ─── Auth — Device flow ───────────────────────────────────────────────────

  Future<void> startSignIn() async {
    if (clientId.isEmpty) {
      _authError =
          'YOUTUBE_CLIENT_ID not set in .env — set up a Google Cloud project first.';
      _authState = YouTubeAuthState.error;
      notifyListeners();
      return;
    }

    _authState = YouTubeAuthState.signingIn;
    _authError = null;
    notifyListeners();

    try {
      final info = await _auth.requestDeviceCode(clientId);
      _deviceUserCode = info['userCode'] as String;
      _deviceVerificationUrl = info['verificationUrl'] as String;
      _deviceSecondsRemaining = info['expiresIn'] as int;
      notifyListeners();

      final authorized = await _auth.pollForToken(
        clientId,
        clientSecret,
        info['deviceCode'] as String,
        info['interval'] as int,
        info['expiresIn'] as int,
        onWaiting: (remaining) {
          _deviceSecondsRemaining = remaining;
          notifyListeners();
        },
        onAuthorized: () {
          _deviceUserCode = null;
          _deviceVerificationUrl = null;
        },
      );

      if (authorized) {
        _authState = YouTubeAuthState.signedIn;
        notifyListeners();
        _loadCurrentTab();
      } else {
        _authError = 'Sign-in timed out or was denied. Try again.';
        _authState = YouTubeAuthState.signedOut;
        notifyListeners();
      }
    } catch (e) {
      _authError = 'Sign-in failed: $e';
      _authState = YouTubeAuthState.error;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _authState = YouTubeAuthState.signedOut;
    _homeFeed = [];
    _history = [];
    _subscriptions = [];
    _searchResults = [];
    _nowPlaying = null;
    _streamUrl = null;
    notifyListeners();
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  void setTab(YouTubeTab tab) {
    _currentTab = tab;
    notifyListeners();
    _loadCurrentTab();
  }

  void _loadCurrentTab() {
    switch (_currentTab) {
      case YouTubeTab.home:
        if (_homeFeed.isEmpty) loadHomeFeed();
        break;
      case YouTubeTab.subscriptions:
        if (_subscriptions.isEmpty) loadSubscriptions();
        break;
      case YouTubeTab.history:
        if (_history.isEmpty) loadHistory();
        break;
      case YouTubeTab.search:
        break;
    }
  }

  // ─── Data loading ─────────────────────────────────────────────────────────

  Future<void> loadHomeFeed({bool refresh = false}) async {
    if (_loadingHome) return;
    final token = await _auth.getValidToken(clientId, clientSecret);
    if (token == null) return;

    if (refresh) _homeFeed = [];
    _loadingHome = true;
    notifyListeners();

    try {
      _homeFeed = await _api.getHomeFeed(token);
    } catch (e) {
      debugPrint('[YouTube] Home feed error: $e');
    } finally {
      _loadingHome = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory({bool refresh = false}) async {
    if (_loadingHistory) return;
    final token = await _auth.getValidToken(clientId, clientSecret);
    if (token == null) return;

    if (refresh) _history = [];
    _loadingHistory = true;
    notifyListeners();

    try {
      _history = await _api.getWatchHistory(token);
    } catch (e) {
      debugPrint('[YouTube] History error: $e');
    } finally {
      _loadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> loadSubscriptions({bool refresh = false}) async {
    if (_loadingSubs) return;
    final token = await _auth.getValidToken(clientId, clientSecret);
    if (token == null) return;

    if (refresh) _subscriptions = [];
    _loadingSubs = true;
    notifyListeners();

    try {
      _subscriptions = await _api.getSubscriptions(token);
    } catch (e) {
      debugPrint('[YouTube] Subscriptions error: $e');
    } finally {
      _loadingSubs = false;
      notifyListeners();
    }
  }

  Future<void> search(String query) async {
    _searchQuery = query;
    if (query.trim().isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _loadingSearch = true;
    notifyListeners();

    final token = await _auth.getValidToken(clientId, clientSecret);
    if (token == null) {
      _loadingSearch = false;
      notifyListeners();
      return;
    }

    try {
      _searchResults = await _api.search(token, query);
    } catch (e) {
      debugPrint('[YouTube] Search error: $e');
    } finally {
      _loadingSearch = false;
      notifyListeners();
    }
  }

  // ─── Playback ─────────────────────────────────────────────────────────────

  /// Extract stream URL via yt-dlp and set nowPlaying.
  Future<void> playVideo(YouTubeVideo video) async {
    _nowPlaying = video;
    _streamUrl = null;
    _streamError = null;
    _extractingStream = true;
    notifyListeners();

    try {
      final url = await _extractStreamUrl(video.url);
      if (url != null) {
        _streamUrl = url;
      } else {
        _streamError = 'Could not extract stream URL. Check yt-dlp is installed.';
      }
    } catch (e) {
      _streamError = 'Playback error: $e';
      debugPrint('[YouTube] Stream extraction error: $e');
    } finally {
      _extractingStream = false;
      notifyListeners();
    }
  }

  void stopPlayback() {
    _nowPlaying = null;
    _streamUrl = null;
    _streamError = null;
    _extractingStream = false;
    notifyListeners();
  }

  Future<String?> _extractStreamUrl(String videoUrl) async {
    if (!await _ytdlp.isInstalled()) await _ytdlp.install();
    final exePath = await _ytdlp.executablePath;

    // Prefer a pre-merged MP4 up to 1080p; fall back to best available.
    // vcodec!^=av01 avoids AV1 which video_player may not decode on Windows.
    final args = [
      '-f',
      'b[height<=1080][ext=mp4][vcodec!^=av01]/'
          'b[height<=720][ext=mp4]/'
          'b[ext=mp4]/b',
      '--get-url',
      '--no-playlist',
      videoUrl,
    ];

    try {
      final result = await Process.run(exePath, args);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((l) => l.trim())
            .where((l) => l.startsWith('http'))
            .toList();
        // First line is video URL (may also include audio URL on line 2 for DASH)
        return lines.isNotEmpty ? lines.first : null;
      }
      debugPrint('[YouTube] yt-dlp exit ${result.exitCode}: ${result.stderr}');
    } catch (e) {
      debugPrint('[YouTube] yt-dlp error: $e');
    }
    return null;
  }
}
