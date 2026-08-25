import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../models/wc_order.dart';
import '../services/orders_controller.dart';
import '../services/settings_service.dart';
import '../services/woo_api.dart';
import '../theme.dart';

/// Everything needed to pack and label one order.
class OrderDetailScreen extends StatefulWidget {
  final WcOrder order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _completing = false;

  WcOrder get order => widget.order;

  Future<void> _launch(Uri uri, String failureMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$what copied')));
  }

  Future<void> _markCompleted() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Mark #${order.number} completed?'),
        content: const Text(
          'This sets the order to Completed in WooCommerce, which normally '
          'emails the customer that it is on its way.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Mark completed'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = context.read<OrdersController>();

    setState(() => _completing = true);
    try {
      await controller.markCompleted(order);
      messenger.showSnackBar(
        SnackBar(content: Text('#${order.number} marked completed')),
      );
      navigator.pop();
    } on WooException catch (e) {
      if (mounted) setState(() => _completing = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text([e.message, if (e.detail != null) e.detail!].join(' ')),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettings>();
    final address = order.shipping.isEmpty ? order.billing : order.shipping;
    final phone = order.shipping.phone.isNotEmpty
        ? order.shipping.phone
        : order.billing.phone;

    return Scaffold(
      appBar: AppBar(title: Text('#${order.number}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
        children: [
          _Section(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(
                      label: statusLabel(order.status),
                      background: order.status == 'processing'
                          ? AppTheme.infoBg
                          : AppTheme.warnBg,
                      foreground: order.status == 'processing'
                          ? AppTheme.infoFg
                          : AppTheme.warnFg,
                    ),
                    Pill(
                      label: 'Waiting ${formatAge(order.age)}',
                      background: order.daysWaiting >= 3
                          ? AppTheme.lateBg
                          : order.daysWaiting >= 1
                              ? AppTheme.warnBg
                              : AppTheme.freshBg,
                      foreground: order.daysWaiting >= 3
                          ? AppTheme.lateFg
                          : order.daysWaiting >= 1
                              ? AppTheme.warnFg
                              : AppTheme.freshFg,
                      icon: Icons.schedule,
                    ),
                    if (order.isPickup)
                      const Pill(
                        label: 'In-store pickup',
                        background: Color(0xFFEDE7F6),
                        foreground: Color(0xFF4A3480),
                        icon: Icons.storefront,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  order.customerName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
                const SizedBox(height: 6),
                _KeyValue('Placed', formatWhen(order.createdAt)),
                _KeyValue('Total', order.formattedTotal),
                if (order.paymentMethod.isNotEmpty)
                  _KeyValue('Paid by', order.paymentMethod),
                if (order.shippingMethods.isNotEmpty)
                  _KeyValue('Shipping', order.shippingMethods.join(', ')),
              ],
            ),
          ),
          if (order.customerNote.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.warnBg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sticky_note_2_outlined,
                        size: 20, color: AppTheme.warnFg),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Customer note',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.warnFg,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            order.customerNote,
                            style: const TextStyle(color: AppTheme.text),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _Section(
            title: '${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
            child: Column(
              children: [
                for (var i = 0; i < order.items.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
                  _ItemRow(item: order.items[i], symbol: order.currencySymbol),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: order.isPickup ? 'Customer' : 'Ship to',
            trailing: address.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Copy address',
                    onPressed: () => _copy(address.lines.join('\n'), 'Address'),
                    icon: const Icon(Icons.copy_rounded, size: 20),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (address.isEmpty)
                  const Text(
                    'No address on this order.',
                    style: TextStyle(color: AppTheme.muted),
                  )
                else
                  for (final line in address.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        line,
                        style: const TextStyle(fontSize: 15, color: AppTheme.text),
                      ),
                    ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (phone.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _launch(
                          Uri(scheme: 'tel', path: phone),
                          'No app on this phone can place calls.',
                        ),
                        icon: const Icon(Icons.call, size: 18),
                        label: Text(phone),
                      ),
                    if (order.billing.email.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _launch(
                          Uri(
                            scheme: 'mailto',
                            path: order.billing.email,
                            queryParameters: {
                              'subject': 'Your Glory Bees order #${order.number}',
                            },
                          ),
                          'No email app is set up on this phone.',
                        ),
                        icon: const Icon(Icons.mail_outline, size: 18),
                        label: const Text('Email'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _completing ? null : _markCompleted,
            icon: _completing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : const Icon(Icons.local_shipping_outlined),
            label: Text(_completing ? 'Updating…' : 'Mark as shipped'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _launch(
              // The legacy edit URL still works on stores using WooCommerce's
              // newer order tables — it redirects to the new admin screen.
              Uri.parse(
                  '${settings.storeUrl}/wp-admin/post.php?post=${order.id}&action=edit'),
              'Couldn\'t open the browser.',
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open in store admin'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;

  const _Section({this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: AppTheme.muted,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValue(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppTheme.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, color: AppTheme.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final WcLineItem item;
  final String symbol;

  const _ItemRow({required this.item, required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.line),
          ),
          child: Text(
            '${item.quantity}×',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryDark,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(fontSize: 15, color: AppTheme.text),
              ),
              if (item.sku.isNotEmpty)
                Text(
                  'SKU ${item.sku}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              for (final option in item.options.entries)
                Text(
                  '${option.key}: ${option.value}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$symbol${item.total.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 14, color: AppTheme.muted),
        ),
      ],
    );
  }
}
