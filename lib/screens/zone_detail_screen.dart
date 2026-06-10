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
  ZoneRouteStatus? _status;
  bool _loading = true;
  bool _togglingMaintenance = false;
  bool _togglingSuspended = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await context.read<MaintenanceService>().getZoneRouteStatus(widget.zone.id);
      setState(() => _status = s);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showSkipped(String title, List<String> skipped) async {
    if (skipped.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(
          'These patterns are already attached to a different Worker on this zone, so they were skipped:\n\n${skipped.join("\n")}\n\nDisable the conflicting toggle first if you want this one to take over.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _toggleMaintenance(bool value) async {
    setState(() => _togglingMaintenance = true);
    try {
      final svc = context.read<MaintenanceService>();
      if (value) {
        final r = await svc.enableMaintenanceOn(widget.zone.id, widget.zone.name);
        await _showSkipped('Maintenance partially applied', r.skipped);
      } else {
        await svc.disableMaintenanceOn(widget.zone.id);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _togglingMaintenance = false);
    }
  }

  Future<void> _toggleSuspended(bool value) async {
    setState(() => _togglingSuspended = true);
    try {
      final svc = context.read<MaintenanceService>();
      if (value) {
        final r = await svc.suspend(widget.zone.id, widget.zone.name);
        await _showSkipped('Suspension partially applied', r.skipped);
      } else {
        await svc.unsuspend(widget.zone.id);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _togglingSuspended = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.zone.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
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
            _SectionLabel('PAGE OVERRIDE'),
            Card(
              child: Column(
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    ListTile(
                      title: const Text('Failed to load route status'),
                      subtitle:
                          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _load,
                      ),
                    )
                  else ...[
                    SwitchListTile(
                      value: s?.inMaintenance ?? false,
                      onChanged: _togglingMaintenance ? null : (v) => _toggleMaintenance(v),
                      title: const Text('Maintenance Mode'),
                      subtitle: Text(
                        (s?.inMaintenance ?? false)
                            ? 'Visitors see the maintenance page (503)'
                            : 'Site serves normally from origin',
                      ),
                      secondary: Icon(
                        Icons.construction,
                        color: (s?.inMaintenance ?? false) ? Colors.orange : Colors.black54,
                      ),
                      activeColor: Colors.orange,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: s?.suspended ?? false,
                      onChanged: _togglingSuspended ? null : (v) => _toggleSuspended(v),
                      title: const Text('Suspended'),
                      subtitle: Text(
                        (s?.suspended ?? false)
                            ? 'Visitors see the account-suspended page (402)'
                            : 'Site serves normally from origin',
                      ),
                      secondary: Icon(
                        Icons.gavel,
                        color: (s?.suspended ?? false) ? Colors.red : Colors.black54,
                      ),
                      activeColor: Colors.red,
                    ),
                    if (s != null && s.otherScripts.isNotEmpty)
                      Container(
                        color: const Color(0xFFFFF4D6),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber, color: Color(0xFF8A5A00)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Other worker(s) attached on this zone: ${s.otherScripts.join(", ")}. Conflicting route patterns will be skipped when toggling above.',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF8A5A00)),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
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
