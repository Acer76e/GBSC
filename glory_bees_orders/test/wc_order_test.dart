import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glory_bees_orders/models/wc_order.dart';

/// Trimmed from a real WooCommerce `GET /wp-json/wc/v3/orders` response —
/// strings for numbers, `_gmt` timestamps without a zone suffix, and item meta
/// mixing internal keys with display ones.
const String _shippedOrderJson = '''
{
  "id": 45812,
  "number": "45812",
  "status": "processing",
  "currency_symbol": "\$",
  "date_created": "2026-08-20T09:14:05",
  "date_created_gmt": "2026-08-20T13:14:05",
  "total": "128.45",
  "payment_method_title": "Credit Card",
  "customer_note": "Please include a gift receipt",
  "billing": {
    "first_name": "Dana",
    "last_name": "Whitfield",
    "address_1": "18 Mill Race Rd",
    "city": "Bel Air",
    "state": "MD",
    "postcode": "21014",
    "country": "US",
    "email": "dana@example.com",
    "phone": "410-555-0142"
  },
  "shipping": {
    "first_name": "Dana",
    "last_name": "Whitfield",
    "company": "Quilting Guild",
    "address_1": "18 Mill Race Rd",
    "address_2": "Unit B",
    "city": "Bel Air",
    "state": "MD",
    "postcode": "21014",
    "country": "US",
    "phone": ""
  },
  "line_items": [
    {
      "name": "Aurifil 50wt Thread - Sky Blue",
      "sku": "AUR-50-2710",
      "quantity": 3,
      "total": "26.85",
      "meta_data": [
        {"key": "_reduced_stock", "value": "3"},
        {"display_key": "Cut length", "display_value": "<p>2 yards</p>"}
      ]
    },
    {
      "name": "Olfa Rotary Cutter 45mm",
      "sku": "OLF-RTY-2",
      "quantity": 1,
      "total": "101.60",
      "meta_data": []
    }
  ],
  "shipping_lines": [
    {"method_id": "flat_rate", "method_title": "Flat rate", "total": "8.50"}
  ]
}
''';

const String _pickupOrderJson = '''
{
  "id": 45813,
  "number": "45813",
  "status": "on-hold",
  "date_created_gmt": "2026-08-24T15:02:00",
  "total": "42.00",
  "billing": {"first_name": "Rae", "last_name": "Olsen", "phone": "443-555-0199"},
  "shipping": {},
  "line_items": [{"name": "Bobbin pack", "quantity": 2, "total": "42.00"}],
  "shipping_lines": [
    {"method_id": "local_pickup", "method_title": "Local pickup", "total": "0.00"}
  ]
}
''';

WcOrder _parse(String json) =>
    WcOrder.fromJson(jsonDecode(json) as Map<String, dynamic>);

void main() {
  group('WcOrder', () {
    test('parses a shipping order', () {
      final order = _parse(_shippedOrderJson);

      expect(order.id, 45812);
      expect(order.number, '45812');
      expect(order.status, 'processing');
      expect(order.total, 128.45);
      expect(order.formattedTotal, r'$128.45');
      expect(order.itemCount, 4, reason: '3 spools + 1 cutter');
      expect(order.shippingMethods, ['Flat rate']);
      expect(order.isPickup, isFalse);
      expect(order.customerNote, 'Please include a gift receipt');
    });

    test('reads the _gmt timestamp as UTC, not local time', () {
      final order = _parse(_shippedOrderJson);
      expect(order.createdAt, isNotNull);
      expect(
        order.createdAt!.toUtc(),
        DateTime.utc(2026, 8, 20, 13, 14, 5),
      );
    });

    test('prefers the shipping name and builds a mailable address', () {
      final order = _parse(_shippedOrderJson);
      expect(order.customerName, 'Dana Whitfield');
      expect(order.shipping.lines, [
        'Dana Whitfield',
        'Quilting Guild',
        '18 Mill Race Rd',
        'Unit B',
        'Bel Air, MD 21014',
      ]);
    });

    test('keeps display item options and drops internal meta', () {
      final thread = _parse(_shippedOrderJson).items.first;
      expect(thread.sku, 'AUR-50-2710');
      expect(thread.options, {'Cut length': '2 yards'},
          reason: '_reduced_stock is internal, and HTML is stripped');
    });

    test('flags a local pickup and falls back to the billing name', () {
      final order = _parse(_pickupOrderJson);
      expect(order.isPickup, isTrue);
      expect(order.customerName, 'Rae Olsen');
      expect(order.currencySymbol, r'$', reason: 'defaults when absent');
    });

    test('treats an order with no shipping line or address as a pickup', () {
      final order = WcOrder.fromJson({
        'id': 1,
        'number': '1',
        'status': 'processing',
        'total': '10.00',
        'line_items': [],
        'shipping_lines': [],
        'shipping': {},
      });
      expect(order.isPickup, isTrue);
    });

    test('survives a sparse payload without throwing', () {
      final order = WcOrder.fromJson({'id': 7});
      expect(order.customerName, 'Guest');
      expect(order.itemCount, 0);
      expect(order.total, 0);
      expect(order.createdAt, isNull);
      expect(order.age, Duration.zero);
    });

    test('counts whole days waiting for the urgency colour', () {
      final order = WcOrder.fromJson({
        'id': 8,
        'date_created_gmt':
            DateTime.now().toUtc().subtract(const Duration(hours: 50)).toIso8601String(),
      });
      expect(order.daysWaiting, 2);
    });
  });
}
