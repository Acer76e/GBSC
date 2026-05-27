import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AuthMode { apiToken, globalKey }

@immutable
class Credentials {
  final AuthMode mode;
  final String? token;
  final String? email;
  final String? globalKey;

  const Credentials.apiToken(String this.token)
      : mode = AuthMode.apiToken,
        email = null,
        globalKey = null;

  const Credentials.globalKey({required String this.email, required String this.globalKey})
      : mode = AuthMode.globalKey,
        token = null;

  Map<String, String> headers() {
    if (mode == AuthMode.apiToken) {
      return {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
    }
    return {
      'X-Auth-Email': email!,
      'X-Auth-Key': globalKey!,
      'Content-Type': 'application/json',
    };
  }

  String get displayLabel {
    if (mode == AuthMode.apiToken) return 'API Token';
    return email ?? 'Global Key';
  }
}

class AuthService extends ChangeNotifier {
  static const _kMode = 'cf_auth_mode';
  static const _kToken = 'cf_auth_token';
  static const _kEmail = 'cf_auth_email';
  static const _kKey = 'cf_auth_key';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Credentials? _credentials;
  bool _loaded = false;

  Credentials? get credentials => _credentials;
  bool get isAuthenticated => _credentials != null;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final mode = await _storage.read(key: _kMode);
    if (mode == AuthMode.apiToken.name) {
      final token = await _storage.read(key: _kToken);
      if (token != null && token.isNotEmpty) {
        _credentials = Credentials.apiToken(token);
      }
    } else if (mode == AuthMode.globalKey.name) {
      final email = await _storage.read(key: _kEmail);
      final key = await _storage.read(key: _kKey);
      if (email != null && key != null && email.isNotEmpty && key.isNotEmpty) {
        _credentials = Credentials.globalKey(email: email, globalKey: key);
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveApiToken(String token) async {
    await _storage.write(key: _kMode, value: AuthMode.apiToken.name);
    await _storage.write(key: _kToken, value: token);
    await _storage.delete(key: _kEmail);
    await _storage.delete(key: _kKey);
    _credentials = Credentials.apiToken(token);
    notifyListeners();
  }

  Future<void> saveGlobalKey({required String email, required String key}) async {
    await _storage.write(key: _kMode, value: AuthMode.globalKey.name);
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kKey, value: key);
    await _storage.delete(key: _kToken);
    _credentials = Credentials.globalKey(email: email, globalKey: key);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _storage.deleteAll();
    _credentials = null;
    notifyListeners();
  }
}
