import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/orders_screen.dart';
import 'screens/setup_screen.dart';
import 'services/orders_controller.dart';
import 'services/settings_service.dart';
import 'services/woo_api.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Settings load before the first frame so the app opens straight onto the
  // order list instead of flashing the setup screen on every launch.
  final settings = AppSettings();
  await settings.load();
  final api = WooApi(settings);
  runApp(
    GloryBeesOrdersApp(
      settings: settings,
      api: api,
      orders: OrdersController(settings: settings, api: api),
    ),
  );
}

class GloryBeesOrdersApp extends StatelessWidget {
  final AppSettings settings;
  final WooApi api;
  final OrdersController orders;

  const GloryBeesOrdersApp({
    super.key,
    required this.settings,
    required this.api,
    required this.orders,
  });

  @override
  Widget build(BuildContext context) {
    // These three live as long as the app does, so they're plain values rather
    // than proxy providers: `settings` never gets swapped for a new instance.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        Provider<WooApi>.value(value: api),
        ChangeNotifierProvider<OrdersController>.value(value: orders),
      ],
      child: MaterialApp(
        title: 'Glory Bees Orders',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _Root(),
      ),
    );
  }
}

/// Sends first-run users to setup and everyone else straight to the list.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final configured = context.select<AppSettings, bool>((s) => s.isConfigured);
    return configured ? const OrdersScreen() : const SetupScreen();
  }
}
