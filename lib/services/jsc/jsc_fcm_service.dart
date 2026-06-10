import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'jsc_api.dart';
import 'jsc_auth_service.dart';

/// Bridges Firebase Cloud Messaging with the JSC backend.
///
/// Responsibilities:
///  - Request notification permission on first run (Android 13+ requirement)
///  - Get the FCM token from Firebase
///  - Register it with /api/fcm-tokens/register whenever the user is signed in
///  - Re-register on token refresh
///  - Unregister + remove from server at sign-out
///  - Surface foreground messages to a listener so the UI can show them
///
/// Designed as a singleton that listens to [JscAuthService] so screens don't
/// have to remember to call register/unregister manually.
class JscFcmService {
  final JscAuthService auth;
  String? _currentToken;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _msgSub;
  bool _initialized = false;

  /// Optional listener for foreground messages (notification arrives while app
  /// is in the foreground — Android won't show a system notification on its
  /// own in this case; the app must surface it).
  void Function(RemoteMessage)? onForegroundMessage;

  JscFcmService(this.auth) {
    auth.addListener(_onAuthChanged);
  }

  bool get isInitialized => _initialized;
  String? get currentToken => _currentToken;

  Future<void> init() async {
    if (_initialized) return;
    try {
      // Android 13+ runtime permission. iOS prompts via this too.
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      _currentToken = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) {
        debugPrint('FCM token: ${_currentToken?.substring(0, 16)}…');
      }

      _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _currentToken = t;
        if (auth.isAuthenticated) {
          _register(t);
        }
      });

      _msgSub = FirebaseMessaging.onMessage.listen((m) {
        onForegroundMessage?.call(m);
      });

      _initialized = true;
      // If the user is already authed from prior session, register now.
      if (auth.isAuthenticated && _currentToken != null) {
        await _register(_currentToken!);
      }
    } catch (e) {
      debugPrint('JscFcmService.init failed: $e');
      _initialized = true; // don't keep retrying
    }
  }

  void _onAuthChanged() {
    // The simplest correctness signal: at the moment a user becomes
    // authenticated, push our cached FCM token. When they sign out, the auth
    // service has already cleared the token before we get here, so we can't
    // call unregister from this listener — sign-out flow calls
    // [unregisterBeforeSignOut] before clearing.
    if (auth.isAuthenticated && _currentToken != null) {
      _register(_currentToken!);
    }
  }

  Future<void> _register(String token) async {
    final api = JscApi(auth);
    try {
      await api.registerFcmToken(token, platform: _platform);
      debugPrint('FCM token registered with JSC');
    } catch (e) {
      debugPrint('FCM register failed: $e');
    } finally {
      await api.dispose();
    }
  }

  String get _platform {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'unknown';
  }

  /// Call this BEFORE [JscAuthService.signOut] so the JWT is still available
  /// for the unregister API call. The auth service's sign-out method invokes
  /// this automatically.
  Future<void> unregisterBeforeSignOut() async {
    if (_currentToken == null || !auth.isAuthenticated) return;
    final api = JscApi(auth);
    try {
      await api.unregisterFcmToken(_currentToken!);
      debugPrint('FCM token unregistered from JSC');
    } catch (e) {
      debugPrint('FCM unregister failed: $e');
    } finally {
      await api.dispose();
    }
  }

  void dispose() {
    auth.removeListener(_onAuthChanged);
    _refreshSub?.cancel();
    _msgSub?.cancel();
  }
}
