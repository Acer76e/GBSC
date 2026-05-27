import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ip_access_rule.dart';
import '../models/zone.dart';
import '../services/cloudflare_api.dart';
import '../theme.dart';

class IpAccessRulesScreen extends StatefulWidget {
  final Zone zone;
  const IpAccessRulesScreen({super.key, required this.zone});

  @override
  State<IpAccessRulesScreen> createState() => _IpAccessRulesScreenState();
}

class _IpAccessRulesScreenState extends State<IpAccessRulesScreen> {
  late Future<List<IpAccessRule>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<IpAccessRule>> _fetch() =>
      context.read<CloudflareApi>().listAccessRules(widget.zone.id);

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  Future<void> _openEditor() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _AccessRuleEditor(zoneId: widget.zone.id),
      ),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _delete(IpAccessRule rule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete rule?'),
        content: Text('${rule.mode.label}: ${rule.targetType.label} ${rule.targetValue}'),
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
      await context.read<CloudflareApi>().deleteAccessRule(widget.zone.id, rule.id);
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
      appBar: AppBar(
        title: const Text('IP Access Rules'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primary),
            onPressed: _openEditor,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<IpAccessRule>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(snapshot.error.toString(), textAlign: TextAlign.center),
                ),
              ]);
            }
            final rules = snapshot.data ?? [];
            if (rules.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Icon(Icons.shield_outlined, size: 56, color: Colors.black26),
                SizedBox(height: 12),
                Text('No access rules', textAlign: TextAlign.center),
                SizedBox(height: 4),
                Text(
                  'Tap + to add one',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45),
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final rule = rules[i];
                return Card(
                  child: ListTile(
                    title: Row(
                      children: [
                        _modePill(rule.mode),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            rule.targetValue,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${rule.targetType.label}${rule.notes != null && rule.notes!.isNotEmpty ? ' · ${rule.notes}' : ''}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _delete(rule),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _modePill(AccessRuleMode mode) {
    Color bg;
    Color fg;
    switch (mode) {
      case AccessRuleMode.whitelist:
        bg = AppTheme.active;
        fg = AppTheme.activeText;
        break;
      case AccessRuleMode.block:
        bg = const Color(0xFFFCD9D6);
        fg = const Color(0xFFB00020);
        break;
      default:
        bg = const Color(0xFFFFE9C7);
        fg = const Color(0xFF8A5A00);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        mode.label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }
}

class _AccessRuleEditor extends StatefulWidget {
  final String zoneId;
  const _AccessRuleEditor({required this.zoneId});

  @override
  State<_AccessRuleEditor> createState() => _AccessRuleEditorState();
}

class _AccessRuleEditorState extends State<_AccessRuleEditor> {
  AccessRuleTargetType _target = AccessRuleTargetType.ip;
  AccessRuleMode _mode = AccessRuleMode.block;
  final _value = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final v = _value.text.trim();
      if (v.isEmpty) throw ArgumentError('Enter a target value');
      await context.read<CloudflareApi>().createAccessRule(
            widget.zoneId,
            mode: _mode,
            targetType: _target,
            value: v,
            notes: _notes.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'New IP Access Rule',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('TARGET',
                style: TextStyle(color: Colors.black54, letterSpacing: 1.2, fontSize: 12)),
            const SizedBox(height: 8),
            DropdownButtonFormField<AccessRuleTargetType>(
              value: _target,
              decoration: const InputDecoration(labelText: 'Type'),
              items: AccessRuleTargetType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _target = v ?? AccessRuleTargetType.ip),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _value,
              decoration: InputDecoration(hintText: _target.hint),
            ),
            const SizedBox(height: 20),
            const Text('MODE',
                style: TextStyle(color: Colors.black54, letterSpacing: 1.2, fontSize: 12)),
            const SizedBox(height: 8),
            DropdownButtonFormField<AccessRuleMode>(
              value: _mode,
              decoration: const InputDecoration(labelText: 'Mode'),
              items: AccessRuleMode.values
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                  .toList(),
              onChanged: (v) => setState(() => _mode = v ?? AccessRuleMode.block),
            ),
            const SizedBox(height: 20),
            const Text('NOTES (OPTIONAL)',
                style: TextStyle(color: Colors.black54, letterSpacing: 1.2, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(hintText: 'e.g. Suspicious traffic'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Add rule'),
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
