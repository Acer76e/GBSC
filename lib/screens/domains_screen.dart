import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/zone.dart';
import '../services/auth_service.dart';
import '../services/cloudflare_api.dart';
import '../theme.dart';
import 'maintenance_screen.dart';
import 'settings_screen.dart';
import 'zone_detail_screen.dart';

class DomainsScreen extends StatefulWidget {
  const DomainsScreen({super.key});

  @override
  State<DomainsScreen> createState() => _DomainsScreenState();
}

class _DomainsScreenState extends State<DomainsScreen> {
  late Future<List<Zone>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Zone>> _fetch() => context.read<CloudflareApi>().listZones();

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: AppTheme.primary),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Domains',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  if (auth.credentials != null)
                    Text(
                      auth.credentials!.displayLabel,
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primary),
            tooltip: 'Open Cloudflare dashboard',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add zones in the Cloudflare dashboard')),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const _MaintenanceShortcut(),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search domains',
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Zone>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _ErrorView(
                        error: snapshot.error!,
                        onRetry: _refresh,
                      );
                    }
                    final all = snapshot.data ?? const [];
                    final zones = _query.isEmpty
                        ? all
                        : all.where((z) => z.name.toLowerCase().contains(_query)).toList();
                    if (zones.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 120),
                          Icon(Icons.public_off, size: 64, color: Colors.black26),
                          SizedBox(height: 12),
                          Text(
                            'No domains found',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      );
                    }
                    return ListView.separated(
                      itemCount: zones.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final z = zones[i];
                        return ListTile(
                          tileColor: Colors.white,
                          shape: i == 0
                              ? const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                                )
                              : i == zones.length - 1
                                  ? const RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.vertical(bottom: Radius.circular(12)),
                                    )
                                  : null,
                          leading: const Icon(Icons.public, color: AppTheme.primary),
                          title: Text(z.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500, fontSize: 16)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StatusPill.fromStatus(z.status),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, color: Colors.black38),
                            ],
                          ),
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ZoneDetailScreen(zone: z),
                            ));
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}

class _MaintenanceShortcut extends StatelessWidget {
  const _MaintenanceShortcut();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.construction, color: AppTheme.primary),
        title: const Text('Maintenance Mode',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Toggle global maintenance page across covered zones'),
        trailing: const Icon(Icons.chevron_right, color: Colors.black38),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MaintenanceScreen()),
        ),
      ),
    );
  }
}
