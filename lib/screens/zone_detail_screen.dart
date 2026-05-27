import 'package:flutter/material.dart';

import '../models/zone.dart';
import '../theme.dart';
import 'dns_records_screen.dart';
import 'ip_access_rules_screen.dart';
import 'zone_settings_screen.dart';

class ZoneDetailScreen extends StatelessWidget {
  final Zone zone;

  const ZoneDetailScreen({super.key, required this.zone});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(zone.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('DOMAIN INFORMATION'),
          Card(
            child: ListTile(
              title: const Text('Status', style: TextStyle(fontSize: 16)),
              trailing: StatusPill.fromStatus(zone.status),
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
                    builder: (_) => DnsRecordsScreen(zone: zone),
                  )),
                ),
                const Divider(height: 1),
                _MenuTile(
                  icon: Icons.shield_outlined,
                  label: 'IP Access Rules',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => IpAccessRulesScreen(zone: zone),
                  )),
                ),
                const Divider(height: 1),
                _MenuTile(
                  icon: Icons.tune,
                  label: 'Zone Settings',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ZoneSettingsScreen(zone: zone),
                  )),
                ),
              ],
            ),
          ),
        ],
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
