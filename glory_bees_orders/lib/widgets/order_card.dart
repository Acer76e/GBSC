import 'package:flutter/material.dart';

import '../format.dart';
import '../models/wc_order.dart';
import '../services/settings_service.dart';
import '../theme.dart';

/// One order, sized so the number, who it's for, and how long it has been
/// waiting all land in a single glance.
class OrderCard extends StatelessWidget {
  final WcOrder order;
  final VoidCallback onTap;

  const OrderCard({super.key, required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final days = order.daysWaiting;
    final ageBg = days >= 3
        ? AppTheme.lateBg
        : days >= 1
            ? AppTheme.warnBg
            : AppTheme.freshBg;
    final ageFg = days >= 3
        ? AppTheme.lateFg
        : days >= 1
            ? AppTheme.warnFg
            : AppTheme.freshFg;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${order.number}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.customerName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(
                    label: formatAge(order.age),
                    background: ageBg,
                    foreground: ageFg,
                    icon: Icons.schedule,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  '${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
                  order.formattedTotal,
                  if (order.shippingMethods.isNotEmpty) order.shippingMethods.first,
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: AppTheme.muted),
              ),
              const SizedBox(height: 6),
              Text(
                formatWhen(order.createdAt),
                style: const TextStyle(fontSize: 13, color: AppTheme.muted),
              ),
              const SizedBox(height: 10),
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
                  if (order.isPickup)
                    const Pill(
                      label: 'Pickup',
                      background: Color(0xFFEDE7F6),
                      foreground: Color(0xFF4A3480),
                      icon: Icons.storefront,
                    ),
                  if (order.customerNote.isNotEmpty)
                    const Pill(
                      label: 'Note',
                      background: AppTheme.warnBg,
                      foreground: AppTheme.warnFg,
                      icon: Icons.sticky_note_2_outlined,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
