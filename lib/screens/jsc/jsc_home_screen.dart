import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/jsc/jsc_auth_service.dart';
import '../../theme.dart';
import 'tabs/jsc_dashboard_tab.dart';
import 'tabs/jsc_incidents_tab.dart';
import 'tabs/jsc_monitors_tab.dart';
import 'tabs/jsc_tickets_tab.dart';

class JscHomeScreen extends StatelessWidget {
  const JscHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<JscAuthService>();
    final user = auth.user;
    if (user == null) return const SizedBox.shrink();

    final isAdmin = user.isAdminOrAgent;
    final tabs = <Tab>[
      if (isAdmin) const Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
      const Tab(icon: Icon(Icons.confirmation_number_outlined), text: 'Tickets'),
      const Tab(icon: Icon(Icons.monitor_heart_outlined), text: 'Monitors'),
      const Tab(icon: Icon(Icons.bolt_outlined), text: 'Incidents'),
    ];
    final views = <Widget>[
      if (isAdmin) const JscDashboardTab(),
      const JscTicketsTab(),
      const JscMonitorsTab(),
      const JscIncidentsTab(),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'JUICE Support',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                '${user.name.isNotEmpty ? user.name : user.email} · ${user.role}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              tooltip: 'Sign out',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Sign out of JSC?'),
                    content: const Text(
                        'Your JSC credentials will be removed from this device. Cloudflare session is unaffected.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Sign out',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await context.read<JscAuthService>().signOut();
                }
              },
            ),
          ],
          bottom: TabBar(
            tabs: tabs,
            isScrollable: tabs.length > 3,
            labelColor: AppTheme.primary,
            unselectedLabelColor: Colors.black54,
            indicatorColor: AppTheme.primary,
          ),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}
