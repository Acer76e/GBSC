import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models/wc_order.dart';
import '../services/orders_controller.dart';
import '../services/settings_service.dart';
import '../services/woo_api.dart';
import '../theme.dart';
import '../widgets/order_card.dart';
import 'order_detail_screen.dart';
import 'settings_screen.dart';

/// The home screen: how many orders are waiting, and which ones.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with WidgetsBindingObserver {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // While the app is open, keep the list current without anyone tapping.
    _poll = Timer.periodic(const Duration(minutes: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is exactly when the list should be right.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    await context.read<OrdersController>().refresh();
  }

  void _openOrder(WcOrder order) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersController>();
    final settings = context.watch<AppSettings>();
    final visible = orders.visibleOrders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders to ship'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: orders.isLoading ? null : _refresh,
            icon: orders.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _SummaryHeader(
              toShip: orders.toShipCount,
              pickups: orders.pickupCount,
              showingPickups: settings.showPickup,
              lastUpdated: orders.lastUpdated,
              loading: orders.isLoading,
            ),
            if (orders.error != null) ...[
              const SizedBox(height: 12),
              _ErrorNotice(
                error: orders.error!,
                onRetry: _refresh,
                // A stale list is still useful, so only offer the settings
                // shortcut when there's nothing to fall back on.
                showSettings: orders.allOrders.isEmpty,
              ),
            ],
            if (visible.isEmpty && orders.hasLoadedOnce && orders.error == null) ...[
              const SizedBox(height: 40),
              const _AllCaughtUp(),
            ],
            if (!orders.hasLoadedOnce && orders.isLoading) ...[
              const SizedBox(height: 60),
              const Center(child: CircularProgressIndicator()),
            ],
            for (final order in visible) ...[
              const SizedBox(height: 10),
              OrderCard(order: order, onTap: () => _openOrder(order)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final int toShip;
  final int pickups;
  final bool showingPickups;
  final DateTime? lastUpdated;
  final bool loading;

  const _SummaryHeader({
    required this.toShip,
    required this.pickups,
    required this.showingPickups,
    required this.lastUpdated,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$toShip',
                  style: const TextStyle(
                    fontSize: 46,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  toShip == 1 ? 'order to ship' : 'orders to ship',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pickups > 0)
                  Pill(
                    label: showingPickups
                        ? '$pickups pickup${pickups == 1 ? '' : 's'}'
                        : '$pickups pickup${pickups == 1 ? '' : 's'} hidden',
                    background: const Color(0xFFEDE7F6),
                    foreground: const Color(0xFF4A3480),
                    icon: Icons.storefront,
                  ),
                const SizedBox(height: 8),
                Text(
                  loading ? 'Checking…' : 'Updated ${formatSince(lastUpdated)}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  final WooException error;
  final VoidCallback onRetry;
  final bool showSettings;

  const _ErrorNotice({
    required this.error,
    required this.onRetry,
    required this.showSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: AppTheme.lateFg, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error.message,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.lateFg,
                    ),
                  ),
                ),
              ],
            ),
            if (error.detail != null) ...[
              const SizedBox(height: 6),
              Text(
                error.detail!,
                style: const TextStyle(fontSize: 13, color: AppTheme.muted),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
                if (showSettings) ...[
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    child: const Text('Settings'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AllCaughtUp extends StatelessWidget {
  const _AllCaughtUp();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            color: AppTheme.freshBg,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 46, color: AppTheme.freshFg),
        ),
        const SizedBox(height: 16),
        const Text(
          'All caught up',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.text,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Nothing is waiting to go out.',
          style: TextStyle(color: AppTheme.muted),
        ),
      ],
    );
  }
}
