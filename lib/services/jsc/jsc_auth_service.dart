import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/jsc/jsc_user.dart';

class JscAuthService extends ChangeNotifier {
  static const _kBaseUrl = 'jsc_base_url';
  static const _kToken = 'jsc_token';
  static const _kUser = 'jsc_user';

  static const String defaultBaseUrl = 'https://juicesupportcenter.com';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String _baseUrl = defaultBaseUrl;
  String? _token;
  JscUser? _user;
  bool _loaded = false;

  String get baseUrl => _baseUrl;
  String? get token => _token;
  JscUser? get user => _user;
  bool get isLoaded => _loaded;
  bool get isAuthenticated => _token != null && _user != null;

  Future<void> load() async {
    _baseUrl = await _storage.read(key: _kBaseUrl) ?? defaultBaseUrl;
    _token = await _storage.read(key: _kToken);
    final userJson = await _storage.read(key: _kUser);
    if (userJson != null) {
      try {
        _user = JscUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      } catch (_) {
        _user = null;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _storage.write(key: _kBaseUrl, value: _baseUrl);
    notifyListeners();
  }

  Future<void> saveSession({required String token, required JscUser user}) async {
    _token = token;
    _user = user;
    await _storage.write(key: _kToken, value: token);
    await _storage.write(
      key: _kUser,
      value: jsonEncode({
        'id': user.id,
        'email': user.email,
        'name': user.name,
        'role': user.role,
        'type': user.type,
        if (user.clientId != null) 'clientId': user.clientId,
        if (user.company != null) 'company': user.company,
      }),
    );
    notifyListeners();
  }

  /// Hook for the FCM service: it sets this so we can unregister the device's
  /// push token *before* we wipe the JWT. Wired up at app startup.
  Future<void> Function()? unregisterFcmHook;

  Future<void> signOut() async {
    try {
      await unregisterFcmHook?.call();
    } catch (_) {
      // Don't block sign-out on a failed unregister.
    }
    _token = null;
    _user = null;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
    notifyListeners();
  }
}
