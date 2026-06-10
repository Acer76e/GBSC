import 'package:flutter/material.dart';

import '../../theme.dart';

class JscTab extends StatelessWidget {
  const JscTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Support Center',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.engineering, size: 80, color: AppTheme.primary),
          const SizedBox(height: 16),
          const Text(
            'JUICE Support Center',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Native port in progress',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Coming soon',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  _line('Dashboard with monitor health overview'),
                  _line('Tickets — admin, agent and client views'),
                  _line('Monitors — uptime checks, incident triggers'),
                  _line('Incidents — create, update, resolve'),
                  _line('Subscribers — public status notifications'),
                  _line('Agents & Clients management'),
                  _line('Push notifications via Firebase'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Waiting on backend source access to build against the real API contract.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _line(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6, right: 8),
              child: Icon(Icons.circle, size: 6, color: Colors.black45),
            ),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
