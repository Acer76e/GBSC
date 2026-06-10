import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/jsc/jsc_monitor.dart';
import '../../../services/jsc/jsc_api.dart';
import '../../../services/jsc/jsc_auth_service.dart';
import '../../../theme.dart';
import '../jsc_incident_detail_screen.dart';

class JscIncidentsTab extends StatefulWidget {
  const JscIncidentsTab({super.key});

  @override
  State<JscIncidentsTab> createState() => _JscIncidentsTabState();
}

class _JscIncidentsTabState extends State<JscIncidentsTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<JscIncident>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<JscIncident>> _fetch() {
    final api = JscApi(context.read<JscAuthService>());
    return api.listIncidents().whenComplete(api.dispose);
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  Future<void> _newIncident() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _NewIncidentScreen()),
    );
    if (created == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = context.watch<JscAuthService>().user!;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<JscIncident>>(
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
            final incidents = snapshot.data ?? [];
            if (incidents.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Icon(Icons.check_circle, size: 64, color: Colors.green),
                SizedBox(height: 12),
                Text('No incidents in the last 90 days',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: incidents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final inc = incidents[i];
                return Card(
                  child: ListTile(
                    leading: _SeverityBadge(severity: inc.severity),
                    title: Text(inc.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [
                          inc.status.replaceAll('_', ' '),
                          if (inc.affectedMonitors.isNotEmpty)
                            inc.affectedMonitors.map((m) => m.name).join(', '),
                          if (inc.createdAt != null) _ago(inc.createdAt!),
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(color: Colors.black54),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.black38),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => JscIncidentDetailScreen(incidentId: inc.id),
                      ));
                      _refresh();
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: user.isAdminOrAgent
          ? FloatingActionButton(
              onPressed: _newIncident,
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  String _ago(DateTime dt) {
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _SeverityBadge extends StatelessWidget {
  final String severity;
  const _SeverityBadge({required this.severity});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    switch (severity.toLowerCase()) {
      case 'critical':
        color = Colors.red;
        icon = Icons.error;
        break;
      case 'warning':
        color = Colors.orange;
        icon = Icons.warning_amber;
        break;
      default:
        color = Colors.blue;
        icon = Icons.info_outline;
    }
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _NewIncidentScreen extends StatefulWidget {
  const _NewIncidentScreen();

  @override
  State<_NewIncidentScreen> createState() => _NewIncidentScreenState();
}

class _NewIncidentScreenState extends State<_NewIncidentScreen> {
  final _title = TextEditingController();
  final _message = TextEditingController();
  String _severity = 'warning';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _message.text.trim().isEmpty) {
      setState(() => _error = 'Title and message are required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = JscApi(context.read<JscAuthService>());
    try {
      await api.createIncident(
        title: _title.text.trim(),
        severity: _severity,
        message: _message.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      await api.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Incident')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _severity,
            decoration: const InputDecoration(labelText: 'Severity'),
            items: const [
              DropdownMenuItem(value: 'critical', child: Text('Critical')),
              DropdownMenuItem(value: 'warning', child: Text('Warning')),
              DropdownMenuItem(value: 'info', child: Text('Info')),
            ],
            onChanged: (v) => setState(() => _severity = v ?? 'warning'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            decoration: const InputDecoration(
              labelText: 'First update message',
              hintText: 'What happened? What\'s the current status?',
            ),
            maxLines: 6,
            minLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Create incident'),
          ),
        ],
      ),
    );
  }
}
