class JscTicket {
  final String id;
  final String subject;
  final String status; // open / in_progress / closed / etc.
  final String priority; // low / medium / high / urgent
  final String? category;
  final String requesterName;
  final String requesterEmail;
  final String? company;
  final String? assigneeName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  JscTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.priority,
    this.category,
    required this.requesterName,
    required this.requesterEmail,
    this.company,
    this.assigneeName,
    this.createdAt,
    this.updatedAt,
  });

  factory JscTicket.fromJson(Map<String, dynamic> j) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return JscTicket(
      id: (j['id'] ?? '').toString(),
      subject: (j['subject'] ?? '(no subject)').toString(),
      status: (j['status'] ?? 'open').toString(),
      priority: (j['priority'] ?? 'medium').toString(),
      category: j['category']?.toString(),
      requesterName: (j['requester_name'] ?? '').toString(),
      requesterEmail: (j['requester_email'] ?? '').toString(),
      company: j['company']?.toString(),
      assigneeName: j['assignee_name']?.toString(),
      createdAt: parse(j['created_at']),
      updatedAt: parse(j['updated_at']),
    );
  }
}

class JscTicketMessage {
  final String id;
  final String ticketId;
  final String? fromName;
  final String? fromEmail;
  final String body;
  final bool isInternal;
  final DateTime? createdAt;

  JscTicketMessage({
    required this.id,
    required this.ticketId,
    this.fromName,
    this.fromEmail,
    required this.body,
    this.isInternal = false,
    this.createdAt,
  });

  factory JscTicketMessage.fromJson(Map<String, dynamic> j) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return JscTicketMessage(
      id: (j['id'] ?? '').toString(),
      ticketId: (j['ticket_id'] ?? '').toString(),
      fromName: j['from_name']?.toString(),
      fromEmail: j['from_email']?.toString(),
      body: (j['body'] ?? '').toString(),
      isInternal: (j['is_internal'] ?? 0).toString() != '0',
      createdAt: parse(j['created_at']),
    );
  }
}
