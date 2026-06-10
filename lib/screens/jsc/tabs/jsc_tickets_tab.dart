import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/jsc/jsc_ticket.dart';
import '../../../services/jsc/jsc_api.dart';
import '../../../services/jsc/jsc_auth_service.dart';
import '../../../theme.dart';
import '../jsc_ticket_detail_screen.dart';

class JscTicketsTab extends StatefulWidget {
  const JscTicketsTab({super.key});

  @override
  State<JscTicketsTab> createState() => _JscTicketsTabState();
}

class _JscTicketsTabState extends State<JscTicketsTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<JscTicket>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<JscTicket>> _fetch() {
    final auth = context.read<JscAuthService>();
    final api = JscApi(auth);
    final user = auth.user!;
    final f = user.isAdminOrAgent ? api.listAllTickets() : api.listMyTickets();
    return f.whenComplete(() => api.dispose());
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<JscTicket>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _errorView(snapshot.error!, _refresh);
          }
          final tickets = snapshot.data ?? [];
          if (tickets.isEmpty) {
            return _emptyView('No tickets', Icons.inbox);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tickets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final t = tickets[i];
              return Card(
                child: ListTile(
                  leading: _PriorityDot(priority: t.priority),
                  title: Text(t.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        t.requesterName.isNotEmpty ? t.requesterName : t.requesterEmail,
                        if (t.company != null && t.company!.isNotEmpty) t.company,
                      ].join(' · '),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                  trailing: _StatusChip(status: t.status),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => JscTicketDetailScreen(ticketId: t.id),
                    ));
                    _refresh();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Widget _emptyView(String text, IconData icon) {
  return ListView(children: [
    const SizedBox(height: 120),
    Icon(icon, size: 64, color: Colors.black26),
    const SizedBox(height: 12),
    Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
  ]);
}

Widget _errorView(Object err, VoidCallback onRetry) {
  return ListView(children: [
    const SizedBox(height: 80),
    Padding(
      padding: const EdgeInsets.all(24),
      child: Text(err.toString(),
          textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
    ),
    Center(child: ElevatedButton(onPressed: onRetry, child: const Text('Retry'))),
  ]);
}

class _PriorityDot extends StatelessWidget {
  final String priority;
  const _PriorityDot({required this.priority});

  Color get _color {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'low':
        return Colors.blueGrey;
      default:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    Color bg, fg;
    if (lower == 'closed' || lower == 'resolved') {
      bg = const Color(0xFFE0E0E0);
      fg = Colors.black54;
    } else if (lower == 'in_progress') {
      bg = const Color(0xFFFFE9C7);
      fg = const Color(0xFF8A5A00);
    } else {
      bg = AppTheme.active;
      fg = AppTheme.activeText;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }
}
