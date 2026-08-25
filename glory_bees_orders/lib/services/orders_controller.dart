import 'package:flutter/foundation.dart';

import '../models/wc_order.dart';
import 'settings_service.dart';
import 'woo_api.dart';

/// Holds the order list the whole app reads from, so the list screen and the
/// detail screen never disagree about what is outstanding.
class OrdersController extends ChangeNotifier {
  OrdersController({required AppSettings settings, required WooApi api})
      : _settings = settings,
        _api = api;

  final AppSettings _settings;
  final WooApi _api;

  List<WcOrder> _orders = const [];
  bool _loading = false;
  WooException? _error;
  DateTime? _lastUpdated;

  bool get isLoading => _loading;
  WooException? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasLoadedOnce => _lastUpdated != null;

  /// Everything fetched, including pickups.
  List<WcOrder> get allOrders => _orders;

  /// What the list screen shows, after the pickup preference is applied.
  List<WcOrder> get visibleOrders =>
      _settings.showPickup ? _orders : _orders.where((o) => !o.isPickup).toList();

  /// Orders that actually need a parcel — the number on the header.
  int get toShipCount => _orders.where((o) => !o.isPickup).length;

  int get pickupCount => _orders.where((o) => o.isPickup).length;

  /// Drops everything on disconnect so a reconnect to a different store
  /// can't flash the previous store's orders.
  void clear() {
    _orders = const [];
    _error = null;
    _lastUpdated = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      _orders = await _api.fetchPendingOrders();
      _error = null;
      _lastUpdated = DateTime.now();
    } on WooException catch (e) {
      _error = e;
    } catch (e) {
      _error = WooException('Something went wrong.', detail: e.toString());
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Marks an order completed and drops it from the list, so the count on the
  /// header is right immediately instead of after the next refresh.
  Future<void> markCompleted(WcOrder order) async {
    await _api.markCompleted(order.id);
    _orders = _orders.where((o) => o.id != order.id).toList();
    notifyListeners();
  }
}
