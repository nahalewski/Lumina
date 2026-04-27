import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/media_model.dart';

class UserAccount {
  final String id;
  final String username;
  final String displayName;
  final String passwordSalt;
  final String passwordHash;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  const UserAccount({
    required this.id,
    required this.username,
    required this.displayName,
    required this.passwordSalt,
    required this.passwordHash,
    required this.isEnabled,
    required this.createdAt,
    this.lastLoginAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'passwordSalt': passwordSalt,
        'passwordHash': passwordHash,
        'isEnabled': isEnabled,
        'createdAt': createdAt.toIso8601String(),
        'lastLoginAt': lastLoginAt?.toIso8601String(),
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String? ?? json['username'] as String,
        passwordSalt: json['passwordSalt'] as String,
        passwordHash: json['passwordHash'] as String,
        isEnabled: json['isEnabled'] as bool? ?? true,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        lastLoginAt: DateTime.tryParse(json['lastLoginAt'] as String? ?? ''),
      );

  UserAccount copyWith({
    String? displayName,
    String? passwordSalt,
    String? passwordHash,
    bool? isEnabled,
    DateTime? lastLoginAt,
  }) {
    return UserAccount(
      id: id,
      username: username,
      displayName: displayName ?? this.displayName,
      passwordSalt: passwordSalt ?? this.passwordSalt,
      passwordHash: passwordHash ?? this.passwordHash,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}

class LoginSession {
  final String token;
  final String userId;
  final DateTime expiresAt;

  const LoginSession({
    required this.token,
    required this.userId,
    required this.expiresAt,
  });
}

class UserAccountService {
  final List<UserAccount> _users = [];
  final List<PairedDevice> _pairedDevices = [];
  final List<String> _deniedDeviceIds = [];
  final Map<String, LoginSession> _sessions = {};
  bool _loaded = false;

  List<UserAccount> get users => List.unmodifiable(_users);
  List<PairedDevice> get pairedDevices => List.unmodifiable(_pairedDevices);
  List<String> get deniedDeviceIds => List.unmodifiable(_deniedDeviceIds);

  Future<File> get _storeFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'user_accounts.json'));
  }

  Future<void> load() async {
    if (_loaded) return;
    final file = await _storeFile;
    if (await file.exists()) {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      
      final userData = json['users'] as List? ?? [];
      _users
        ..clear()
        ..addAll(userData.map((item) => UserAccount.fromJson(Map<String, dynamic>.from(item as Map))));
      
      final deviceData = json['pairedDevices'] as List? ?? [];
      _pairedDevices
        ..clear()
        ..addAll(deviceData.map((item) => PairedDevice.fromJson(Map<String, dynamic>.from(item as Map))));
      
      final deniedData = json['deniedDevices'] as List? ?? [];
      _deniedDeviceIds
        ..clear()
        ..addAll(deniedData.cast<String>());
    }
    _loaded = true;
  }

  Future<void> save() async {
    final file = await _storeFile;
    await file.writeAsString(jsonEncode({
      'users': _users.map((UserAccount user) => user.toJson()).toList(),
      'pairedDevices': _pairedDevices.map((PairedDevice d) => d.toJson()).toList(),
      'deniedDevices': _deniedDeviceIds,
    }));
  }

  Future<void> addPairedDevice(PairedDevice device) async {
    await load();
    final index = _pairedDevices.indexWhere((PairedDevice d) => d.id == device.id);
    if (index != -1) {
      _pairedDevices[index] = device;
    } else {
      _pairedDevices.add(device);
    }
    _deniedDeviceIds.remove(device.id);
    await save();
  }

  Future<void> denyDevice(String deviceId) async {
    await load();
    _pairedDevices.removeWhere((PairedDevice d) => d.id == deviceId);
    if (!_deniedDeviceIds.contains(deviceId)) {
      _deniedDeviceIds.add(deviceId);
    }
    await save();
  }

  Future<void> revokeDevice(String deviceId) async {
    await load();
    _pairedDevices.removeWhere((PairedDevice d) => d.id == deviceId);
    _deniedDeviceIds.remove(deviceId);
    await save();
  }

  String generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%';
    final random = Random.secure();
    return List.generate(14, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<UserAccount> createUser({
    required String username,
    required String displayName,
    required String password,
  }) async {
    await load();
    final normalized = _normalizeUsername(username);
    if (normalized.isEmpty) {
      throw ArgumentError('Username is required');
    }
    if (_users.any((user) => user.username.toLowerCase() == normalized.toLowerCase())) {
      throw ArgumentError('Username already exists');
    }
    if (password.length < 8) {
      throw ArgumentError('Password must be at least 8 characters');
    }

    final salt = _newToken(16);
    final user = UserAccount(
      id: _newToken(12),
      username: normalized,
      displayName: displayName.trim().isEmpty ? normalized : displayName.trim(),
      passwordSalt: salt,
      passwordHash: _hashPassword(password, salt),
      isEnabled: true,
      createdAt: DateTime.now(),
    );
    _users.add(user);
    await save();
    return user;
  }

  Future<void> setUserEnabled(String id, bool enabled) async {
    await load();
    final index = _users.indexWhere((user) => user.id == id);
    if (index == -1) return;
    _users[index] = _users[index].copyWith(isEnabled: enabled);
    if (!enabled) {
      _sessions.removeWhere((_, session) => session.userId == id);
    }
    await save();
  }

  Future<void> resetPassword(String id, String password) async {
    await load();
    if (password.length < 8) {
      throw ArgumentError('Password must be at least 8 characters');
    }
    final index = _users.indexWhere((user) => user.id == id);
    if (index == -1) return;
    final salt = _newToken(16);
    _users[index] = _users[index].copyWith(
      passwordSalt: salt,
      passwordHash: _hashPassword(password, salt),
    );
    _sessions.removeWhere((_, session) => session.userId == id);
    await save();
  }

  Future<void> deleteUser(String id) async {
    await load();
    _users.removeWhere((user) => user.id == id);
    _sessions.removeWhere((_, session) => session.userId == id);
    await save();
  }

  Future<Map<String, dynamic>?> authenticate(String username, String password) async {
    await load();
    final normalized = _normalizeUsername(username);
    final index = _users.indexWhere((user) => user.username.toLowerCase() == normalized.toLowerCase());
    if (index == -1) return null;
    final user = _users[index];
    if (!user.isEnabled) return null;
    if (_hashPassword(password, user.passwordSalt) != user.passwordHash) return null;

    final token = _newToken(32);
    final expiresAt = DateTime.now().add(const Duration(days: 30));
    _sessions[token] = LoginSession(token: token, userId: user.id, expiresAt: expiresAt);
    _users[index] = user.copyWith(lastLoginAt: DateTime.now());
    await save();

    return {
      'token': token,
      'expiresAt': expiresAt.toIso8601String(),
      'user': publicUserJson(_users[index]),
    };
  }

  bool validateSession(String token) {
    final session = _sessions[token];
    if (session == null) return false;
    if (DateTime.now().isAfter(session.expiresAt)) {
      _sessions.remove(token);
      return false;
    }
    return _users.any((user) => user.id == session.userId && user.isEnabled);
  }

  Map<String, dynamic> publicUserJson(UserAccount user) => {
        'id': user.id,
        'username': user.username,
        'displayName': user.displayName,
        'isEnabled': user.isEnabled,
        'createdAt': user.createdAt.toIso8601String(),
        'lastLoginAt': user.lastLoginAt?.toIso8601String(),
      };

  String _normalizeUsername(String value) => value.trim().replaceAll(RegExp(r'\s+'), '.');

  String _hashPassword(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  String _newToken(int bytes) {
    final random = Random.secure();
    final data = List<int>.generate(bytes, (_) => random.nextInt(256));
    return base64UrlEncode(data).replaceAll('=', '');
  }
}
