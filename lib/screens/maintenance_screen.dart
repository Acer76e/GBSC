import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/maintenance_config.dart';
import '../services/maintenance_service.dart';
import '../theme.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  late Future<MaintenanceOverview> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<MaintenanceOverview> _fetch() =>
      context.read<MaintenanceService>().getOverview();

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  Future<void> _enable() async {
    final confirm = await _confirm(
      title: 'Enable maintenance mode?',
      message:
          'This attaches Worker routes on every covered zone. Visitors will see the maintenance page (except IPs on the bypass list).',
      confirmLabel: 'Enable',
      destructive: true,
    );
    if (confirm != true) return;
    await _runToggle(() => context.read<MaintenanceService>().enableAll(), 'Enable');
  }

  Future<void> _disable() async {
    final confirm = await _confirm(
      title: 'Disable maintenance mode?',
      message: 'This removes the maintenance Worker routes from every zone in the account.',
      confirmLabel: 'Disable',
    );
    if (confirm != true) return;
    await _runToggle(() => context.read<MaintenanceService>().disableAll(), 'Disable');
  }

  Future<void> _runToggle(Future<ToggleResult> Function() op, String verb) async {
    setState(() => _busy = true);
    try {
      final result = await op();
      if (!mounted) return;
      final lines = <String>[];
      if (result.succeeded.isNotEmpty) {
        lines.add('${result.succeeded.length} zone(s) updated.');
      }
      if (result.skipped.isNotEmpty) {
        lines.add('${result.skipped.length} skipped (conflict).');
      }
      if (result.failed.isNotEmpty) {
        lines.add('${result.failed.length} failed.');
      }
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('$verb result'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(lines.join('\n')),
                if (result.skipped.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Skipped:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final s in result.skipped) Text('• $s'),
                ],
                if (result.failed.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Failed:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  for (final f in result.failed) Text('• ${f.domain}: ${f.message}'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmLabel,
              style: TextStyle(color: destructive ? Colors.red : AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editText({
    required String title,
    required String initial,
    required String hint,
    required Future<void> Function(String) onSave,
  }) async {
    final ctrl = TextEditingController(text: initial);
    bool busy = false;
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: InputDecoration(hintText: hint),
                maxLines: title.contains('IP') ? 4 : 1,
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        await onSave(ctrl.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setLocal(() {
                          err = e.toString();
                          busy = false;
                        });
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance Mode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Configuration',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const MaintenanceConfigScreen(),
            )),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<MaintenanceOverview>(
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
                  child: Text(snapshot.error.toString(), textAlign: TextAlign.center),
                ),
              ]);
            }
            final o = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusCard(overview: o, busy: _busy, onEnable: _enable, onDisable: _disable),
                const SizedBox(height: 20),
                const _SectionLabel('MAINTENANCE PAGE'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Bypass IPs'),
                        subtitle: Text(
                          o.bypassIpsRaw == null || o.bypassIpsRaw!.isEmpty
                              ? 'None'
                              : '${o.bypassIps.length} IP(s): ${o.bypassIps.join(', ')}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editText(
                          title: 'Bypass IPs',
                          initial: o.bypassIpsRaw ?? '',
                          hint: 'Comma-separated, e.g. 1.2.3.4, 5.6.7.8',
                          onSave: (v) async {
                            final svc = context.read<MaintenanceService>();
                            await svc.setBypassIps(v.split(','));
                            await _refresh();
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Updates URL'),
                        subtitle: Text(
                          o.updatesUrl == null || o.updatesUrl!.isEmpty
                              ? 'Not set'
                              : o.updatesUrl!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editText(
                          title: 'Updates URL',
                          initial: o.updatesUrl ?? '',
                          hint: 'https://status.example.com',
                          onSave: (v) async {
                            final svc = context.read<MaintenanceService>();
                            await svc.setUpdatesUrl(v);
                            await _refresh();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionLabel('COVERED ZONES'),
                Card(
                  child: Column(
                    children: [
                      for (final s in o.perZone)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            s.zone == null
                                ? Icons.error_outline
                                : (s.hasMaintenanceRoutes
                                    ? Icons.cloud_off
                                    : Icons.cloud_done_outlined),
                            color: s.zone == null
                                ? Colors.redAccent
                                : (s.hasMaintenanceRoutes
                                    ? Colors.orange
                                    : Colors.green),
                          ),
                          title: Text(s.domain),
                          subtitle: s.error != null
                              ? Text(s.error!, style: const TextStyle(color: Colors.red))
                              : Text(s.hasMaintenanceRoutes ? 'Maintenance attached' : 'Normal'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
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
      child: Text(
        text,
        style: const TextStyle(
          letterSpacing: 1.2,
          color: Colors.black54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final MaintenanceOverview overview;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onDisable;

  const _StatusCard({
    required this.overview,
    required this.busy,
    required this.onEnable,
    required this.onDisable,
  });

  @override
  Widget build(BuildContext context) {
    final state = overview.state;
    Color color;
    String label;
    String detail;
    switch (state) {
      case MaintenanceState.on:
        color = Colors.red;
        label = 'ON';
        detail = '${overview.coveredCount} of ${overview.totalResolved} zones in maintenance';
        break;
      case MaintenanceState.partial:
        color = Colors.orange;
        label = 'PARTIAL';
        detail = '${overview.coveredCount} of ${overview.totalResolved} zones in maintenance';
        break;
      case MaintenanceState.off:
        color = Colors.green;
        label = 'OFF';
        detail = 'All ${overview.totalResolved} covered zones serving normally';
        break;
      case MaintenanceState.unknown:
        color = Colors.grey;
        label = 'UNKNOWN';
        detail = 'No covered zones resolved';
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            Text(detail, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: busy || state == MaintenanceState.on ? null : onEnable,
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Enable all'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy || state == MaintenanceState.off ? null : onDisable,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Disable all'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MaintenanceConfigScreen extends StatefulWidget {
  const MaintenanceConfigScreen({super.key});

  @override
  State<MaintenanceConfigScreen> createState() => _MaintenanceConfigScreenState();
}

class _MaintenanceConfigScreenState extends State<MaintenanceConfigScreen> {
  Future<void> _editField({
    required String title,
    required String initial,
    required Future<void> Function(String) onSave,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) await onSave(ctrl.text);
    ctrl.dispose();
  }

  Future<void> _addZone() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add covered zone'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'example.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await context.read<MaintenanceConfig>().addCoveredZone(ctrl.text);
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<MaintenanceConfig>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'reset') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Reset to defaults?'),
                    content: const Text('Restores account ID, KV namespace, script names and the original 17-zone list.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Reset', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) await config.resetToDefaults();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reset', child: Text('Reset to defaults')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionLabel('ACCOUNT'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Account ID'),
                  subtitle: Text(config.accountId,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editField(
                    title: 'Account ID',
                    initial: config.accountId,
                    onSave: config.setAccountId,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('KV Namespace ID'),
                  subtitle: Text(config.kvNamespaceId,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editField(
                    title: 'KV Namespace ID',
                    initial: config.kvNamespaceId,
                    onSave: config.setKvNamespaceId,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('WORKER SCRIPTS'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Maintenance script'),
                  subtitle: Text(config.maintenanceScript),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editField(
                    title: 'Maintenance script name',
                    initial: config.maintenanceScript,
                    onSave: config.setMaintenanceScript,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Suspended script'),
                  subtitle: Text(config.suspendedScript),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editField(
                    title: 'Suspended script name',
                    initial: config.suspendedScript,
                    onSave: config.setSuspendedScript,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: _SectionLabel('COVERED ZONES')),
              TextButton.icon(
                onPressed: _addZone,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          Card(
            child: Column(
              children: [
                for (final z in config.coveredZones)
                  ListTile(
                    leading: const Icon(Icons.public, color: AppTheme.primary),
                    title: Text(z),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                      onPressed: () => config.removeCoveredZone(z),
                    ),
                  ),
                if (config.coveredZones.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No covered zones. Tap Add.',
                        style: TextStyle(color: Colors.black54)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
