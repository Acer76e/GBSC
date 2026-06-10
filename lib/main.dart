import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'services/auth_service.dart';
import 'services/cloudflare_api.dart';
import 'services/jsc/jsc_auth_service.dart';
import 'services/jsc/jsc_fcm_service.dart';
import 'services/maintenance_config.dart';
import 'services/maintenance_service.dart';
import 'theme.dart';

late final JscAuthService _jscAuth;
JscFcmService? _fcm;

// Used by the FCM foreground listener so it can surface notifications via a
// SnackBar even when no screen knows about the message.
final GlobalKey<ScaffoldMessengerState> _rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init is best-effort: if the device lacks Play Services the rest
  // of the app still works (push just won't fire). Use explicit options so
  // init doesn't depend on Gradle plugin processing of google-services.json
  // — which proved unreliable against Flutter 3.24's scaffold.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase.initializeApp failed: $e');
  }

  _jscAuth = JscAuthService();
  await _jscAuth.load();

  // Wire FCM. The service registers tokens lazily — it requests permission +
  // gets the FCM token from Firebase, and re-registers whenever the JSC auth
  // state flips to authenticated.
  try {
    _fcm = JscFcmService(_jscAuth);
    _jscAuth.unregisterFcmHook = () => _fcm!.unregisterBeforeSignOut();
    // Foreground messages: Android won't show a system notification while the
    // app is in the foreground, so we surface a SnackBar so the user sees
    // *something*. Background delivery still uses the OS notification UI.
    _fcm!.onForegroundMessage = (msg) {
      final title = msg.notification?.title ?? msg.data['title']?.toString();
      final body = msg.notification?.body ?? msg.data['body']?.toString();
      final text = [
        if (title != null && title.isNotEmpty) title,
        if (body != null && body.isNotEmpty) body,
      ].join(' — ');
      if (text.isEmpty) return;
      _rootMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            onPressed: () =>
                _rootMessengerKey.currentState?.hideCurrentSnackBar(),
          ),
        ),
      );
    };
    // Fire-and-forget init; UI doesn't depend on it.
    _fcm!.init();
  } catch (e) {
    debugPrint('FCM service init failed: $e');
  }

  runApp(const JuiceCommandApp());
}

class JuiceCommandApp extends StatelessWidget {
  const JuiceCommandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..load()),
        ChangeNotifierProvider<JscAuthService>.value(value: _jscAuth),
        if (_fcm != null) ChangeNotifierProvider<JscFcmService>.value(value: _fcm!),
        ChangeNotifierProvider(create: (_) => MaintenanceConfig()..load()),
        ProxyProvider<AuthService, CloudflareApi>(
          update: (_, auth, previous) => previous ?? CloudflareApi(auth),
          dispose: (_, api) => api.dispose(),
        ),
        ProxyProvider2<CloudflareApi, MaintenanceConfig, MaintenanceService>(
          update: (_, api, config, __) => MaintenanceService(api: api, config: config),
        ),
      ],
      child: MaterialApp(
        title: 'JUICE Command',
        theme: AppTheme.light(),
        scaffoldMessengerKey: _rootMessengerKey,
        debugShowCheckedModeBanner: false,
        home: const HomeShell(),
      ),
    );
  }
}
