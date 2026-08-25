import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/orders_controller.dart';
import '../services/settings_service.dart';
import '../services/woo_api.dart';
import '../theme.dart';
import 'setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _testing = false;

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<WooApi>();
    setState(() => _testing = true);
    try {
      final count = await api.testConnection();
      messenger.showSnackBar(
        SnackBar(content: Text('Connected — $count matching order(s) found.')),
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
                for (final status in kSelectableStatuses)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: settings.statuses.contains(status),
                    title: Text(statusLabel(status)),
                    subtitle: Text(_statusHint(status),
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
              'Glory Bees Orders 1.0',
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
