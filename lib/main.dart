import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/domains_screen.dart';
import 'services/auth_service.dart';
import 'services/cloudflare_api.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CloudflareMobileApp());
}

class CloudflareMobileApp extends StatelessWidget {
  const CloudflareMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..load()),
        ProxyProvider<AuthService, CloudflareApi>(
          update: (_, auth, previous) => previous ?? CloudflareApi(auth),
          dispose: (_, api) => api.dispose(),
        ),
      ],
      child: MaterialApp(
        title: 'Cloudflare Mobile',
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!auth.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.isAuthenticated ? const DomainsScreen() : const AuthScreen();
  }
}
