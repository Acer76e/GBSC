class JscUser {
  final String id;
  final String email;
  final String name;
  final String role; // 'admin' | 'agent' | 'client'
  final String type; // 'admin' | 'client'
  final String? clientId;
  final String? company;

  JscUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.type,
    this.clientId,
    this.company,
  });

  factory JscUser.fromJson(Map<String, dynamic> json) {
    return JscUser(
      id: (json['id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      role: (json['role'] ?? 'client').toString(),
      type: (json['type'] ?? (json['role'] == 'client' ? 'client' : 'admin')).toString(),
      clientId: json['clientId']?.toString(),
      company: json['company']?.toString(),
    );
  }

  bool get isAdminOrAgent => role == 'admin' || role == 'agent';
  bool get isClient => role == 'client';
}
