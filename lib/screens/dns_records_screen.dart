import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dns_record.dart';
import '../models/zone.dart';
import '../services/cloudflare_api.dart';
import '../theme.dart';

class DnsRecordsScreen extends StatefulWidget {
  final Zone zone;
  const DnsRecordsScreen({super.key, required this.zone});

  @override
  State<DnsRecordsScreen> createState() => _DnsRecordsScreenState();
}

class _DnsRecordsScreenState extends State<DnsRecordsScreen> {
  late Future<List<DnsRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<DnsRecord>> _fetch() =>
      context.read<CloudflareApi>().listDnsRecords(widget.zone.id);

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  Future<void> _openEditor({DnsRecord? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _DnsRecordEditor(zoneId: widget.zone.id, existing: existing),
      ),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _delete(DnsRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete DNS record?'),
        content: Text('${record.type} ${record.name} → ${record.content}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await context.read<CloudflareApi>().deleteDnsRecord(widget.zone.id, record.id);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DNS Records')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<DnsRecord>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(snapshot.error.toString(), textAlign: TextAlign.center),
                    ),
                  ),
                ],
              );
            }
            final records = snapshot.data ?? [];
            if (records.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.dns_outlined, size: 56, color: Colors.black26),
                  SizedBox(height: 12),
                  Text('No DNS records', textAlign: TextAlign.center),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = records[i];
                return Card(
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        r.type,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      r.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (r.proxied)
                          const Tooltip(
                            message: 'Proxied',
                            child: Icon(Icons.cloud, color: Color(0xFFF6821F), size: 20),
                          ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (v) {
                            if (v == 'edit') _openEditor(existing: r);
                            if (v == 'delete') _delete(r);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ],
                    ),
                    onTap: () => _openEditor(existing: r),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _DnsRecordEditor extends StatefulWidget {
  final String zoneId;
  final DnsRecord? existing;
  const _DnsRecordEditor({required this.zoneId, this.existing});

  @override
  State<_DnsRecordEditor> createState() => _DnsRecordEditorState();
}

class _DnsRecordEditorState extends State<_DnsRecordEditor> {
  static const _types = ['A', 'AAAA', 'CNAME', 'TXT', 'MX', 'NS', 'SRV', 'CAA'];

  late String _type;
  late TextEditingController _name;
  late TextEditingController _content;
  late TextEditingController _ttl;
  late TextEditingController _priority;
  late bool _proxied;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _type = r?.type ?? 'A';
    _name = TextEditingController(text: r?.name ?? '');
    _content = TextEditingController(text: r?.content ?? '');
    _ttl = TextEditingController(text: (r?.ttl ?? 1).toString());
    _priority = TextEditingController(text: r?.priority?.toString() ?? '');
    _proxied = r?.proxied ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    _ttl.dispose();
    _priority.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final priority = _priority.text.trim().isEmpty ? null : int.tryParse(_priority.text.trim());
      final record = DnsRecord(
        id: widget.existing?.id ?? '',
        type: _type,
        name: _name.text.trim(),
        content: _content.text.trim(),
        ttl: int.tryParse(_ttl.text.trim()) ?? 1,
        proxied: _proxied,
        priority: priority,
      );
      final api = context.read<CloudflareApi>();
      if (widget.existing == null) {
        await api.createDnsRecord(widget.zoneId, record);
      } else {
        await api.updateDnsRecord(widget.zoneId, widget.existing!.id, record);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canProxy = _type == 'A' || _type == 'AAAA' || _type == 'CNAME';
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing == null ? 'New DNS Record' : 'Edit DNS Record',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: _types
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? 'A'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. www, @, sub.example.com',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              decoration: const InputDecoration(
                labelText: 'Content',
                hintText: 'IPv4, hostname, or value',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ttl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'TTL',
                      hintText: '1 = Auto',
                    ),
                  ),
                ),
                if (_type == 'MX' || _type == 'SRV') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _priority,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Priority'),
                    ),
                  ),
                ],
              ],
            ),
            if (canProxy) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                value: _proxied,
                onChanged: (v) => setState(() => _proxied = v),
                title: const Text('Proxy through Cloudflare'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
