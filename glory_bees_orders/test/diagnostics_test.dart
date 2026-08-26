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

  test('asks the comma form and the array form as genuinely different requests',
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
    // Probe 3: one parameter carrying all three statuses.
    expect(urls[2].queryParameters['status'], 'processing,on-hold,pending');
    // Probe 4: the PHP array form, which parses differently server-side. If
    // these two ever encode the same way the comparison proves nothing.
    expect(urls[3].queryParametersAll['status[]'],
        ['processing', 'on-hold', 'pending']);
    expect(urls[2].toString(), isNot(urls[3].toString()));
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
