import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The store this app was built for. Pre-filled on the setup screen so there
/// is nothing to type but the API key.
const String kDefaultStoreUrl = 'https://glorybeessewingcenter.com';

/// WooCommerce statuses that can plausibly be "waiting on me".
const List<String> kSelectableStatuses = [
  'processing',
  'on-hold',
  'pending',
];

const Map<String, String> kStatusLabels = {
  'processing': 'Processing',
  'on-hold': 'On hold',
  'pending': 'Pending payment',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
  'refunded': 'Refunded',
  'failed': 'Failed',
};

String statusLabel(String status) =>
    kStatusLabels[status] ??
    (status.isEmpty
        ? 'Unknown'
        : status[0].toUpperCase() + status.substring(1).replaceAll('-', ' '));

/// Turns whatever the user typed into a scheme-qualified origin with no
/// trailing slash and no REST path glued on the end.
String normalizeStoreUrl(String input) {
  var url = input.trim();
  if (url.isEmpty) return '';
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://$url';
  }
  // Tolerate someone pasting a full REST endpoint or an admin page.
  final cut = url.indexOf(RegExp(r'/(wp-json|wp-admin)'));
  if (cut > 0) url = url.substring(0, cut);
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// The three values every API call needs, as a plain value object so a key
/// can be tested before it is saved.
class WooCreds {
  final String storeUrl;
  final String consumerKey;
  final String consumerSecret;

  const WooCreds({
    required this.storeUrl,
    required this.consumerKey,
    required this.consumerSecret,
  });

  bool get isComplete =>
      storeUrl.isNotEmpty && consumerKey.isNotEmpty && consumerSecret.isNotEmpty;
}

class AppSettings extends ChangeNotifier {
  static const _kStoreUrl = 'gb_store_url';
  static const _kKey = 'gb_consumer_key';
  static const _kSecret = 'gb_consumer_secret';
  static const _kStatuses = 'gb_statuses';
  static const _kShowPickup = 'gb_show_pickup';
  static const _kOldestFirst = 'gb_oldest_first';

  // `encryptedSharedPreferences` keeps values in an AES-encrypted store, and
  // `resetOnError` clears it rather than throwing if a key ever fails to
  // decrypt (which happens after some Android backup/restore cycles) — the
  // user just signs in again instead of hitting a permanently broken app.
  static const _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
  );

  final FlutterSecureStorage _storage =
      const FlutterSecureStorage(aOptions: _androidOptions);

  String _storeUrl = '';
  String _consumerKey = '';
  String _consumerSecret = '';
  Set<String> _statuses = {'processing', 'on-hold'};
  bool _showPickup = true;
  bool _oldestFirst = true;
  bool _loaded = false;

  String get storeUrl => _storeUrl;
  String get consumerKey => _consumerKey;
  String get consumerSecret => _consumerSecret;
  Set<String> get statuses => _statuses;
  bool get showPickup => _showPickup;
  bool get oldestFirst => _oldestFirst;
  bool get isLoaded => _loaded;

  WooCreds get creds => WooCreds(
        storeUrl: _storeUrl,
        consumerKey: _consumerKey,
        consumerSecret: _consumerSecret,
      );

  bool get isConfigured =>
      _storeUrl.isNotEmpty && _consumerKey.isNotEmpty && _consumerSecret.isNotEmpty;

  /// Statuses to request, never empty — an empty filter would ask WooCommerce
  /// for every order ever placed.
  List<String> get activeStatuses =>
      _statuses.isEmpty ? const ['processing'] : _statuses.toList();

  Future<void> load() async {
    try {
      final all = await _storage.readAll(aOptions: _androidOptions);
      _storeUrl = all[_kStoreUrl] ?? '';
      _consumerKey = all[_kKey] ?? '';
      _consumerSecret = all[_kSecret] ?? '';
      final statuses = all[_kStatuses];
      if (statuses != null && statuses.isNotEmpty) {
        _statuses = statuses.split(',').where((s) => s.isNotEmpty).toSet();
      }
      _showPickup = all[_kShowPickup] != 'false';
      _oldestFirst = all[_kOldestFirst] != 'false';
    } catch (e) {
      debugPrint('Settings load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveCredentials({
    required String storeUrl,
    required String consumerKey,
    required String consumerSecret,
  }) async {
    _storeUrl = normalizeStoreUrl(storeUrl);
    _consumerKey = consumerKey.trim();
    _consumerSecret = consumerSecret.trim();
    await _storage.write(
        key: _kStoreUrl, value: _storeUrl, aOptions: _androidOptions);
    await _storage.write(
        key: _kKey, value: _consumerKey, aOptions: _androidOptions);
    await _storage.write(
        key: _kSecret, value: _consumerSecret, aOptions: _androidOptions);
    notifyListeners();
  }

  Future<void> setStatuses(Set<String> statuses) async {
    _statuses = statuses;
    await _storage.write(
        key: _kStatuses, value: statuses.join(','), aOptions: _androidOptions);
    notifyListeners();
  }

  Future<void> setShowPickup(bool value) async {
    _showPickup = value;
    await _storage.write(
        key: _kShowPickup, value: '$value', aOptions: _androidOptions);
    notifyListeners();
  }

  Future<void> setOldestFirst(bool value) async {
    _oldestFirst = value;
    await _storage.write(
        key: _kOldestFirst, value: '$value', aOptions: _androidOptions);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _storage.deleteAll(aOptions: _androidOptions);
    _storeUrl = '';
    _consumerKey = '';
    _consumerSecret = '';
    _statuses = {'processing', 'on-hold'};
    _showPickup = true;
    _oldestFirst = true;
    notifyListeners();
  }
}
