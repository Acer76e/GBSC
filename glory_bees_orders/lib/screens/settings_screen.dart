import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order_status_count.dart';
import '../services/orders_controller.dart';
import '../services/settings_service.dart';
import '../services/woo_api.dart';
import '../theme.dart';
import 'diagnostics_screen.dart';
import 'setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _testing = false;

  /// Statuses as the store reports them. Null until the lookup finishes, and
  /// stays null if it fails — the picker then falls back to a built-in list.
  List<OrderStatusCount>? _storeStatuses;
  bool _statusesFailed = false;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    try {
      final statuses = await context.read<WooApi>().fetchStatusCounts();
      if (!mounted) return;
      setState(() => _storeStatuses = statuses);
    } on WooException {
      // A key without reports access, or an offline phone. Not worth an error
      // banner — the fallback list still works.
      if (mounted) setState(() => _statusesFailed = true);
    }
  }

  /// What to show in the picker: the store's own statuses when we have them,
  /// otherwise the built-in list.
  List<String> get _pickerStatuses {
    final fromStore = _storeStatuses;
    if (fromStore == null || fromStore.isEmpty) return kSelectableStatuses;
    // Anything already ticked stays visible even if the store stopped
    // reporting it, so a selection can always be turned off again.
    final slugs = fromStore.map((s) => s.slug).toList();
    for (final selected in context.read<AppSettings>().statuses) {
      if (!slugs.contains(selected)) slugs.add(selected);
    }
    return slugs;
  }

  String _subtitleFor(String slug) {
    final fromStore = _storeStatuses;
    if (fromStore != null) {
      for (final status in fromStore) {
        if (status.slug != slug) continue;
        final hint = _statusHint(slug);
        final count = status.total == 1
            ? '1 order right now'
            : '${status.total} orders right now';
        return hint.isEmpty ? count : '$hint · $count';
      }
    }
    return _statusHint(slug);
  }

  String _labelFor(String slug) {
    final fromStore = _storeStatuses;
    if (fromStore != null) {
      for (final status in fromStore) {
        if (status.slug == slug && status.name.isNotEmpty) return status.name;
      }
    }
    return statusLabel(slug);
  }

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<WooApi>();
    setState(() => _testing = true);
    try {
      final count = await api.testConnection();
      messenger.showSnackBar(
        SnackBar(
          content: Text(count == null
              ? 'Connected. The store didn\'t send a count, so run '
                  'Diagnostics to see what it returns.'
              : 'Connected — $count matching order(s) found.'),
        ),
      );
    } on WooException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text([e.message, if (e.detail != null) e.detail!].join(' ')),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect this phone?'),
        content: const Text(
          'The API key is erased from this phone. The key itself keeps working '
          'until you delete it on the website.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    context.read<OrdersController>().clear();
    await context.read<AppSettings>().signOut();
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final orders = context.read<OrdersController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          _Group(
            title: 'Which orders count as waiting',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_storeStatuses == null && !_statusesFailed)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Reading the statuses your store uses…',
                      style: TextStyle(fontSize: 12, color: AppTheme.muted),
                    ),
                  ),
                if (_statusesFailed)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Couldn\'t read the store\'s own status list, so these '
                      'are the usual ones.',
                      style: TextStyle(fontSize: 12, color: AppTheme.muted),
                    ),
                  ),
                for (final status in _pickerStatuses)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: settings.statuses.contains(status),
                    title: Text(_labelFor(status)),
                    subtitle: Text(_subtitleFor(status),
                        style: const TextStyle(fontSize: 12)),
                    onChanged: (checked) async {
                      final next = Set<String>.from(settings.statuses);
                      if (checked == true) {
                        next.add(status);
                      } else {
                        next.remove(status);
                      }
                      // Never let the filter empty out — that would ask the
                      // store for every order it has ever taken.
                      if (next.isEmpty) return;
                      await settings.setStatuses(next);
                      await orders.refresh();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Group(
            title: 'List',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.showPickup,
                  title: const Text('Show in-store pickups'),
                  subtitle: const Text(
                    'Orders with no parcel to send',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (value) => settings.setShowPickup(value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.oldestFirst,
                  title: const Text('Oldest first'),
                  subtitle: const Text(
                    'Longest-waiting order at the top',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (value) async {
                    await settings.setOldestFirst(value);
                    await orders.refresh();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Group(
            title: 'Store',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.storeUrl,
                  style: const TextStyle(fontSize: 15, color: AppTheme.text),
                ),
                const SizedBox(height: 4),
                Text(
                  'Key ${_maskKey(settings.consumerKey)}',
                  style: const TextStyle(fontSize: 13, color: AppTheme.muted),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text('Test connection'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const DiagnosticsScreen()),
                      ),
                      icon: const Icon(Icons.troubleshoot, size: 18),
                      label: const Text('Diagnostics'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: _disconnect,
                      style: TextButton.styleFrom(
                          foregroundColor: AppTheme.lateFg),
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const HowToGetAKey(),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'Glory Bees Orders 1.1',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ),
        ],
      ),
    );
  }

  static String _statusHint(String status) {
    switch (status) {
      case 'processing':
        return 'Paid and waiting to go out — the usual one';
      case 'on-hold':
        return 'Waiting on a check or bank transfer';
      case 'pending':
        return 'Checkout started but never paid';
      case 'partially-paid':
        return 'Part of the balance is still owed';
      case 'ready-pickup':
        return 'Waiting for the customer to collect';
      case 'backordered':
        return 'Waiting on stock to arrive';
      default:
        return '';
    }
  }

  /// Shows just enough of the key to tell two of them apart.
  static String _maskKey(String key) {
    if (key.length <= 10) return '••••';
    return '${key.substring(0, 6)}…${key.substring(key.length - 4)}';
  }
}

class _Group extends StatelessWidget {
  final String title;
  final Widget child;

  const _Group({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}
