import 'dart:convert';

import 'package:http/http.dart' as http;

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

  Future<void> dispose() async => _client.close();
}
