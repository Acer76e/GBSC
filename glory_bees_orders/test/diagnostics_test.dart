import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glory_bees_orders/services/diagnostics.dart';
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
  List<String> get activeStatuses => const ['processing', 'on-hold', 'pending'];
  @override
  WooCreds get creds => const WooCreds(
        storeUrl: 'https://shop.example',
        consumerKey: 'ck_abc',
        consumerSecret: 'cs_xyz',
      );
}

void main() {
  late _FakeSettings settings;
  setUp(() => settings = _FakeSettings());

  test('probes with and without the date bound, so the store bug stays visible',
      () async {
    final urls = <Uri>[];
    final api = WooApi(
      settings,
      client: MockClient((request) async {
        urls.add(request.url);
        return http.Response('[]', 200);
      }),
    );

    await Diagnostics(api, settings).run();

    expect(urls, hasLength(4));
    // 2: what the app relies on — a date bound present.
    expect(urls[1].queryParameters['modified_after'], '1970-01-02T00:00:00');
    // 3: deliberately without it. This is the control: while the store is
    // unpatched this returns nothing, and if it ever starts returning orders
    // the workaround can be removed.
    expect(urls[2].queryParameters.containsKey('modified_after'), isFalse);
    // 4: the real order-list request, statuses and bound together.
    expect(urls[3].queryParameters['status'], 'processing,on-hold,pending');
    expect(urls[3].queryParameters['modified_after'], '1970-01-02T00:00:00');
  });

  test('reports which statuses the store admits to having', () async {
    final api = WooApi(
      settings,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/reports/orders/totals')) {
          return http.Response(
            jsonEncode([
              {'slug': 'pending', 'name': 'Pending payment', 'total': 1},
              {'slug': 'processing', 'name': 'Processing', 'total': 0},
              {'slug': 'completed', 'name': 'Completed', 'total': 812},
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );

    final results = await Diagnostics(api, settings).run();

    expect(results.first.outcome, contains('pending=1'));
    expect(results.first.outcome, contains('completed=812'));
    // Statuses at zero are noise on a small screen.
    expect(results.first.outcome, isNot(contains('processing=0')));
  });

  test('names the orders it got back so they can be matched against admin',
      () async {
    final api = WooApi(
      settings,
      client: MockClient((_) async => http.Response(
            jsonEncode([
              {'id': 9, 'number': '45999', 'status': 'pending'}
            ]),
            200,
            headers: {'x-wp-total': '1'},
          )),
    );

    final results = await Diagnostics(api, settings).run();
    expect(results[1].outcome, contains('#45999 pending'));
    expect(results[1].outcome, contains('X-WP-Total: 1'));
  });

  test('says when no count header came back instead of implying zero',
      () async {
    final api = WooApi(
      settings,
      client: MockClient((_) async => http.Response('[]', 200)),
    );

    final results = await Diagnostics(api, settings).run();
    expect(results[1].outcome, contains('0 orders'));
    expect(results[1].outcome, contains('no X-WP-Total header'));
  });

  test('shows an error body rather than swallowing it', () async {
    final api = WooApi(
      settings,
      client: MockClient((_) async => http.Response(
            jsonEncode({'code': 'woocommerce_rest_cannot_view'}),
            401,
          )),
    );

    final results = await Diagnostics(api, settings).run();
    expect(results.first.ok, isFalse);
    expect(results.first.outcome, contains('401'));
    expect(results.first.detail, contains('woocommerce_rest_cannot_view'));
  });

  test('never puts credentials in a URL meant to be shared', () async {
    final api = WooApi(
      settings,
      client: MockClient((_) async => http.Response('[]', 200)),
    );

    final results = await Diagnostics(api, settings).run();
    for (final result in results) {
      expect(result.url, isNot(contains('cs_xyz')));
      expect(result.url, isNot(contains('ck_abc')));
      expect(result.asText, isNot(contains('cs_xyz')));
    }
  });
}
