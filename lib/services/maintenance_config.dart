import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MaintenanceConfig extends ChangeNotifier {
  static const _kStoreKey = 'cf_maintenance_config_v1';

  // Defaults from KJONGSys spec.
  static const String defaultAccountId = '87876c1d35c9cb5e2a2f1de75311a8f6';
  static const String defaultKvNamespaceId = '052f484030aa4be98ab729b98e7a601f';
  static const String defaultMaintenanceScript = 'maintenance-mode';
  static const String defaultSuspendedScript = 'account-suspended';
  static const String kvBypassIpsKey = 'bypass_ips';
  static const String kvUpdatesUrlKey = 'updates_url';

  static const List<String> defaultCoveredZones = [
    '1-offcustomz.com',
    '1offbsg.com',
    '1offcustomz.com',
    'bsg1off.com',
    'buccibuilt.com',
    'callbreezy.com',
    'capecoralanimalshelter.com',
    'capecoralanimalshelter.org',
    'citicenterpieces.com',
    'elaineschmidt.com',
    'keithgallagher.xyz',
    'kjongsys.com',
    'rbknowsbest.com',
    'strawberryhillmd.com',
    'testalongevity.com',
    'theswanroom.com',
    'whatscookinglakeland.com',
  ];

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String _accountId = defaultAccountId;
  String _kvNamespaceId = defaultKvNamespaceId;
  String _maintenanceScript = defaultMaintenanceScript;
  String _suspendedScript = defaultSuspendedScript;
  List<String> _coveredZones = List.of(defaultCoveredZones);
  bool _loaded = false;

  String get accountId => _accountId;
  String get kvNamespaceId => _kvNamespaceId;
  String get maintenanceScript => _maintenanceScript;
  String get suspendedScript => _suspendedScript;
  List<String> get coveredZones => List.unmodifiable(_coveredZones);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final raw = await _storage.read(key: _kStoreKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _accountId = (m['accountId'] as String?) ?? defaultAccountId;
        _kvNamespaceId = (m['kvNamespaceId'] as String?) ?? defaultKvNamespaceId;
        _maintenanceScript =
            (m['maintenanceScript'] as String?) ?? defaultMaintenanceScript;
        _suspendedScript = (m['suspendedScript'] as String?) ?? defaultSuspendedScript;
        final zones = (m['coveredZones'] as List?)?.cast<String>();
        if (zones != null) _coveredZones = List.of(zones);
      } catch (_) {
        // Corrupt config — fall back to defaults.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final m = {
      'accountId': _accountId,
      'kvNamespaceId': _kvNamespaceId,
      'maintenanceScript': _maintenanceScript,
      'suspendedScript': _suspendedScript,
      'coveredZones': _coveredZones,
    };
    await _storage.write(key: _kStoreKey, value: jsonEncode(m));
    notifyListeners();
  }

  Future<void> setAccountId(String v) async {
    _accountId = v.trim();
    await _persist();
  }

  Future<void> setKvNamespaceId(String v) async {
    _kvNamespaceId = v.trim();
    await _persist();
  }

  Future<void> setMaintenanceScript(String v) async {
    _maintenanceScript = v.trim();
    await _persist();
  }

  Future<void> setSuspendedScript(String v) async {
    _suspendedScript = v.trim();
    await _persist();
  }

  Future<void> setCoveredZones(List<String> zones) async {
    _coveredZones = zones.map((z) => z.trim().toLowerCase()).where((z) => z.isNotEmpty).toList();
    await _persist();
  }

  Future<void> addCoveredZone(String zone) async {
    final z = zone.trim().toLowerCase();
    if (z.isEmpty || _coveredZones.contains(z)) return;
    _coveredZones = [..._coveredZones, z];
    await _persist();
  }

  Future<void> removeCoveredZone(String zone) async {
    _coveredZones = _coveredZones.where((z) => z != zone).toList();
    await _persist();
  }

  Future<void> resetToDefaults() async {
    _accountId = defaultAccountId;
    _kvNamespaceId = defaultKvNamespaceId;
    _maintenanceScript = defaultMaintenanceScript;
    _suspendedScript = defaultSuspendedScript;
    _coveredZones = List.of(defaultCoveredZones);
    await _persist();
  }
}
