import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glory_bees_orders/models/order_status_count.dart';
import 'package:glory_bees_orders/services/settings_service.dart';
import 'package:glory_bees_orders/services/woo_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeSettings extends AppSettings {
  @override
  String get storeUrl => 'https://shop.example';
  @override
  String get consumerKey => 'ck_abc';
  @override
  String get consumerSecret => 'cs_xyz';
  @override
  bool get isConfigured => true;
  @override
  WooCreds get creds => const WooCreds(
        storeUrl: 'https://shop.example',
        consumerKey: 'ck_abc',
        consumerSecret: 'cs_xyz',
      );
}

/// The real response from this shop, custom statuses and all.
const String _totalsJson = '''
[{"slug":"pending","name":"Pending payment","total":1},
 {"slug":"partially-paid","name":"Partially Paid","total":0},
 {"slug":"processing","name":"Processing","total":0},
 {"slug":"ready-pickup","name":"Ready for Pickup","total":0},
 {"slug":"on-hold","name":"On hold","total":0},
 {"slug":"backordered","name":"Backordered","total":1},
 {"slug":"completed","name":"Completed","total":162},
 {"slug":"cancelled","name":"Cancelled","total":111},
 {"slug":"refunded","name":"Refunded","total":18},
 {"slug":"failed","name":"Failed","total":28},
 {"slug":"checkout-draft","name":"Draft","total":0}]
''';

void main() {
  test('offers the shop\'s custom statuses, not just the standard ones',
      () async {
    final api = WooApi(
      _FakeSettings(),
      client: MockClient((_) async => http.Response(_totalsJson, 200)),
    );

    final statuses = await api.fetchStatusCounts();
    final slugs = statuses.map((s) => s.slug).toList();

    expect(slugs, contains('ready-pickup'));
    expect(slugs, contains('partially-paid'));
    expect(slugs, contains('backordered'));
    expect(slugs, contains('processing'));
  });

  test('leaves out statuses an order has finished in', () async {
    final api = WooApi(
      _FakeSettings(),
      client: MockClient((_) async => http.Response(_totalsJson, 200)),
    );

    final slugs = (await api.fetchStatusCounts()).map((s) => s.slug);

    expect(slugs, isNot(contains('completed')));
    expect(slugs, isNot(contains('cancelled')));
    expect(slugs, isNot(contains('refunded')));
    expect(slugs, isNot(contains('failed')));
    expect(slugs, isNot(contains('checkout-draft')));
  });

  test('keeps the store\'s own names and current counts', () async {
    final api = WooApi(
      _FakeSettings(),
      client: MockClient((_) async => http.Response(_totalsJson, 200)),
    );

    final statuses = await api.fetchStatusCounts();
    final backordered = statuses.firstWhere((s) => s.slug == 'backordered');

    expect(backordered.name, 'Backordered');
    expect(backordered.total, 1);
  });

  test('hits the reports endpoint the diagnostics screen also uses', () async {
    late Uri captured;
    final api = WooApi(
      _FakeSettings(),
      client: MockClient((request) async {
        captured = request.url;
        return http.Response(_totalsJson, 200);
      }),
    );

    await api.fetchStatusCounts();
    expect(captured.path, '/wp-json/wc/v3/reports/orders/totals');
  });

  test('surfaces a key without reports access as a WooException', () async {
    final api = WooApi(
      _FakeSettings(),
      client: MockClient((_) async => http.Response(
            jsonEncode({'code': 'woocommerce_rest_cannot_view'}),
            401,
          )),
    );

    await expectLater(api.fetchStatusCounts(), throwsA(isA<WooException>()));
  });

  test('copes with totals arriving as strings', () async {
    final status = OrderStatusCount.fromJson(
        {'slug': 'ready-pickup', 'name': 'Ready for Pickup', 'total': '4'});
    expect(status.total, 4);
  });

  test('the built-in fallback list also carries the custom statuses', () {
    expect(kSelectableStatuses, contains('ready-pickup'));
    expect(kSelectableStatuses, contains('partially-paid'));
    expect(kSelectableStatuses, contains('backordered'));
    expect(statusLabel('ready-pickup'), 'Ready for Pickup');
    expect(statusLabel('partially-paid'), 'Partially Paid');
  });
}
