import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/zone.dart';
import '../services/cloudflare_api.dart';
import '../theme.dart';

class ZoneSettingsScreen extends StatefulWidget {
  final Zone zone;
  const ZoneSettingsScreen({super.key, required this.zone});

  @override
  State<ZoneSettingsScreen> createState() => _ZoneSettingsScreenState();
}

class _ZoneSettingsScreenState extends State<ZoneSettingsScreen> {
  bool? _devMode;
  bool _loading = true;
  bool _toggling = false;
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
      final enabled = await context.read<CloudflareApi>().getDevelopmentMode(widget.zone.id);
      setState(() => _devMode = enabled);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleDev(bool value) async {
    setState(() => _toggling = true);
    try {
      await context.read<CloudflareApi>().setDevelopmentMode(widget.zone.id, value);
      setState(() => _devMode = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _purge() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Purge entire cache?'),
        content: const Text(
          'This will purge all cached resources for this zone. The next visit to every URL will go to the origin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Purge', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await context.read<CloudflareApi>().purgeEverything(widget.zone.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache purged')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zone Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                  ],
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 0, 8),
                    child: Text('CACHE MANAGEMENT',
                        style: TextStyle(
                            letterSpacing: 1.2,
                            color: Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _devMode ?? false,
                          onChanged: _toggling ? null : (v) => _toggleDev(v),
                          title: const Text('Development Mode'),
                          subtitle: const Text('Temporarily bypass cache (3h)'),
                          activeColor: AppTheme.primary,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                          title: const Text('Purge Everything'),
                          subtitle: const Text('Clear all cached resources'),
                          onTap: _purge,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 0, 8),
                    child: Text('ZONE',
                        style: TextStyle(
                            letterSpacing: 1.2,
                            color: Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('Domain'),
                          subtitle: Text(widget.zone.name),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: const Text('Zone ID'),
                          subtitle: Text(widget.zone.id,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        ),
                        if (widget.zone.plan != null) ...[
                          const Divider(height: 1),
                          ListTile(
                            title: const Text('Plan'),
                            subtitle: Text(widget.zone.plan!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
