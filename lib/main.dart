import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init is best-effort: if google-services.json is missing or the
  // device lacks Play Services, the rest of the app still works (push just
  // won't fire).
  try {
    await Firebase.initializeApp();
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
        debugShowCheckedModeBanner: false,
        home: const HomeShell(),
      ),
    );
  }
}
