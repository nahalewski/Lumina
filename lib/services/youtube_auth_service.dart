import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Google OAuth 2.0 Device Authorization Grant — no browser needed on desktop.
///
/// The user visits accounts.google.com/device on any phone/browser and enters
/// the displayed code. The desktop app polls and receives the token.
///
/// Requires a Google Cloud project with:
///   • YouTube Data API v3 enabled
///   • An OAuth 2.0 "TV and Limited Input devices" client ID
///
/// Set YOUTUBE_CLIENT_ID in your .env file.
class YouTubeAuthService {
  static const String _tokenFileName = 'youtube_tokens.json';
  static const String _deviceCodeUrl =
      'https://oauth2.googleapis.com/device/code';
  static const String _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const String _scope =
      'https://www.googleapis.com/auth/youtube.readonly';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  final _client = HttpClient();

  // ─── Public state ──────────────────────────────────────────────────────────

  bool get isSignedIn => _accessToken != null && _refreshToken != null;

  String? get accessToken => _accessToken;

  // ─── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await _loadTokens();
    if (_refreshToken != null) {
      await _refreshAccessToken().catchError((_) {});
    }
  }

  // ─── Device flow (called from UI) ──────────────────────────────────────────

  /// Step 1 — Request a device code. Returns `{userCode, verificationUrl, deviceCode, interval}`.
  Future<Map<String, dynamic>> requestDeviceCode(String clientId) async {
    final body = 'client_id=${Uri.encodeComponent(clientId)}'
        '&scope=${Uri.encodeComponent(_scope)}';

    final response = await _post(_deviceCodeUrl, body);
    return {
      'userCode': response['user_code'] as String,
      'verificationUrl': response['verification_url'] as String,
      'deviceCode': response['device_code'] as String,
      'interval': (response['interval'] as int?) ?? 5,
      'expiresIn': (response['expires_in'] as int?) ?? 1800,
    };
  }

  /// Step 2 — Poll until the user completes login on their phone/browser.
  ///
  /// Calls [onWaiting] each poll cycle with the remaining seconds.
  /// Returns true when authorized, false on timeout or error.
  Future<bool> pollForToken(
    String clientId,
    String clientSecret,
    String deviceCode,
    int intervalSeconds,
    int expiresIn, {
    void Function(int remainingSeconds)? onWaiting,
    void Function()? onAuthorized,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: expiresIn));
    final body = 'client_id=${Uri.encodeComponent(clientId)}'
        '&client_secret=${Uri.encodeComponent(clientSecret)}'
        '&device_code=${Uri.encodeComponent(deviceCode)}'
        '&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code';

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(Duration(seconds: intervalSeconds));

      try {
        final resp = await _post(_tokenUrl, body);
        if (resp.containsKey('access_token')) {
          _accessToken = resp['access_token'] as String;
          _refreshToken = resp['refresh_token'] as String?;
          _expiresAt = DateTime.now()
              .add(Duration(seconds: (resp['expires_in'] as int?) ?? 3600));
          await _saveTokens();
          onAuthorized?.call();
          return true;
        }
        // error = authorization_pending → keep polling
        // error = slow_down → increase interval
        if (resp['error'] == 'slow_down') intervalSeconds += 5;
        if (resp['error'] == 'access_denied') return false;
      } catch (_) {}

      final remaining = deadline.difference(DateTime.now()).inSeconds;
      onWaiting?.call(remaining);
    }
    return false;
  }

  // ─── Token refresh ──────────────────────────────────────────────────────────

  Future<String?> getValidToken(String clientId, String clientSecret) async {
    if (_accessToken == null) return null;
    if (_expiresAt != null &&
        DateTime.now().isAfter(_expiresAt!.subtract(const Duration(minutes: 2)))) {
      await _refreshAccessToken(clientId: clientId, clientSecret: clientSecret);
    }
    return _accessToken;
  }

  Future<void> _refreshAccessToken({String? clientId, String? clientSecret}) async {
    if (_refreshToken == null) return;
    try {
      final body = 'client_id=${Uri.encodeComponent(clientId ?? '')}'
          '&client_secret=${Uri.encodeComponent(clientSecret ?? '')}'
          '&refresh_token=${Uri.encodeComponent(_refreshToken!)}'
          '&grant_type=refresh_token';
      final resp = await _post(_tokenUrl, body);
      if (resp.containsKey('access_token')) {
        _accessToken = resp['access_token'] as String;
        _expiresAt = DateTime.now()
            .add(Duration(seconds: (resp['expires_in'] as int?) ?? 3600));
        await _saveTokens();
      }
    } catch (e) {
      debugPrint('[YouTubeAuth] Token refresh failed: $e');
    }
  }

  // ─── Sign out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    final file = await _tokenFile();
    if (await file.exists()) await file.delete();
  }

  // ─── Persistence ────────────────────────────────────────────────────────────

  Future<File> _tokenFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_tokenFileName');
  }

  Future<void> _saveTokens() async {
    final file = await _tokenFile();
    await file.writeAsString(jsonEncode({
      'access_token': _accessToken,
      'refresh_token': _refreshToken,
      'expires_at': _expiresAt?.toIso8601String(),
    }));
  }

  Future<void> _loadTokens() async {
    try {
      final file = await _tokenFile();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _accessToken = data['access_token'] as String?;
      _refreshToken = data['refresh_token'] as String?;
      final exp = data['expires_at'] as String?;
      if (exp != null) _expiresAt = DateTime.tryParse(exp);
    } catch (_) {}
  }

  // ─── HTTP helper ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(String url, String body) async {
    final request = await _client.postUrl(Uri.parse(url));
    request.headers.set(
        HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
    request.write(body);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    if (response.statusCode >= 400 && !data.containsKey('error')) {
      throw Exception('HTTP ${response.statusCode}: $responseBody');
    }
    return data;
  }
}
