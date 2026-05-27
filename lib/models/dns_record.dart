class DnsRecord {
  final String id;
  final String type;
  final String name;
  final String content;
  final int ttl;
  final bool proxied;
  final int? priority;

  DnsRecord({
    required this.id,
    required this.type,
    required this.name,
    required this.content,
    required this.ttl,
    required this.proxied,
    this.priority,
  });

  factory DnsRecord.fromJson(Map<String, dynamic> json) {
    return DnsRecord(
      id: json['id'] as String,
      type: json['type'] as String,
      name: json['name'] as String,
      content: (json['content'] as String?) ?? '',
      ttl: (json['ttl'] as int?) ?? 1,
      proxied: (json['proxied'] as bool?) ?? false,
      priority: json['priority'] as int?,
    );
  }

  Map<String, dynamic> toCreatePayload() {
    final m = <String, dynamic>{
      'type': type,
      'name': name,
      'content': content,
      'ttl': ttl,
      'proxied': proxied,
    };
    if (priority != null) m['priority'] = priority;
    return m;
  }
}
