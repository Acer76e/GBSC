import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/jsc/jsc_monitor.dart';
import '../../../services/jsc/jsc_api.dart';
import '../../../services/jsc/jsc_auth_service.dart';
import '../../../theme.dart';

class JscMonitorsTab extends StatefulWidget {
  const JscMonitorsTab({super.key});

  @override
  State<JscMonitorsTab> createState() => _JscMonitorsTabState();
}

class _JscMonitorsTabState extends State<JscMonitorsTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<JscMonitor>> _future;
  final Set<String> _pinging = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<JscMonitor>> _fetch() {
    final auth = context.read<JscAuthService>();
    final api = JscApi(auth);
    final user = auth.user!;
    final f = user.isAdminOrAgent
        ? api.listMonitorsAdmin()
        : (user.isClient ? api.listMyMonitors() : api.listMonitorsPublic());
    return f.whenComplete(api.dispose);
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  Future<void> _ping(JscMonitor m) async {
    setState(() => _pinging.add(m.id));
    final api = JscApi(context.read<JscAuthService>());
    try {
      await api.pingMonitor(m.id);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      await api.dispose();
      if (mounted) setState(() => _pinging.remove(m.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = context.watch<JscAuthService>().user!;
    final isAdmin = user.isAdminOrAgent;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<JscMonitor>>(
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
          final monitors = snapshot.data ?? [];
          if (monitors.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 120),
              Icon(Icons.monitor_heart_outlined, size: 64, color: Colors.black26),
              SizedBox(height: 12),
              Text('No monitors',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
            ]);
          }

          // Group by category
          final grouped = <String, List<JscMonitor>>{};
          for (final m in monitors) {
            grouped.putIfAbsent(m.category ?? 'Other', () => []).add(m);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      letterSpacing: 1.2,
                      color: Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      for (int i = 0; i < entry.value.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _MonitorTile(
                          monitor: entry.value[i],
                          canPing: isAdmin,
                          pinging: _pinging.contains(entry.value[i].id),
                          onPing: () => _ping(entry.value[i]),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MonitorTile extends StatelessWidget {
  final JscMonitor monitor;
  final bool canPing;
  final bool pinging;
  final VoidCallback onPing;

  const _MonitorTile({
    required this.monitor,
    required this.canPing,
    required this.pinging,
    required this.onPing,
  });

  Color get _statusColor {
    switch (monitor.status) {
      case 'operational':
        return Colors.green;
      case 'degraded':
        return Colors.orange;
      case 'outage':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData get _statusIcon {
    switch (monitor.status) {
      case 'operational':
        return Icons.check_circle;
      case 'degraded':
        return Icons.warning_amber;
      case 'outage':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_statusIcon, color: _statusColor, size: 28),
      title: Text(monitor.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${monitor.uptime30d.toStringAsFixed(2)}% • ${monitor.responseTime}ms${_lastCheckedText()}',
          style: const TextStyle(color: Colors.black54),
        ),
      ),
      trailing: canPing
          ? IconButton(
              icon: pinging
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.replay, color: AppTheme.primary),
              tooltip: 'Force check now',
              onPressed: pinging ? null : onPing,
            )
          : null,
    );
  }

  String _lastCheckedText() {
    if (monitor.lastChecked == null) return '';
    final diff = DateTime.now().toUtc().difference(monitor.lastChecked!.toUtc());
    if (diff.inMinutes < 1) return ' • just now';
    if (diff.inMinutes < 60) return ' • ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return ' • ${diff.inHours}h ago';
    return ' • ${diff.inDays}d ago';
  }
}
