import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/jsc/jsc_ticket.dart';
import '../../services/jsc/jsc_api.dart';
import '../../services/jsc/jsc_auth_service.dart';
import '../../theme.dart';

class JscTicketDetailScreen extends StatefulWidget {
  final String ticketId;
  const JscTicketDetailScreen({super.key, required this.ticketId});

  @override
  State<JscTicketDetailScreen> createState() => _JscTicketDetailScreenState();
}

class _JscTicketDetailScreenState extends State<JscTicketDetailScreen> {
  late Future<({JscTicket ticket, List<JscTicketMessage> messages})> _future;
  final _reply = TextEditingController();
  bool _internal = false;
  bool _sending = false;

  bool get _asClient => context.read<JscAuthService>().user?.isClient ?? false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<({JscTicket ticket, List<JscTicketMessage> messages})> _fetch() {
    final api = JscApi(context.read<JscAuthService>());
    return api.getTicket(widget.ticketId, asClient: _asClient).whenComplete(api.dispose);
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final api = JscApi(context.read<JscAuthService>());
    try {
      await api.replyToTicket(
        widget.ticketId,
        asClient: _asClient,
        body: text,
        isInternal: _internal,
      );
      _reply.clear();
      _internal = false;
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

  Future<void> _changeStatus(String newStatus) async {
    final api = JscApi(context.read<JscAuthService>());
    try {
      await api.updateTicket(widget.ticketId, status: newStatus);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      await api.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = !_asClient;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppTheme.primary),
              onSelected: _changeStatus,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Set: Open')),
                PopupMenuItem(value: 'in_progress', child: Text('Set: In progress')),
                PopupMenuItem(value: 'closed', child: Text('Set: Closed')),
              ],
            ),
        ],
      ),
      body: FutureBuilder<({JscTicket ticket, List<JscTicketMessage> messages})>(
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
          final t = snapshot.data!.ticket;
          final msgs = snapshot.data!.messages;
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _HeaderCard(ticket: t),
                      const SizedBox(height: 16),
                      for (final m in msgs) ...[
                        _MessageBubble(message: m, currentUserEmail: context.read<JscAuthService>().user?.email ?? ''),
                        const SizedBox(height: 8),
                      ],
                      if (msgs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text('No messages yet',
                                style: TextStyle(color: Colors.black54)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _ReplyComposer(
                controller: _reply,
                isAdmin: isAdmin,
                internal: _internal,
                onInternalChanged: (v) => setState(() => _internal = v),
                sending: _sending,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final JscTicket ticket;
  const _HeaderCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ticket.subject,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip('Status', ticket.status.replaceAll('_', ' '), AppTheme.active, AppTheme.activeText),
                _chip('Priority', ticket.priority, const Color(0xFFEFEAF8), AppTheme.primary),
                if (ticket.category != null)
                  _chip('Category', ticket.category!, const Color(0xFFE9F5FF), const Color(0xFF0B5FBE)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'From: ${ticket.requesterName.isEmpty ? ticket.requesterEmail : ticket.requesterName}${ticket.requesterName.isEmpty ? '' : ' (${ticket.requesterEmail})'}',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            if (ticket.company != null && ticket.company!.isNotEmpty)
              Text(
                'Company: ${ticket.company}',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            if (ticket.assigneeName != null)
              Text(
                'Assigned: ${ticket.assigneeName}',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text('$label: $value',
          style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 11)),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final JscTicketMessage message;
  final String currentUserEmail;
  const _MessageBubble({required this.message, required this.currentUserEmail});

  @override
  Widget build(BuildContext context) {
    final mine = (message.fromEmail ?? '').toLowerCase() ==
        currentUserEmail.toLowerCase();
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = message.isInternal
        ? const Color(0xFFFFF4D6)
        : (mine ? AppTheme.primary : Colors.white);
    final fg = message.isInternal
        ? const Color(0xFF8A5A00)
        : (mine ? Colors.white : Colors.black87);
    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: message.isInternal
                ? Border.all(color: const Color(0xFFEAB949))
                : (!mine && !message.isInternal
                    ? Border.all(color: const Color(0xFFE3DCEF))
                    : null),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (message.isInternal) ...[
                    const Icon(Icons.lock_outline, size: 14, color: Color(0xFF8A5A00)),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    message.fromName ?? message.fromEmail ?? 'Unknown',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: mine && !message.isInternal
                          ? Colors.white70
                          : Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(message.body, style: TextStyle(color: fg)),
              if (message.createdAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  _formatTimestamp(message.createdAt!),
                  style: TextStyle(
                    fontSize: 10,
                    color: mine && !message.isInternal
                        ? Colors.white60
                        : Colors.black38,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${_2(local.month)}-${_2(local.day)} ${_2(local.hour)}:${_2(local.minute)}';
  }

  String _2(int v) => v.toString().padLeft(2, '0');
}

class _ReplyComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool isAdmin;
  final bool internal;
  final ValueChanged<bool> onInternalChanged;
  final bool sending;
  final VoidCallback onSend;

  const _ReplyComposer({
    required this.controller,
    required this.isAdmin,
    required this.internal,
    required this.onInternalChanged,
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
            if (isAdmin)
              Row(
                children: [
                  Checkbox(
                    value: internal,
                    onChanged: (v) => onInternalChanged(v ?? false),
                  ),
                  const Text('Internal note (not emailed)',
                      style: TextStyle(fontSize: 13)),
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
                      hintText: 'Type a reply…',
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
