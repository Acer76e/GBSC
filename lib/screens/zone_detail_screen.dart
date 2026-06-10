import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/zone.dart';
import '../services/maintenance_service.dart';
import '../theme.dart';
import 'dns_records_screen.dart';
import 'ip_access_rules_screen.dart';
import 'zone_settings_screen.dart';

class ZoneDetailScreen extends StatefulWidget {
  final Zone zone;

  const ZoneDetailScreen({super.key, required this.zone});

  @override
  State<ZoneDetailScreen> createState() => _ZoneDetailScreenState();
}

class _ZoneDetailScreenState extends State<ZoneDetailScreen> {
  bool? _suspended;
  bool _conflict = false;
  String? _conflictScript;
  bool _loading = true;
  bool _toggling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSuspended();
  }

  Future<void> _loadSuspended() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await context.read<MaintenanceService>().getSuspendedStatus(widget.zone.id);
      setState(() {
        _suspended = s.suspended;
        _conflict = s.conflict;
        _conflictScript = s.conflictScript;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleSuspended(bool value) async {
    setState(() => _toggling = true);
    try {
      final svc = context.read<MaintenanceService>();
      if (value) {
        final r = await svc.suspend(widget.zone.id, widget.zone.name);
        if (r.skipped.isNotEmpty && mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Some routes skipped'),
              content: Text(
                'These patterns are already attached to a different Worker:\n\n${r.skipped.join("\n")}',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
              ],
            ),
          );
        }
      } else {
        await svc.unsuspend(widget.zone.id);
      }
      await _loadSuspended();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.zone.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSuspended,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionLabel('DOMAIN INFORMATION'),
            Card(
              child: ListTile(
                title: const Text('Status', style: TextStyle(fontSize: 16)),
                trailing: StatusPill.fromStatus(widget.zone.status),
              ),
            ),
            const SizedBox(height: 24),
            _SectionLabel('CLIENT STATE'),
            Card(
              child: Column(
                children: [
                  if (_loading)
                    const ListTile(
                      title: Text('Suspended'),
                      trailing: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_error != null)
                    ListTile(
                      title: const Text('Suspended'),
                      subtitle:
                          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loadSuspended,
                      ),
                    )
                  else
                    SwitchListTile(
                      value: _suspended ?? false,
                      onChanged: _toggling ? null : (v) => _toggleSuspended(v),
                      title: const Text('Suspended (402 page)'),
                      subtitle: Text(
                        (_suspended ?? false)
                            ? 'Visitors see the account-suspended page'
                            : 'Site serves normally from origin',
                      ),
                      activeColor: Colors.red,
                    ),
                  if (_conflict && !(_suspended ?? false))
                    Container(
                      color: const Color(0xFFFFF4D6),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, color: Color(0xFF8A5A00)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Routes on this zone are already attached to "${_conflictScript ?? "another worker"}". Enabling suspension will skip conflicting patterns.',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF8A5A00)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _SectionLabel('MANAGEMENT'),
            Card(
              child: Column(
                children: [
                  _MenuTile(
                    icon: Icons.list_alt_outlined,
                    label: 'DNS Records',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DnsRecordsScreen(zone: widget.zone),
                    )),
                  ),
                  const Divider(height: 1),
                  _MenuTile(
                    icon: Icons.shield_outlined,
                    label: 'IP Access Rules',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => IpAccessRulesScreen(zone: widget.zone),
                    )),
                  ),
                  const Divider(height: 1),
                  _MenuTile(
                    icon: Icons.tune,
                    label: 'Zone Settings',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ZoneSettingsScreen(zone: widget.zone),
                    )),
                  ),
                ],
              ),
            ),
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

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primary),
      title: Text(label, style: const TextStyle(fontSize: 16)),
      trailing: const Icon(Icons.chevron_right, color: Colors.black38),
      onTap: onTap,
    );
  }
}
