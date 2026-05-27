class Zone {
  final String id;
  final String name;
  final String status;
  final bool paused;
  final String? plan;
  final bool developmentMode;

  Zone({
    required this.id,
    required this.name,
    required this.status,
    required this.paused,
    this.plan,
    this.developmentMode = false,
  });

  factory Zone.fromJson(Map<String, dynamic> json) {
    final planMap = json['plan'];
    return Zone(
      id: json['id'] as String,
      name: json['name'] as String,
      status: (json['status'] as String?) ?? 'unknown',
      paused: (json['paused'] as bool?) ?? false,
      plan: planMap is Map<String, dynamic> ? planMap['name'] as String? : null,
      developmentMode: ((json['development_mode'] as num?) ?? 0) > 0,
    );
  }
}
