import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glory_bees_orders/services/settings_service.dart';
import 'package:glory_bees_orders/services/woo_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// AppSettings talks to platform secure storage, which doesn't exist in a
/// plain unit test, so the API is exercised against a stand-in that reports
/// the same credentials without ever touching a channel.
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
  List<String> get activeStatuses => const ['processing', 'on-hold'];
  @override
  bool get oldestFirst => true;
  @override
  WooCreds get creds => const WooCreds(
        storeUrl: 'https://shop.example',
        consumerKey: 'ck_abc',
        consumerSecret: 'cs_xyz',
      );
}

const String _basicAuth = 'Basic Y2tfYWJjOmNzX3h5eg=='; // ck_abc:cs_xyz

void main() {
  late _FakeSettings settings;

  setUp(() => settings = _FakeSettings());

  test('asks for the selected statuses, oldest first, over Basic auth',
      () async {
    late http.Request captured;
    final api = WooApi(
      settings,
      client: MockClient((request) async {
        captured = request;
        return http.Response('[]', 200);
      }),
    );

    await api.fetchPendingOrders();

    expect(captured.url.origin, 'https://shop.example');
    expect(captured.url.path, '/wp-json/wc/v3/orders');
    // Comma-joined into ONE parameter. A repeated key (status=a&status=b) is
    // what Dart produces from a list, and PHP keeps only the last one — which
    // silently asked the store for on-hold orders only and returned nothing.
    expect(captured.url.queryParameters['status'], 'processing,on-hold');
    expect(captured.url.queryParametersAll['status'], hasLength(1));
    expect(captured.url.queryParameters['order'], 'asc');
    expect(captured.url.queryParameters['per_page'], '50');
    expect(captured.url.queryParameters['_fields'], contains('line_items'));
    expect(captured.headers['Authorization'], _basicAuth);
    // Credentials belong in the header, not in a URL that lands in server logs.
    expect(captured.url.queryParameters.containsKey('consumer_secret'), isFalse);
  });

  test('parses the returned orders', () async {
    final api = WooApi(
      settings,
      client: MockClient((_) async => http.Response(
            jsonEncode([
              {'id': 3, 'number': '3', 'status': 'processing', 'total': '9.99'}
            ]),
            200,
          )),
    );

    final orders = await api.fetchPendingOrders();
    expect(orders, hasLength(1));
    expect(orders.single.number, '3');
  });

  test('retries with query-string credentials when a host strips the header',
      () async {
    final calls = <Uri>[];
    final api = WooApi(
      settings,
      client: MockClient((request) async {
        calls.add(request.url);
        if (request.headers.containsKey('Authorization')) {
          return http.Response(
            jsonEncode({'code': 'woocommerce_rest_authentication_error'}),
            401,
          );
        }
        return http.Response('[]', 200);
      }),
    );

    await api.fetchPendingOrders();

    expect(calls, hasLength(2), reason: 'header attempt, then query-string');
    expect(calls.last.queryParameters['consumer_key'], 'ck_abc');
    expect(calls.last.queryParameters['consumer_secret'], 'cs_xyz');
  });

  test('reports a genuinely bad key rather than looping', () async {
    var calls = 0;
    final api = WooApi(
      settings,
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({'message': 'Consumer key is invalid.'}),
          401,
        );
      }),
    );

    await expectLater(
      api.fetchPendingOrders(),
      throwsA(isA<WooException>()
          .having((e) => e.message, 'message', contains('rejected the API key'))),
    );
    expect(calls, 2, reason: 'one header attempt plus one query-string attempt');
  });

  test('explains a read-only key when an update is refused', () async {
    final api = WooApi(
      settings,
      client: MockClient((_) async => http.Response(
            jsonEncode({'code': 'woocommerce_rest_cannot_edit'}),
            403,
          )),
    );

    await expectLater(
      api.markCompleted(12),
      throwsA(isA<WooException>()
          .having((e) => e.message, 'message', contains('read-only'))),
    );
  });

  test('explains a missing REST API instead of showing a bare 404', () async {
    final api = WooApi(
      settings,
      client: MockClient((_) async => http.Response('<html>Not Found</html>', 404)),
    );

    await expectLater(
      api.fetchPendingOrders(),
      throwsA(isA<WooException>().having(
          (e) => e.detail, 'detail', contains('permalinks'))),
    );
  });

  test('marks an order completed with the right verb and body', () async {
    late http.Request captured;
    final api = WooApi(
      settings,
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'id': 12, 'status': 'completed'}), 200);
      }),
    );

    await api.markCompleted(12);

    expect(captured.method, 'PUT');
    expect(captured.url.path, '/wp-json/wc/v3/orders/12');
    expect(jsonDecode(captured.body), {'status': 'completed'});
  });

  test('reads the order count out of the WP total header', () async {
    late http.Request captured;
    final api = WooApi(
      settings,
      client: MockClient((request) async {
        captured = request;
        return http.Response('[]', 200, headers: {'x-wp-total': '7'});
      }),
    );

    expect(await api.testConnection(), 7);
    // The count shown in Settings has to be counting the same statuses the
    // list screen asks for, or "connected, 0 orders" means nothing.
    expect(captured.url.queryParameters['status'], 'processing,on-hold');
  });

  test('refuses to test an incomplete credential set', () async {
    final api = WooApi(settings, client: MockClient((_) async {
      fail('should not have made a request');
    }));

    await expectLater(
      api.testConnection(
          creds: const WooCreds(
              storeUrl: 'https://shop.example', consumerKey: '', consumerSecret: '')),
      throwsA(isA<WooException>()),
    );
  });
}
