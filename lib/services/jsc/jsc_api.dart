import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/jsc/jsc_monitor.dart';
import '../../models/jsc/jsc_ticket.dart';
import '../../models/jsc/jsc_user.dart';
import 'jsc_auth_service.dart';

enum JscLoginMode { admin, client }

class JscApiException implements Exception {
  final int statusCode;
  final String message;
  JscApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class JscApi {
  final JscAuthService auth;
  final http.Client _client;

  JscApi(this.auth, {http.Client? client}) : _client = client ?? http.Client();

  Uri _u(String path, [Map<String, String>? q]) {
    final base = Uri.parse(auth.baseUrl);
    final fullPath = '/api$path';
    return base.replace(path: fullPath, queryParameters: q);
  }

  Map<String, String> _headers({bool needAuth = true}) {
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (needAuth && auth.token != null) {
      h['Authorization'] = 'Bearer ${auth.token}';
    }
    return h;
  }

  Future<dynamic> _decode(http.Response res) async {
    Map<String, dynamic> body = const {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        throw JscApiException(
          res.statusCode,
          'Unexpected response (HTTP ${res.statusCode})',
        );
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    if (res.statusCode == 401) {
      // Token rejected by the server (expired/revoked). Wipe creds so the
      // JscTab swaps to the login screen with a "session expired" banner.
      // Fire-and-forget — we still throw below so callers don't get a
      // half-populated response.
      auth.markSessionExpired();
    }
    final msg = body['error']?.toString() ??
        body['message']?.toString() ??
        'HTTP ${res.statusCode}';
    throw JscApiException(res.statusCode, msg);
  }

  // ── Auth ───────────────────────────────────────────────────────────────

  Future<({String token, JscUser user})> login({
    required JscLoginMode mode,
    required String email,
    required String password,
  }) async {
    final path = mode == JscLoginMode.admin
        ? '/auth/admin/login'
        : '/auth/client/login';
    final res = await _client.post(
      _u(path),
      headers: _headers(needAuth: false),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final body = await _decode(res) as Map<String, dynamic>;
    final token = body['token']?.toString();
    if (token == null || token.isEmpty) {
      throw JscApiException(res.statusCode, 'Server did not return a token');
    }
    final userMap = (body['user'] as Map<String, dynamic>?) ?? const {};
    final inferredType = mode == JscLoginMode.admin ? 'admin' : 'client';
    final user = JscUser.fromJson({
      'type': inferredType,
      ...userMap,
    });
    return (token: token, user: user);
  }

  Future<JscUser> me() async {
    final res = await _client.get(_u('/auth/me'), headers: _headers());
    final body = await _decode(res) as Map<String, dynamic>;
    return JscUser.fromJson((body['user'] as Map<String, dynamic>?) ?? const {});
  }

  // ── Tickets ────────────────────────────────────────────────────────────

  Future<List<JscTicket>> listMyTickets() async {
    final res = await _client.get(_u('/tickets/mine'), headers: _headers());
    final body = await _decode(res) as Map<String, dynamic>;
    final list = (body['tickets'] as List?) ?? const [];
    return list.map((j) => JscTicket.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<JscTicket>> listAllTickets({String? status, String? priority}) async {
    final q = <String, String>{};
    if (status != null && status.isNotEmpty) q['status'] = status;
    if (priority != null && priority.isNotEmpty) q['priority'] = priority;
    final res = await _client.get(
      _u('/tickets', q.isEmpty ? null : q),
      headers: _headers(),
    );
    final body = await _decode(res) as Map<String, dynamic>;
    final list = (body['tickets'] as List?) ?? const [];
    return list.map((j) => JscTicket.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<({JscTicket ticket, List<JscTicketMessage> messages})> getTicket(
    String id, {
    required bool asClient,
  }) async {
    final path = asClient ? '/tickets/mine/$id' : '/tickets/$id';
    final res = await _client.get(_u(path), headers: _headers());
    final body = await _decode(res) as Map<String, dynamic>;
    final ticket = JscTicket.fromJson((body['ticket'] as Map<String, dynamic>?) ?? const {});
    final msgs = ((body['messages'] as List?) ?? const [])
        .map((j) => JscTicketMessage.fromJson(j as Map<String, dynamic>))
        .toList();
    return (ticket: ticket, messages: msgs);
  }

  Future<void> replyToTicket(
    String id, {
    required bool asClient,
    required String body,
    bool isInternal = false,
  }) async {
    final path = asClient ? '/tickets/mine/$id/reply' : '/tickets/$id/reply';
    final payload = <String, dynamic>{'body': body};
    if (!asClient && isInternal) payload['is_internal'] = true;
    final res = await _client.post(
      _u(path),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    await _decode(res);
  }

  Future<JscTicket> updateTicket(
    String id, {
    String? status,
    String? priority,
    String? assigneeId,
  }) async {
    final payload = <String, dynamic>{};
    if (status != null) payload['status'] = status;
    if (priority != null) payload['priority'] = priority;
    if (assigneeId != null) payload['assignee_id'] = assigneeId;
    final res = await _client.patch(
      _u('/tickets/$id'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    final body = await _decode(res) as Map<String, dynamic>;
    return JscTicket.fromJson((body['ticket'] as Map<String, dynamic>?) ?? const {});
  }

  // ── FCM token registration ─────────────────────────────────────────────

  Future<void> registerFcmToken(String token, {String platform = 'android'}) async {
    final res = await _client.post(
      _u('/fcm-tokens/register'),
      headers: _headers(),
      body: jsonEncode({'fcm_token': token, 'platform': platform}),
    );
    await _decode(res);
  }

  Future<void> unregisterFcmToken(String token) async {
    final res = await _client.post(
      _u('/fcm-tokens/unregister'),
      headers: _headers(),
      body: jsonEncode({'fcm_token': token}),
    );
    await _decode(res);
  }

  // ── Monitors ───────────────────────────────────────────────────────────

  Future<List<JscMonitor>> listMonitorsPublic() async {
    final res = await _client.get(_u('/monitors'), headers: _headers(needAuth: false));
    final body = await _decode(res) as Map<String, dynamic>;
    final list = (body['monitors'] as List?) ?? const [];
    return list.map((j) => JscMonitor.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<JscMonitor>> listMonitorsAdmin() async {
    final res = await _client.get(_u('/monitors/admin'), headers: _headers());
    final body = await _decode(res) as Map<String, dynamic>;
    final list = (body['monitors'] as List?) ?? const [];
    return list.map((j) => JscMonitor.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<JscMonitor>> listMyMonitors() async {
    final res = await _client.get(_u('/monitors/mine'), headers: _headers());
    final body = await _decode(res) as Map<String, dynamic>;
    final list = (body['monitors'] as List?) ?? const [];
    return list.map((j) => JscMonitor.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> pingMonitor(String id) async {
    final res = await _client.post(_u('/monitors/$id/ping'), headers: _headers());
    await _decode(res);
  }

  // ── Incidents ──────────────────────────────────────────────────────────

  Future<List<JscIncident>> listIncidents() async {
    final res = await _client.get(_u('/incidents'), headers: _headers(needAuth: false));
    final body = await _decode(res) as Map<String, dynamic>;
    final list = (body['incidents'] as List?) ?? const [];
    return list.map((j) => JscIncident.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<JscIncident> getIncident(String id) async {
    final res = await _client.get(_u('/incidents/$id'), headers: _headers(needAuth: false));
    final body = await _decode(res) as Map<String, dynamic>;
    return JscIncident.fromJson((body['incident'] as Map<String, dynamic>?) ?? const {});
  }

  Future<JscIncident> createIncident({
    required String title,
    required String severity,
    required String message,
    List<String> monitorIds = const [],
  }) async {
    final res = await _client.post(
      _u('/incidents'),
      headers: _headers(),
      body: jsonEncode({
        'title': title,
        'severity': severity,
        'message': message,
        if (monitorIds.isNotEmpty) 'monitor_ids': monitorIds,
      }),
    );
    final body = await _decode(res) as Map<String, dynamic>;
    return JscIncident.fromJson((body['incident'] as Map<String, dynamic>?) ?? const {});
  }

  Future<void> updateIncident(
    String id, {
    String? status,
    required String message,
  }) async {
    final res = await _client.post(
      _u('/incidents/$id/update'),
      headers: _headers(),
      body: jsonEncode({
        if (status != null) 'status': status,
        'message': message,
      }),
    );
    await _decode(res);
  }

  Future<void> deleteIncident(String id) async {
    final res = await _client.delete(_u('/incidents/$id'), headers: _headers());
    await _decode(res);
  }

  Future<void> dispose() async => _client.close();
}
