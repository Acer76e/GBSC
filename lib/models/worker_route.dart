class WorkerRoute {
  final String id;
  final String pattern;
  final String? script;

  WorkerRoute({required this.id, required this.pattern, this.script});

  factory WorkerRoute.fromJson(Map<String, dynamic> json) {
    return WorkerRoute(
      id: json['id'] as String,
      pattern: json['pattern'] as String,
      script: json['script'] as String?,
    );
  }
}
