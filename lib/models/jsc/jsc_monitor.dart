class JscMonitor {
  final String id;
  final String name;
  final String? category;
  final String status; // operational / degraded / outage
  final double uptime30d;
  final int responseTime;
  final DateTime? lastChecked;

  JscMonitor({
    required this.id,
    required this.name,
    this.category,
    required this.status,
    this.uptime30d = 100,
    this.responseTime = 0,
    this.lastChecked,
  });

  factory JscMonitor.fromJson(Map<String, dynamic> j) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return JscMonitor(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      category: j['category']?.toString(),
      status: (j['status'] ?? 'operational').toString(),
      uptime30d: (j['uptime_30d'] is num) ? (j['uptime_30d'] as num).toDouble() : 100,
      responseTime:
          (j['response_time'] is num) ? (j['response_time'] as num).toInt() : 0,
      lastChecked: parse(j['last_checked']),
    );
  }
}

class JscIncidentUpdate {
  final String id;
  final String message;
  final String? author;
  final DateTime? createdAt;

  JscIncidentUpdate({
    required this.id,
    required this.message,
    this.author,
    this.createdAt,
  });

  factory JscIncidentUpdate.fromJson(Map<String, dynamic> j) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return JscIncidentUpdate(
      id: (j['id'] ?? '').toString(),
      message: (j['message'] ?? '').toString(),
      author: j['author']?.toString(),
      createdAt: parse(j['created_at']),
    );
  }
}

class JscIncident {
  final String id;
  final String title;
  final String severity; // critical / warning / info
  final String status; // investigating / identified / monitoring / resolved
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final List<JscIncidentUpdate> updates;
  final List<({String id, String name})> affectedMonitors;

  JscIncident({
    required this.id,
    required this.title,
    required this.severity,
    required this.status,
    this.createdAt,
    this.resolvedAt,
    this.updates = const [],
    this.affectedMonitors = const [],
  });

  factory JscIncident.fromJson(Map<String, dynamic> j) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    final upsRaw = (j['updates'] as List?) ?? const [];
    final mons = (j['affectedMonitors'] as List?) ?? const [];

    return JscIncident(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '(untitled)').toString(),
      severity: (j['severity'] ?? 'warning').toString(),
      status: (j['status'] ?? 'investigating').toString(),
      createdAt: parse(j['created_at']),
      resolvedAt: parse(j['resolved_at']),
      updates: upsRaw
          .map((u) => JscIncidentUpdate.fromJson(u as Map<String, dynamic>))
          .toList(),
      affectedMonitors: mons.map((m) {
        final mm = m as Map<String, dynamic>;
        return (id: (mm['id'] ?? '').toString(), name: (mm['name'] ?? '').toString());
      }).toList(),
    );
  }

  bool get isResolved => status == 'resolved';
}
