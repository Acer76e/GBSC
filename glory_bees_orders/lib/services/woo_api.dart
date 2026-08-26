import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/order_status_count.dart';
import '../models/wc_order.dart';
import 'settings_service.dart';

/// An API failure with a message worth showing to a shop owner rather than a
/// developer.
class WooException implements Exception {
  final String message;
  final String? detail;

  const WooException(this.message, {this.detail});

  @override
  String toString() => message;
}

class WooApi {
  /// [client] exists so tests can supply a mock; production passes nothing.
  WooApi(this._settings, {http.Client? client})
      : _client = client ?? http.Client();

  final AppSettings _settings;
  final http.Client _client;

  /// Some hosts (and a few security plugins) strip the Authorization header
  /// before PHP sees it. After the first request proves which style works, we
  /// stick with it instead of paying for a failed round-trip every time.
  bool _useQueryAuth = false;

  static const Duration _timeout = Duration(seconds: 25);

  /// Sent on every orders request. Without a date bound, this store returns an
  /// empty list for every query.
  ///
  /// "Media API for WooCommerce" (WooPOS 2.8.1) hooks
  /// `woocommerce_rest_orders_prepare_object_query` and unconditionally sets
  /// `date_query[0]['column'] = 'post_modified'`. When a request carries no
  /// date filter, PHP autovivifies a date_query with a column and no bound.
  /// Under HPOS that column maps to `date_updated`, whose missing bound
  /// becomes timestamp 0, and the generated SQL asks for orders modified
  /// before 1970 — always zero rows, HTTP 200, empty body, no error anywhere.
  ///
  /// Supplying any real bound makes the plugin's rewrite behave correctly.
  /// Every order was modified after 1970, so this filters nothing out: the
  /// store returns all 321 orders with it and 0 without. It stays correct once
  /// the plugin is patched, so there is nothing here to rip out later.
  static const String _everyOrderEverModified = '1970-01-02T00:00:00';

  void dispose() => _client.close();

  Uri _uri(String path,
      {Map<String, dynamic> query = const {}, WooCreds? creds}) {
    final c = creds ?? _settings.creds;
    final base = Uri.parse('${c.storeUrl}/wp-json/wc/v3$path');
    final params = <String, dynamic>{...query};
    if (_useQueryAuth) {
      params['consumer_key'] = c.consumerKey;
      params['consumer_secret'] = c.consumerSecret;
    }
    return base.replace(queryParameters: params);
  }

  Map<String, String> _headers({WooCreds? creds}) {
    final c = creds ?? _settings.creds;
    final headers = <String, String>{'Accept': 'application/json'};
    if (!_useQueryAuth) {
      final encoded =
          base64Encode(utf8.encode('${c.consumerKey}:${c.consumerSecret}'));
      headers['Authorization'] = 'Basic $encoded';
    }
    return headers;
  }

  /// Runs [send], and if it comes back as an auth failure once, retries with
  /// the credentials in the query string instead of the header.
  Future<http.Response> _authed(
    Future<http.Response> Function() send,
  ) async {
    var response = await send();
    if (response.statusCode == 401 && !_useQueryAuth) {
      _useQueryAuth = true;
      response = await send();
      if (response.statusCode == 401) {
        // Neither style worked, so it really is the key that's wrong. Reset so
        // the next attempt starts from the normal header again.
        _useQueryAuth = false;
      }
    }
    return response;
  }

  Future<List<WcOrder>> fetchPendingOrders() async {
    if (!_settings.isConfigured) {
      throw const WooException('Not connected to the store yet.');
    }

    final query = <String, dynamic>{
      // See _everyOrderEverModified — without this the store returns nothing.
      'modified_after': _everyOrderEverModified,
      // Comma-joined, NOT a list: Dart encodes a list as a repeated key
      // (status=a&status=b), and PHP keeps only the last one — so a repeated
      // key silently narrows the request to one status. WordPress splits a
      // comma-separated string into an array for array-typed parameters.
      'status': _settings.activeStatuses.join(','),
      'per_page': '50',
      'orderby': 'date',
      'order': _settings.oldestFirst ? 'asc' : 'desc',
      // Trim the payload: a full WooCommerce order carries tax lines, coupon
      // lines and refunds this app never shows.
      '_fields': 'id,number,status,currency_symbol,date_created,date_created_gmt,'
          'total,payment_method_title,customer_note,billing,shipping,'
          'line_items,shipping_lines',
    };

    final response = await _run(() => _authed(
          () => _client
              .get(_uri('/orders', query: query), headers: _headers())
              .timeout(_timeout),
        ));

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const WooException(
        'The store sent back something unexpected.',
        detail: 'Expected a list of orders.',
      );
    }

    return decoded
        .whereType<Map>()
        .map((json) => WcOrder.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  /// Asks the store which order statuses it has and how many orders are in
  /// each. Drives the status picker so custom statuses added by plugins are
  /// offered without this app needing to know about them.
  Future<List<OrderStatusCount>> fetchStatusCounts() async {
    final response = await _run(() => _authed(
          () => _client
              .get(_uri('/reports/orders/totals'), headers: _headers())
              .timeout(_timeout),
        ));
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const WooException('The store sent back an unexpected status list.');
    }
    return decoded
        .whereType<Map>()
        .map((json) => OrderStatusCount.fromJson(Map<String, dynamic>.from(json)))
        .where((status) => status.isWaitingCandidate)
        .toList();
  }

  /// Flips an order to `completed`. Requires a Read/Write API key — a
  /// read-only key comes back 401/403, which is reported as such.
  Future<void> markCompleted(int orderId) async {
    await _run(() => _authed(
          () => _client
              .put(
                _uri('/orders/$orderId'),
                headers: {
                  ..._headers(),
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({'status': 'completed'}),
              )
              .timeout(_timeout),
        ));
  }

  /// Cheap round-trip used by the setup screen to prove the key works before
  /// saving it. Pass [creds] to test a key that isn't stored yet.
  ///
  /// Returns null when the store didn't send a count header — some hosts and
  /// CDNs strip X-WP-*. That is NOT the same as a count of zero, and reporting
  /// it as zero sent this app's own troubleshooting down the wrong path once
  /// already.
  Future<int?> testConnection({WooCreds? creds}) async {
    if (creds != null && !creds.isComplete) {
      throw const WooException('Fill in the web address, key and secret.');
    }
    final response = await _run(() => _authed(
          () => _client
              .get(
                _uri(
                  '/orders',
                  query: {
                    'modified_after': _everyOrderEverModified,
                    // Comma-joined for the same reason as fetchPendingOrders.
                    'status': _settings.activeStatuses.join(','),
                    'per_page': '1',
                    '_fields': 'id',
                  },
                  creds: creds,
                ),
                headers: _headers(creds: creds),
              )
              .timeout(_timeout),
        ));
    final total = response.headers['x-wp-total'];
    if (total == null) return null;
    return int.tryParse(total);
  }

  /// Issues a request exactly the way the app does, but hands back the raw
  /// response for the diagnostics screen instead of translating errors. Query
  /// values may be a String or a List<String>; a list becomes a repeated key.
  Future<http.Response> probe(String path, Map<String, dynamic> query) {
    return _authed(
      () => _client
          .get(_uri(path, query: query), headers: _headers())
          .timeout(_timeout),
    );
  }

  /// Exposed so the diagnostics screen probes the store the same way the
  /// order list does.
  static String get epochModifiedAfter => _everyOrderEverModified;

  /// The URL a probe hits, with no credentials in it — safe to display and to
  /// paste into a chat.
  Uri redactedUrl(String path, Map<String, dynamic> query) =>
      Uri.parse('${_settings.storeUrl}/wp-json/wc/v3$path')
          .replace(queryParameters: query);

  /// Wraps a request with the network- and HTTP-level error translation that
  /// every call needs.
  Future<http.Response> _run(Future<http.Response> Function() send) async {
    late http.Response response;
    try {
      response = await send();
    } on TimeoutException {
      throw const WooException(
        'The store took too long to answer.',
        detail: 'Check your signal and try again.',
      );
    } on SocketException catch (e) {
      throw WooException(
        'Can\'t reach the store.',
        detail: 'Check the web address and your connection. (${e.osError?.message ?? e.message})',
      );
    } on HandshakeException {
      throw const WooException(
        'Secure connection to the store failed.',
        detail: 'The site\'s SSL certificate could not be verified.',
      );
    } on FormatException {
      throw const WooException('That store address doesn\'t look right.');
    } on http.ClientException catch (e) {
      throw WooException('Connection to the store failed.', detail: e.message);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw _httpError(response);
  }

  WooException _httpError(http.Response response) {
    // WooCommerce errors come back as {"code": "...", "message": "..."}.
    String? apiMessage;
    String? apiCode;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        apiMessage = decoded['message']?.toString();
        apiCode = decoded['code']?.toString();
      }
    } catch (_) {
      // Not JSON — likely an HTML error page from the host.
    }

    switch (response.statusCode) {
      case 401:
        return WooException(
          'The store rejected the API key.',
          detail: apiMessage ??
              'Double-check the consumer key and secret in Settings.',
        );
      case 403:
        if (apiCode == 'woocommerce_rest_cannot_edit') {
          return const WooException(
            'This API key is read-only.',
            detail: 'Create a Read/Write key in WooCommerce to change orders '
                'from the phone.',
          );
        }
        return WooException(
          'The store blocked the request.',
          detail: apiMessage ??
              'A security plugin or firewall may be blocking the REST API.',
        );
      case 404:
        return WooException(
          'Couldn\'t find the WooCommerce API on that site.',
          detail: apiMessage ??
              'Check the web address, and that permalinks are not set to "Plain".',
        );
      default:
        return WooException(
          'The store returned an error (${response.statusCode}).',
          detail: apiMessage,
        );
    }
  }
}
