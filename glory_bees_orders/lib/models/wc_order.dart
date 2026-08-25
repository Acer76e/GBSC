/// Models for the slice of the WooCommerce order payload this app cares about.
///
/// WooCommerce returns most numbers as strings ("29.00") and omits optional
/// objects entirely on some setups, so every accessor here is defensive.
library;

String _str(dynamic v) => v == null ? '' : v.toString();

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(_str(v)) ?? 0;
}

/// Parses a WooCommerce timestamp. The `*_gmt` fields carry no timezone suffix
/// but are UTC, so they need the `Z` appended before parsing.
DateTime? _gmt(dynamic v) {
  final raw = _str(v);
  if (raw.isEmpty) return null;
  final withZone = raw.endsWith('Z') ? raw : '${raw}Z';
  return DateTime.tryParse(withZone)?.toLocal();
}

class WcAddress {
  final String firstName;
  final String lastName;
  final String company;
  final String address1;
  final String address2;
  final String city;
  final String state;
  final String postcode;
  final String country;
  final String email;
  final String phone;

  const WcAddress({
    required this.firstName,
    required this.lastName,
    required this.company,
    required this.address1,
    required this.address2,
    required this.city,
    required this.state,
    required this.postcode,
    required this.country,
    required this.email,
    required this.phone,
  });

  factory WcAddress.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const {};
    return WcAddress(
      firstName: _str(j['first_name']),
      lastName: _str(j['last_name']),
      company: _str(j['company']),
      address1: _str(j['address_1']),
      address2: _str(j['address_2']),
      city: _str(j['city']),
      state: _str(j['state']),
      postcode: _str(j['postcode']),
      country: _str(j['country']),
      email: _str(j['email']),
      phone: _str(j['phone']),
    );
  }

  String get name => '$firstName $lastName'.trim();

  bool get isEmpty => address1.isEmpty && city.isEmpty && postcode.isEmpty;

  /// Street address on its own lines, then "City, ST 12345".
  List<String> get lines {
    final out = <String>[];
    if (name.isNotEmpty) out.add(name);
    if (company.isNotEmpty) out.add(company);
    if (address1.isNotEmpty) out.add(address1);
    if (address2.isNotEmpty) out.add(address2);
    final cityLine = [
      if (city.isNotEmpty) city,
      if (state.isNotEmpty || postcode.isNotEmpty)
        [state, postcode].where((s) => s.isNotEmpty).join(' '),
    ].where((s) => s.isNotEmpty).join(', ');
    if (cityLine.isNotEmpty) out.add(cityLine);
    if (country.isNotEmpty && country != 'US') out.add(country);
    return out;
  }

  String get singleLine => lines.join(', ');
}

class WcLineItem {
  final String name;
  final String sku;
  final int quantity;
  final double total;

  /// Product options (fabric cut length, thread color, …) that WooCommerce
  /// stores as item meta. Internal keys start with `_` and are filtered out.
  final Map<String, String> options;

  const WcLineItem({
    required this.name,
    required this.sku,
    required this.quantity,
    required this.total,
    required this.options,
  });

  factory WcLineItem.fromJson(Map<String, dynamic> json) {
    final options = <String, String>{};
    final meta = json['meta_data'];
    if (meta is List) {
      for (final entry in meta) {
        if (entry is! Map) continue;
        final key = _str(entry['display_key']).isNotEmpty
            ? _str(entry['display_key'])
            : _str(entry['key']);
        if (key.isEmpty || key.startsWith('_')) continue;
        final value = _str(entry['display_value']).isNotEmpty
            ? _str(entry['display_value'])
            : _str(entry['value']);
        if (value.isEmpty) continue;
        // display_value arrives as HTML on some plugins ("<p>Blue</p>").
        options[key] = value.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      }
    }
    return WcLineItem(
      name: _str(json['name']),
      sku: _str(json['sku']),
      quantity: (json['quantity'] is num)
          ? (json['quantity'] as num).toInt()
          : int.tryParse(_str(json['quantity'])) ?? 1,
      total: _num(json['total']),
      options: options,
    );
  }
}

class WcOrder {
  final int id;
  final String number;
  final String status;
  final String currencySymbol;
  final DateTime? createdAt;
  final double total;
  final String paymentMethod;
  final String customerNote;
  final WcAddress billing;
  final WcAddress shipping;
  final List<WcLineItem> items;
  final List<String> shippingMethods;
  final bool isPickup;

  const WcOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.currencySymbol,
    required this.createdAt,
    required this.total,
    required this.paymentMethod,
    required this.customerNote,
    required this.billing,
    required this.shipping,
    required this.items,
    required this.shippingMethods,
    required this.isPickup,
  });

  factory WcOrder.fromJson(Map<String, dynamic> json) {
    final items = <WcLineItem>[];
    final rawItems = json['line_items'];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map) {
          items.add(WcLineItem.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }

    final methods = <String>[];
    var pickup = false;
    final rawShipping = json['shipping_lines'];
    if (rawShipping is List) {
      for (final entry in rawShipping) {
        if (entry is! Map) continue;
        final methodId = _str(entry['method_id']).toLowerCase();
        final title = _str(entry['method_title']);
        if (title.isNotEmpty) methods.add(title);
        if (methodId.contains('pickup') || title.toLowerCase().contains('pickup')) {
          pickup = true;
        }
      }
    }

    final shipping = WcAddress.fromJson(
        (json['shipping'] as Map?)?.cast<String, dynamic>());

    // No shipping line and no shipping address means nothing was ever costed
    // for delivery — in a shop with a storefront that's an in-store pickup.
    if (methods.isEmpty && shipping.isEmpty) pickup = true;

    return WcOrder(
      id: (json['id'] is num) ? (json['id'] as num).toInt() : 0,
      number: _str(json['number']),
      status: _str(json['status']),
      currencySymbol: _str(json['currency_symbol']).isNotEmpty
          ? _str(json['currency_symbol'])
          : r'$',
      createdAt: _gmt(json['date_created_gmt']) ??
          DateTime.tryParse(_str(json['date_created'])),
      total: _num(json['total']),
      paymentMethod: _str(json['payment_method_title']),
      customerNote: _str(json['customer_note']),
      billing: WcAddress.fromJson((json['billing'] as Map?)?.cast<String, dynamic>()),
      shipping: shipping,
      items: items,
      shippingMethods: methods,
      isPickup: pickup,
    );
  }

  /// The name to show on the card: shipping name when the parcel is going
  /// somewhere, otherwise whoever paid.
  String get customerName {
    final shipName = shipping.name;
    if (shipName.isNotEmpty) return shipName;
    final billName = billing.name;
    return billName.isNotEmpty ? billName : 'Guest';
  }

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  Duration get age =>
      createdAt == null ? Duration.zero : DateTime.now().difference(createdAt!);

  /// Whole days waiting — what drives the colour of the age chip.
  int get daysWaiting => age.inHours ~/ 24;

  String get formattedTotal => '$currencySymbol${total.toStringAsFixed(2)}';
}
