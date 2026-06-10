import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dns_record.dart';
import '../models/ip_access_rule.dart';
import '../models/worker_route.dart';
import '../models/zone.dart';
import 'auth_service.dart';

class CloudflareApiException implements Exception {
  final int statusCode;
  final String message;
  final List<Map<String, dynamic>> errors;

  CloudflareApiException(this.statusCode, this.message, this.errors);

  @override
  String toString() => 'CloudflareApiException($statusCode): $message';
}

class CloudflareApi {
  static const String _base = 'https://api.cloudflare.com/client/v4';

  final AuthService auth;
  final http.Client _client;

  CloudflareApi(this.auth, {http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> get _headers {
    final creds = auth.credentials;
    if (creds == null) {
      throw StateError('Not authenticated');
    }
    return creds.headers();
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final req = http.Request(method, uri);
    req.headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);

    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);
    final decoded = res.body.isEmpty ? {} : jsonDecode(res.body) as Map<String, dynamic>;
    final success = (decoded['success'] as bool?) ?? false;
    if (!success || res.statusCode >= 400) {
      final errs = (decoded['errors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final msg = errs.isNotEmpty
          ? errs.map((e) => e['message']).whereType<String>().join('; ')
          : 'HTTP ${res.statusCode}';
      throw CloudflareApiException(res.statusCode, msg, errs);
    }
    return decoded['result'];
  }

  Future<bool> verifyCredentials() async {
    final creds = auth.credentials;
    if (creds == null) return false;
    return CloudflareApi.verifyWithCredentials(creds, client: _client);
  }

  static Future<String?> verifyWithCredentialsForError(
    Credentials creds, {
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    Future<String?> probe(String path) async {
      try {
        final uri = Uri.parse('$_base$path');
        final res = await c.get(uri, headers: creds.headers());
        Map<String, dynamic> body = {};
        if (res.body.isNotEmpty) {
          try {
            body = jsonDecode(res.body) as Map<String, dynamic>;
          } catch (_) {
            return 'Unexpected response from $path (HTTP ${res.statusCode})';
          }
        }
        if (res.statusCode >= 200 && res.statusCode < 300 && (body['success'] == true)) {
          return null;
        }
        final errs = (body['errors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final msg = errs.isNotEmpty
            ? errs.map((e) => e['message']).whereType<String>().join('; ')
            : 'HTTP ${res.statusCode}';
        return msg;
      } catch (e) {
        return e.toString();
      }
    }

    try {
      // /zones is what the app actually uses on first load, and it works
      // for both API Token (with Zone:Read) and Global API Key. Avoids
      // /user which requires a separate User:Read scope that our
      // recommended token doesn't include.
      final zonesErr = await probe('/zones?per_page=1');
      if (zonesErr == null) return null;
      // Fallback: /user/tokens/verify confirms the token itself is valid
      // even if the account has zero zones.
      final tokenErr = await probe('/user/tokens/verify');
      if (tokenErr == null) return null;
      return zonesErr;
    } finally {
      if (client == null) c.close();
    }
  }

  static Future<bool> verifyWithCredentials(
    Credentials creds, {
    http.Client? client,
  }) async {
    return (await verifyWithCredentialsForError(creds, client: client)) == null;
  }

  Future<List<Zone>> listZones({String? search}) async {
    final query = <String, String>{'per_page': '50'};
    if (search != null && search.isNotEmpty) query['name'] = 'contains:$search';
    final result = await _send('GET', '/zones', query: query) as List;
    return result.map((j) => Zone.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Zone> getZone(String zoneId) async {
    final result = await _send('GET', '/zones/$zoneId');
    return Zone.fromJson(result as Map<String, dynamic>);
  }

  Future<List<DnsRecord>> listDnsRecords(String zoneId) async {
    final result =
        await _send('GET', '/zones/$zoneId/dns_records', query: {'per_page': '100'}) as List;
    return result.map((j) => DnsRecord.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<DnsRecord> createDnsRecord(String zoneId, DnsRecord record) async {
    final result =
        await _send('POST', '/zones/$zoneId/dns_records', body: record.toCreatePayload());
    return DnsRecord.fromJson(result as Map<String, dynamic>);
  }

  Future<DnsRecord> updateDnsRecord(String zoneId, String recordId, DnsRecord record) async {
    final result = await _send(
      'PUT',
      '/zones/$zoneId/dns_records/$recordId',
      body: record.toCreatePayload(),
    );
    return DnsRecord.fromJson(result as Map<String, dynamic>);
  }

  Future<void> deleteDnsRecord(String zoneId, String recordId) async {
    await _send('DELETE', '/zones/$zoneId/dns_records/$recordId');
  }

  Future<List<IpAccessRule>> listAccessRules(String zoneId) async {
    final result = await _send(
      'GET',
      '/zones/$zoneId/firewall/access_rules/rules',
      query: {'per_page': '50'},
    ) as List;
    return result.map((j) => IpAccessRule.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<IpAccessRule> createAccessRule(
    String zoneId, {
    required AccessRuleMode mode,
    required AccessRuleTargetType targetType,
    required String value,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'mode': mode.apiValue,
      'configuration': {'target': targetType.apiValue, 'value': value},
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    };
    final result = await _send('POST', '/zones/$zoneId/firewall/access_rules/rules', body: body);
    return IpAccessRule.fromJson(result as Map<String, dynamic>);
  }

  Future<void> deleteAccessRule(String zoneId, String ruleId) async {
    await _send('DELETE', '/zones/$zoneId/firewall/access_rules/rules/$ruleId');
  }

  Future<bool> getDevelopmentMode(String zoneId) async {
    final result =
        await _send('GET', '/zones/$zoneId/settings/development_mode') as Map<String, dynamic>;
    return (result['value'] as String?) == 'on';
  }

  Future<void> setDevelopmentMode(String zoneId, bool enabled) async {
    await _send(
      'PATCH',
      '/zones/$zoneId/settings/development_mode',
      body: {'value': enabled ? 'on' : 'off'},
    );
  }

  Future<void> purgeEverything(String zoneId) async {
    await _send('POST', '/zones/$zoneId/purge_cache', body: {'purge_everything': true});
  }

  Future<List<Map<String, dynamic>>> listZoneSettings(String zoneId) async {
    final result = await _send('GET', '/zones/$zoneId/settings') as List;
    return result.cast<Map<String, dynamic>>();
  }

  // ── Worker Routes ──────────────────────────────────────────────────────

  Future<List<WorkerRoute>> listWorkerRoutes(String zoneId) async {
    final result = await _send('GET', '/zones/$zoneId/workers/routes') as List;
    return result.map((j) => WorkerRoute.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<WorkerRoute> createWorkerRoute(
    String zoneId, {
    required String pattern,
    required String script,
  }) async {
    final result = await _send(
      'POST',
      '/zones/$zoneId/workers/routes',
      body: {'pattern': pattern, 'script': script},
    );
    return WorkerRoute.fromJson(result as Map<String, dynamic>);
  }

  Future<void> deleteWorkerRoute(String zoneId, String routeId) async {
    await _send('DELETE', '/zones/$zoneId/workers/routes/$routeId');
  }

  // ── Zones lookup ───────────────────────────────────────────────────────

  Future<Zone?> findZoneByName(String name) async {
    final result =
        await _send('GET', '/zones', query: {'name': name, 'per_page': '1'}) as List;
    if (result.isEmpty) return null;
    return Zone.fromJson(result.first as Map<String, dynamic>);
  }

  // ── Workers KV (raw text values) ───────────────────────────────────────

  Future<String?> getKvValue(String accountId, String namespaceId, String key) async {
    final uri = Uri.parse(
      '$_base/accounts/$accountId/storage/kv/namespaces/$namespaceId/values/${Uri.encodeComponent(key)}',
    );
    final req = http.Request('GET', uri);
    req.headers.addAll(_headers);
    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 200 && res.statusCode < 300) return res.body;
    Map<String, dynamic> body = {};
    try {
      if (res.body.isNotEmpty) body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    final errs = (body['errors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final msg = errs.isNotEmpty
        ? errs.map((e) => e['message']).whereType<String>().join('; ')
        : 'HTTP ${res.statusCode}';
    throw CloudflareApiException(res.statusCode, msg, errs);
  }

  Future<void> putKvValue(
    String accountId,
    String namespaceId,
    String key,
    String value,
  ) async {
    final uri = Uri.parse(
      '$_base/accounts/$accountId/storage/kv/namespaces/$namespaceId/values/${Uri.encodeComponent(key)}',
    );
    final req = http.Request('PUT', uri);
    // Override Content-Type — KV values are raw bytes, not JSON.
    final headers = Map<String, String>.from(_headers);
    headers['Content-Type'] = 'text/plain';
    req.headers.addAll(headers);
    req.body = value;
    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    Map<String, dynamic> body = {};
    try {
      if (res.body.isNotEmpty) body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    final errs = (body['errors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final msg = errs.isNotEmpty
        ? errs.map((e) => e['message']).whereType<String>().join('; ')
        : 'HTTP ${res.statusCode}';
    throw CloudflareApiException(res.statusCode, msg, errs);
  }

  void dispose() => _client.close();
}
