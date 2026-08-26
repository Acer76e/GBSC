/// One row of `/reports/orders/totals` — a status the store actually has, its
/// display name, and how many orders sit in it right now.
///
/// Read at runtime rather than hardcoded: this shop adds statuses via a plugin
/// ("Ready for Pickup", "Partially Paid", "Backordered"), and a filter that
/// can't see them is a filter that quietly misses orders.
class OrderStatusCount {
  final String slug;
  final String name;
  final int total;

  const OrderStatusCount({
    required this.slug,
    required this.name,
    required this.total,
  });

  factory OrderStatusCount.fromJson(Map<String, dynamic> json) {
    final raw = json['total'];
    return OrderStatusCount(
      slug: json['slug']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      total: raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0,
    );
  }

  /// Statuses an order ends its life in. They're real statuses, but nothing in
  /// them is waiting on the shop, so they'd only clutter the picker.
  static const Set<String> terminal = {
    'completed',
    'cancelled',
    'refunded',
    'failed',
    'checkout-draft',
    'draft',
    'trash',
    'any',
  };

  bool get isWaitingCandidate => slug.isNotEmpty && !terminal.contains(slug);
}
