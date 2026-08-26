import 'dart:convert';


import 'settings_service.dart';
import 'woo_api.dart';

/// One question asked of the store, and what came back.
class ProbeResult {
  final String title;
  final String url;
  final String outcome;
  final String? detail;
  final bool ok;

  const ProbeResult({
    required this.title,
    required this.url,
    required this.outcome,
    required this.ok,
    this.detail,
  });

  String get asText => [
        title,
        '  $url',
        '  $outcome',
        if (detail != null) '  $detail',
      ].join('\n');
}

/// Asks the store a short series of questions whose answers, together, say
/// where an empty order list is coming from: no orders at all, no orders in
/// the chosen statuses, or a filter the store isn't reading the way the app
/// means it.
class Diagnostics {
  Diagnostics(this._api, this._settings);

  final WooApi _api;
  final AppSettings _settings;

  static const String _fields = 'id,number,status';

  Future<List<ProbeResult>> run() async {
    final statuses = _settings.activeStatuses;
    return [
      await _probe(
        title: '1. What the store says it has, per status',
        path: '/reports/orders/totals',
        query: const {},
        summarise: _summariseTotals,
      ),
      await _probe(
        title: '2. Any orders at all (no status filter)',
        path: '/orders',
        query: {
          'status': 'any',
          'per_page': '3',
          '_fields': _fields,
          'modified_after': WooApi.epochModifiedAfter,
        },
        summarise: _summariseOrders,
      ),
      // Proves the date bound is still doing the work. If this one starts
      // returning orders too, the store has been patched and the workaround
      // in WooApi could come out.
      await _probe(
        title: '3. Same request with no date bound (the store\'s bug)',
        path: '/orders',
        query: {'status': 'any', 'per_page': '3', '_fields': _fields},
        summarise: _summariseOrders,
      ),
      await _probe(
        title: '4. The exact request the order list makes',
        path: '/orders',
        query: {
          'status': statuses.join(','),
          'per_page': '3',
          '_fields': _fields,
          'modified_after': WooApi.epochModifiedAfter,
        },
        summarise: _summariseOrders,
      ),
    ];
  }

  Future<ProbeResult> _probe({
    required String title,
    required String path,
    required Map<String, dynamic> query,
    required String Function(dynamic decoded) summarise,
  }) async {
    final shown = _api.redactedUrl(path, query).toString();
    try {
      final response = await _api.probe(path, query);
      // response.request is the LAST request made, so this also reveals a
      // redirect (a www. or http->https hop) that could be losing the filter.
      final landedOn = response.request?.url.toString();
      final redirected = landedOn != null &&
              Uri.parse(landedOn).replace(queryParameters: {}).toString() !=
                  Uri.parse(shown).replace(queryParameters: {}).toString()
          ? '\n  landed on: $landedOn'
          : '';

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ProbeResult(
          title: title,
          url: shown,
          ok: false,
          outcome: 'HTTP ${response.statusCode}',
          detail: '${_snippet(response.body)}$redirected',
        );
      }

      final decoded = jsonDecode(response.body);
      final total = response.headers['x-wp-total'];
      return ProbeResult(
        title: title,
        url: shown,
        ok: true,
        outcome: 'HTTP 200 · ${summarise(decoded)}'
            '${total == null ? ' · no X-WP-Total header' : ' · X-WP-Total: $total'}',
        detail: redirected.isEmpty ? null : redirected.trim(),
      );
    } catch (e) {
      return ProbeResult(
        title: title,
        url: shown,
        ok: false,
        outcome: 'Failed',
        detail: e.toString(),
      );
    }
  }

  static String _summariseOrders(dynamic decoded) {
    if (decoded is! List) return 'unexpected shape: ${_snippet(decoded.toString())}';
    if (decoded.isEmpty) return '0 orders';
    final listed = decoded
        .whereType<Map>()
        .map((o) => '#${o['number'] ?? o['id']} ${o['status']}')
        .join(', ');
    return '${decoded.length} order(s): $listed';
  }

  static String _summariseTotals(dynamic decoded) {
    if (decoded is! List) return 'unexpected shape: ${_snippet(decoded.toString())}';
    final parts = decoded
        .whereType<Map>()
        .where((row) => (row['total'] ?? 0).toString() != '0')
        .map((row) => '${row['slug']}=${row['total']}')
        .join('  ');
    return parts.isEmpty ? 'every status reports 0' : parts;
  }

  static String _snippet(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 300 ? flat : '${flat.substring(0, 300)}…';
  }
}
