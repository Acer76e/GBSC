import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionLabel('ACCOUNT'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.key_outlined, color: AppTheme.primary),
              title: Text(auth.credentials?.displayLabel ?? '—'),
              subtitle: Text(
                auth.credentials?.mode == AuthMode.apiToken ? 'API Token' : 'Global API Key',
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionLabel('INFORMATION'),
          Card(
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.info_outline, color: AppTheme.primary),
                  title: Text('API Documentation'),
                  subtitle: Text('developers.cloudflare.com/api'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.help_outline, color: AppTheme.primary),
                  title: Text('About'),
                  subtitle: Text('Cloudflare Mobile · v0.1.0'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text('Your credentials will be removed from this device.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await context.read<AuthService>().signOut();
                  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
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
