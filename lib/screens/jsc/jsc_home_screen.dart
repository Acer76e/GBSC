import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/jsc/jsc_ticket.dart';
import '../../services/jsc/jsc_api.dart';
import '../../services/jsc/jsc_auth_service.dart';
import '../../theme.dart';

class JscHomeScreen extends StatefulWidget {
  const JscHomeScreen({super.key});

  @override
  State<JscHomeScreen> createState() => _JscHomeScreenState();
}

class _JscHomeScreenState extends State<JscHomeScreen> {
  late Future<List<JscTicket>> _future;

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

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out of JSC?'),
        content: const Text('Your JSC credentials will be removed from this device. Cloudflare session is unaffected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<JscAuthService>().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<JscAuthService>();
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user.isAdminOrAgent ? 'All Tickets' : 'My Tickets',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              user.name.isNotEmpty ? user.name : user.email,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primary),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<JscTicket>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                Center(
                  child: ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
                ),
              ]);
            }
            final tickets = snapshot.data ?? [];
            if (tickets.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Icon(Icons.inbox, size: 64, color: Colors.black26),
                SizedBox(height: 12),
                Text(
                  'No tickets',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ]);
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
                    title: Text(
                      t.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
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
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ticket detail coming next')),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
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
