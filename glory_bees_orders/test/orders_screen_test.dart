import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glory_bees_orders/screens/orders_screen.dart';
import 'package:glory_bees_orders/services/orders_controller.dart';
import 'package:glory_bees_orders/services/settings_service.dart';
import 'package:glory_bees_orders/services/woo_api.dart';
import 'package:glory_bees_orders/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

class _FakeSettings extends AppSettings {
  _FakeSettings({this.pickupsVisible = true});

  final bool pickupsVisible;

  @override
  String get storeUrl => 'https://shop.example';
  @override
  String get consumerKey => 'ck_abc';
  @override
  String get consumerSecret => 'cs_xyz';
  @override
  bool get isConfigured => true;
  @override
  bool get showPickup => pickupsVisible;
  @override
  WooCreds get creds => const WooCreds(
        storeUrl: 'https://shop.example',
        consumerKey: 'ck_abc',
        consumerSecret: 'cs_xyz',
      );
}

String _ordersPayload() => jsonEncode([
      {
        'id': 1,
        'number': '45812',
        'status': 'processing',
        'date_created_gmt':
            DateTime.now().toUtc().subtract(const Duration(days: 3)).toIso8601String(),
        'total': '128.45',
        'shipping': {'first_name': 'Dana', 'last_name': 'Whitfield', 'address_1': '18 Mill Race Rd', 'city': 'Bel Air'},
        'line_items': [
          {'name': 'Thread', 'quantity': 3, 'total': '26.85'}
        ],
        'shipping_lines': [
          {'method_id': 'flat_rate', 'method_title': 'Flat rate'}
        ],
      },
      {
        'id': 2,
        'number': '45813',
        'status': 'on-hold',
        'date_created_gmt': DateTime.now().toUtc().toIso8601String(),
        'total': '42.00',
        'billing': {'first_name': 'Rae', 'last_name': 'Olsen'},
        'shipping': {},
        'line_items': [
          {'name': 'Bobbins', 'quantity': 2, 'total': '42.00'}
        ],
        'shipping_lines': [
          {'method_id': 'local_pickup', 'method_title': 'Local pickup'}
        ],
      },
    ]);

Widget _app({required AppSettings settings, required String body, int status = 200}) {
  final api = WooApi(
    settings,
    client: MockClient((_) async => http.Response(body, status)),
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppSettings>.value(value: settings),
      Provider<WooApi>.value(value: api),
      ChangeNotifierProvider<OrdersController>.value(
        value: OrdersController(settings: settings, api: api),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const OrdersScreen()),
  );
}

void main() {
  // The screen keeps a periodic refresh timer, so every test tears the tree
  // down at the end to let `dispose` cancel it.
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('counts only the orders that need a parcel', (tester) async {
    await tester.pumpWidget(_app(settings: _FakeSettings(), body: _ordersPayload()));
    await tester.pumpAndSettle();

    // Two orders came back, but one is a local pickup.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('order to ship'), findsOneWidget);
    expect(find.text('1 pickup'), findsOneWidget);
    expect(find.text('#45812'), findsOneWidget);
    expect(find.text('#45813'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('shows how long the oldest order has waited', (tester) async {
    await tester.pumpWidget(_app(settings: _FakeSettings(), body: _ordersPayload()));
    await tester.pumpAndSettle();

    expect(find.text('3 days'), findsOneWidget);
    expect(find.text('Pickup'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('hides pickups when the preference is off', (tester) async {
    await tester.pumpWidget(
      _app(settings: _FakeSettings(pickupsVisible: false), body: _ordersPayload()),
    );
    await tester.pumpAndSettle();

    expect(find.text('#45812'), findsOneWidget);
    expect(find.text('#45813'), findsNothing);
    expect(find.text('1 pickup hidden'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('says so plainly when nothing is waiting', (tester) async {
    await tester.pumpWidget(_app(settings: _FakeSettings(), body: '[]'));
    await tester.pumpAndSettle();

    expect(find.text('All caught up'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    // Says what it looked for, so "empty" can't be confused with "wrong filter".
    expect(find.text('Checking for: Processing, On hold'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('surfaces a rejected key with a way to fix it', (tester) async {
    await tester.pumpWidget(_app(
      settings: _FakeSettings(),
      body: jsonEncode({'message': 'Consumer key is invalid.'}),
      status: 401,
    ));
    await tester.pumpAndSettle();

    expect(find.text('The store rejected the API key.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await teardown(tester);
  });
}
