import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'services/auth_service.dart';
import 'services/cloudflare_api.dart';
import 'services/maintenance_config.dart';
import 'services/maintenance_service.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JuiceCommandApp());
}

class JuiceCommandApp extends StatelessWidget {
  const JuiceCommandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..load()),
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
