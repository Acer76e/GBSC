import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/jsc/jsc_monitor.dart';
import '../../services/jsc/jsc_api.dart';
import '../../services/jsc/jsc_auth_service.dart';
import '../../theme.dart';

class JscIncidentDetailScreen extends StatefulWidget {
  final String incidentId;
  const JscIncidentDetailScreen({super.key, required this.incidentId});

  @override
  State<JscIncidentDetailScreen> createState() => _JscIncidentDetailScreenState();
}

class _JscIncidentDetailScreenState extends State<JscIncidentDetailScreen> {
  late Future<JscIncident> _future;
  final _update = TextEditingController();
  String? _status;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void dispose() {
    _update.dispose();
    super.dispose();
  }

  Future<JscIncident> _fetch() {
    final api = JscApi(context.read<JscAuthService>());
    return api.getIncident(widget.incidentId).whenComplete(api.dispose);
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  Future<void> _post() async {
    if (_update.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final api = JscApi(context.read<JscAuthService>());
    try {
      await api.updateIncident(
        widget.incidentId,
        status: _status,
        message: _update.text.trim(),
      );
      _update.clear();
      _status = null;
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      await api.dispose();
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.read<JscAuthService>().user?.isAdminOrAgent ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<JscIncident>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }
          final inc = snapshot.data!;
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(inc.title,
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  _chip(inc.severity, _sevBg(inc.severity), _sevFg(inc.severity)),
                                  _chip(inc.status.replaceAll('_', ' '),
                                      inc.isResolved ? const Color(0xFFE0E0E0) : AppTheme.active,
                                      inc.isResolved ? Colors.black54 : AppTheme.activeText),
                                ],
                              ),
                              if (inc.affectedMonitors.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('Affecting: ${inc.affectedMonitors.map((m) => m.name).join(", ")}',
                                    style: const TextStyle(color: Colors.black54, fontSize: 13)),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 0, 0, 8),
                        child: Text('TIMELINE',
                            style: TextStyle(
                                letterSpacing: 1.2,
                                color: Colors.black54,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                      for (final u in inc.updates.reversed) _UpdateCard(update: u),
                      if (inc.updates.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text('No updates yet',
                                style: TextStyle(color: Colors.black54)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (isAdmin)
                _AdminComposer(
                  controller: _update,
                  status: _status,
                  onStatusChanged: (s) => setState(() => _status = s),
                  sending: _sending,
                  onSend: _post,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 11)),
    );
  }

  Color _sevBg(String sev) {
    switch (sev.toLowerCase()) {
      case 'critical':
        return const Color(0xFFFCD9D6);
      case 'warning':
        return const Color(0xFFFFE9C7);
      default:
        return const Color(0xFFE3F2FD);
    }
  }

  Color _sevFg(String sev) {
    switch (sev.toLowerCase()) {
      case 'critical':
        return const Color(0xFFB00020);
      case 'warning':
        return const Color(0xFF8A5A00);
      default:
        return const Color(0xFF0B5FBE);
    }
  }
}

class _UpdateCard extends StatelessWidget {
  final JscIncidentUpdate update;
  const _UpdateCard({required this.update});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(update.author ?? '—',
                    style:
                        const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                if (update.createdAt != null)
                  Text(_fmt(update.createdAt!),
                      style: const TextStyle(color: Colors.black54, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 6),
            Text(update.message),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${_p(l.month)}-${_p(l.day)} ${_p(l.hour)}:${_p(l.minute)}';
  }

  String _p(int v) => v.toString().padLeft(2, '0');
}

class _AdminComposer extends StatelessWidget {
  final TextEditingController controller;
  final String? status;
  final ValueChanged<String?> onStatusChanged;
  final bool sending;
  final VoidCallback onSend;

  const _AdminComposer({
    required this.controller,
    required this.status,
    required this.onStatusChanged,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE3DCEF))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Set status: ', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: DropdownButton<String?>(
                    value: status,
                    isExpanded: true,
                    hint: const Text('(no change)'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('(no change)')),
                      DropdownMenuItem(value: 'investigating', child: Text('Investigating')),
                      DropdownMenuItem(value: 'identified', child: Text('Identified')),
                      DropdownMenuItem(value: 'monitoring', child: Text('Monitoring')),
                      DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                    ],
                    onChanged: onStatusChanged,
                  ),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLines: 5,
                    minLines: 1,
                    decoration: const InputDecoration(
                      hintText: 'Post an update…',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sending ? null : onSend,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
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
