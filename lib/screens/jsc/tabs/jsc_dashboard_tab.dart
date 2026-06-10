import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/jsc/jsc_monitor.dart';
import '../../../models/jsc/jsc_ticket.dart';
import '../../../services/jsc/jsc_api.dart';
import '../../../services/jsc/jsc_auth_service.dart';
import '../../../theme.dart';

class _DashSnapshot {
  final List<JscTicket> tickets;
  final List<JscMonitor> monitors;
  final List<JscIncident> incidents;
  _DashSnapshot(this.tickets, this.monitors, this.incidents);
}

class JscDashboardTab extends StatefulWidget {
  const JscDashboardTab({super.key});

  @override
  State<JscDashboardTab> createState() => _JscDashboardTabState();
}

class _JscDashboardTabState extends State<JscDashboardTab>
    with AutomaticKeepAliveClientMixin {
  late Future<_DashSnapshot> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_DashSnapshot> _fetch() async {
    final api = JscApi(context.read<JscAuthService>());
    try {
      final results = await Future.wait([
        api.listAllTickets(),
        api.listMonitorsAdmin(),
        api.listIncidents(),
      ]);
      return _DashSnapshot(
        results[0] as List<JscTicket>,
        results[1] as List<JscMonitor>,
        results[2] as List<JscIncident>,
      );
    } finally {
      await api.dispose();
    }
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
      child: FutureBuilder<_DashSnapshot>(
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
                child: Text(snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
              ),
            ]);
          }
          final d = snapshot.data!;
          final openTickets = d.tickets.where((t) => t.status != 'closed' && t.status != 'resolved').toList();
          final urgentTickets = openTickets.where((t) => t.priority == 'urgent' || t.priority == 'high').length;
          final downMonitors = d.monitors.where((m) => m.status == 'outage').toList();
          final degradedMonitors = d.monitors.where((m) => m.status == 'degraded').toList();
          final openIncidents = d.incidents.where((i) => !i.isResolved).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _StatTile(label: 'Open tickets', value: '${openTickets.length}', accent: AppTheme.primary, icon: Icons.confirmation_number_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatTile(label: 'Urgent/high', value: '$urgentTickets', accent: Colors.orange, icon: Icons.priority_high)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _StatTile(label: 'Monitors down', value: '${downMonitors.length}', accent: Colors.red, icon: Icons.cloud_off)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatTile(label: 'Open incidents', value: '${openIncidents.length}', accent: Colors.red, icon: Icons.bolt)),
                ],
              ),
              const SizedBox(height: 24),
              if (downMonitors.isNotEmpty || degradedMonitors.isNotEmpty) ...[
                const _SectionLabel('NEEDS ATTENTION'),
                Card(
                  child: Column(
                    children: [
                      for (int i = 0; i < downMonitors.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.cancel, color: Colors.red),
                          title: Text(downMonitors[i].name),
                          subtitle: const Text('Outage', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                      for (final m in degradedMonitors) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.warning_amber, color: Colors.orange),
                          title: Text(m.name),
                          subtitle: Text('Degraded — ${m.responseTime}ms',
                              style: const TextStyle(color: Colors.orange)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (openIncidents.isNotEmpty) ...[
                const _SectionLabel('OPEN INCIDENTS'),
                Card(
                  child: Column(
                    children: [
                      for (int i = 0; i < openIncidents.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            openIncidents[i].severity == 'critical' ? Icons.error : Icons.warning_amber,
                            color: openIncidents[i].severity == 'critical' ? Colors.red : Colors.orange,
                          ),
                          title: Text(openIncidents[i].title),
                          subtitle: Text(openIncidents[i].status.replaceAll('_', ' ')),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (downMonitors.isEmpty && openIncidents.isEmpty) ...[
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 48),
                      const SizedBox(height: 8),
                      Text('All systems operational',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final IconData icon;
  const _StatTile({
    required this.label,
    required this.value,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold, color: accent)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(text,
          style: const TextStyle(
              letterSpacing: 1.2,
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}
