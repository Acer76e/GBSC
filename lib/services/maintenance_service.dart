import '../models/worker_route.dart';
import '../models/zone.dart';
import 'cloudflare_api.dart';
import 'maintenance_config.dart';

enum MaintenanceState { off, on, partial, unknown }

class ZoneMaintenanceStatus {
  final String domain;
  final Zone? zone;
  final bool hasMaintenanceRoutes;
  final String? error;

  ZoneMaintenanceStatus({
    required this.domain,
    this.zone,
    this.hasMaintenanceRoutes = false,
    this.error,
  });
}

class MaintenanceOverview {
  final MaintenanceState state;
  final List<ZoneMaintenanceStatus> perZone;
  final String? bypassIpsRaw;
  final String? updatesUrl;

  MaintenanceOverview({
    required this.state,
    required this.perZone,
    this.bypassIpsRaw,
    this.updatesUrl,
  });

  int get coveredCount => perZone.where((s) => s.hasMaintenanceRoutes).length;
  int get totalResolved => perZone.where((s) => s.zone != null).length;
  List<String> get bypassIps => (bypassIpsRaw ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

class ZoneRouteStatus {
  final bool inMaintenance;
  final bool suspended;
  final Set<String> otherScripts;

  ZoneRouteStatus({
    required this.inMaintenance,
    required this.suspended,
    required this.otherScripts,
  });
}

class ToggleResult {
  final List<String> succeeded;
  final List<({String domain, String message})> failed;
  final List<String> skipped;

  ToggleResult({
    required this.succeeded,
    required this.failed,
    required this.skipped,
  });

  bool get hasFailures => failed.isNotEmpty;
}

class MaintenanceService {
  final CloudflareApi api;
  final MaintenanceConfig config;

  MaintenanceService({required this.api, required this.config});

  String _patternFor(String domain) => '$domain/*';
  String _wwwPatternFor(String domain) => 'www.$domain/*';

  Future<MaintenanceOverview> getOverview() async {
    // Parallelize zone+route lookups; Cloudflare's rate limit (1200/5min)
    // easily absorbs ~34 concurrent calls for the default 17 zones.
    final futures = config.coveredZones.map((domain) async {
      try {
        final zone = await api.findZoneByName(domain);
        if (zone == null) {
          return ZoneMaintenanceStatus(domain: domain, error: 'Zone not in account');
        }
        final routes = await api.listWorkerRoutes(zone.id);
        final has = routes.any((r) => r.script == config.maintenanceScript);
        return ZoneMaintenanceStatus(
          domain: domain,
          zone: zone,
          hasMaintenanceRoutes: has,
        );
      } catch (e) {
        return ZoneMaintenanceStatus(domain: domain, error: e.toString());
      }
    });
    final results = await Future.wait(futures);

    String? bypassIps;
    String? updatesUrl;
    try {
      bypassIps = await api.getKvValue(
        config.accountId,
        config.kvNamespaceId,
        MaintenanceConfig.kvBypassIpsKey,
      );
    } catch (_) {}
    try {
      updatesUrl = await api.getKvValue(
        config.accountId,
        config.kvNamespaceId,
        MaintenanceConfig.kvUpdatesUrlKey,
      );
    } catch (_) {}

    final resolved = results.where((r) => r.zone != null).toList();
    MaintenanceState state;
    if (resolved.isEmpty) {
      state = MaintenanceState.unknown;
    } else {
      final on = resolved.where((r) => r.hasMaintenanceRoutes).length;
      if (on == 0) {
        state = MaintenanceState.off;
      } else if (on == resolved.length) {
        state = MaintenanceState.on;
      } else {
        state = MaintenanceState.partial;
      }
    }

    return MaintenanceOverview(
      state: state,
      perZone: results,
      bypassIpsRaw: bypassIps,
      updatesUrl: updatesUrl,
    );
  }

  Future<ToggleResult> enableAll() async {
    final succeeded = <String>[];
    final failed = <({String domain, String message})>[];
    final skipped = <String>[];

    for (final domain in config.coveredZones) {
      try {
        final zone = await api.findZoneByName(domain);
        if (zone == null) {
          failed.add((domain: domain, message: 'Zone not in account'));
          continue;
        }
        final existing = await api.listWorkerRoutes(zone.id);
        final wantedPatterns = [_patternFor(domain), _wwwPatternFor(domain)];
        bool didAnything = false;
        for (final pattern in wantedPatterns) {
          final match = existing.where((r) => r.pattern == pattern).toList();
          if (match.any((r) => r.script == config.maintenanceScript)) {
            continue; // already attached
          }
          if (match.any((r) => r.script != config.maintenanceScript)) {
            skipped.add('$domain — $pattern already attached to ${match.first.script}');
            continue;
          }
          await api.createWorkerRoute(
            zone.id,
            pattern: pattern,
            script: config.maintenanceScript,
          );
          didAnything = true;
        }
        if (didAnything || existing.any((r) => r.script == config.maintenanceScript)) {
          succeeded.add(domain);
        }
      } catch (e) {
        failed.add((domain: domain, message: e.toString()));
      }
    }

    return ToggleResult(succeeded: succeeded, failed: failed, skipped: skipped);
  }

  Future<ToggleResult> disableAll() async {
    final succeeded = <String>[];
    final failed = <({String domain, String message})>[];

    for (final domain in config.coveredZones) {
      try {
        final zone = await api.findZoneByName(domain);
        if (zone == null) {
          failed.add((domain: domain, message: 'Zone not in account'));
          continue;
        }
        final existing = await api.listWorkerRoutes(zone.id);
        final toDelete =
            existing.where((r) => r.script == config.maintenanceScript).toList();
        for (final r in toDelete) {
          await api.deleteWorkerRoute(zone.id, r.id);
        }
        succeeded.add(domain);
      } catch (e) {
        failed.add((domain: domain, message: e.toString()));
      }
    }

    return ToggleResult(succeeded: succeeded, failed: failed, skipped: const []);
  }

  Future<void> setBypassIps(List<String> ips) async {
    final value = ips.map((s) => s.trim()).where((s) => s.isNotEmpty).join(',');
    await api.putKvValue(
      config.accountId,
      config.kvNamespaceId,
      MaintenanceConfig.kvBypassIpsKey,
      value,
    );
  }

  Future<void> setUpdatesUrl(String url) async {
    final trimmed = url.trim();
    if (!trimmed.startsWith('https://')) {
      throw ArgumentError('URL must start with https://');
    }
    await api.putKvValue(
      config.accountId,
      config.kvNamespaceId,
      MaintenanceConfig.kvUpdatesUrlKey,
      trimmed,
    );
  }

  // ── Per-zone status / toggles ─────────────────────────────────────────

  Future<ZoneRouteStatus> getZoneRouteStatus(String zoneId) async {
    final routes = await api.listWorkerRoutes(zoneId);
    final hasMaintenance = routes.any((r) => r.script == config.maintenanceScript);
    final hasSuspended = routes.any((r) => r.script == config.suspendedScript);
    final otherScripts = routes
        .where((r) =>
            r.script != null &&
            r.script != config.maintenanceScript &&
            r.script != config.suspendedScript)
        .map((r) => r.script!)
        .toSet();
    return ZoneRouteStatus(
      inMaintenance: hasMaintenance,
      suspended: hasSuspended,
      otherScripts: otherScripts,
    );
  }

  // Backwards-compatible wrapper used by older callers.
  Future<({bool suspended, bool conflict, String? conflictScript})>
      getSuspendedStatus(String zoneId) async {
    final s = await getZoneRouteStatus(zoneId);
    // A "conflict" here is anything that would block setting the suspended
    // worker on the same pattern — i.e. another worker (including the
    // maintenance worker) already attached.
    final blockers = {
      ...s.otherScripts,
      if (s.inMaintenance) config.maintenanceScript,
    };
    return (
      suspended: s.suspended,
      conflict: blockers.isNotEmpty,
      conflictScript: blockers.isEmpty ? null : blockers.first,
    );
  }

  Future<({bool ok, List<String> skipped})> enableMaintenanceOn(
    String zoneId,
    String domain,
  ) async {
    final existing = await api.listWorkerRoutes(zoneId);
    final wantedPatterns = [_patternFor(domain), _wwwPatternFor(domain)];
    final skipped = <String>[];
    for (final pattern in wantedPatterns) {
      final match = existing.where((r) => r.pattern == pattern).toList();
      if (match.any((r) => r.script == config.maintenanceScript)) continue;
      if (match.any((r) => r.script != config.maintenanceScript)) {
        skipped.add('$pattern already attached to ${match.first.script}');
        continue;
      }
      await api.createWorkerRoute(
        zoneId,
        pattern: pattern,
        script: config.maintenanceScript,
      );
    }
    return (ok: true, skipped: skipped);
  }

  Future<void> disableMaintenanceOn(String zoneId) async {
    final existing = await api.listWorkerRoutes(zoneId);
    final toDelete =
        existing.where((r) => r.script == config.maintenanceScript).toList();
    for (final r in toDelete) {
      await api.deleteWorkerRoute(zoneId, r.id);
    }
  }

  // ── Per-domain suspension ─────────────────────────────────────────────

  Future<({bool ok, List<String> skipped})> suspend(String zoneId, String domain) async {
    final existing = await api.listWorkerRoutes(zoneId);
    final wantedPatterns = [_patternFor(domain), _wwwPatternFor(domain)];
    final skipped = <String>[];
    for (final pattern in wantedPatterns) {
      final match = existing.where((r) => r.pattern == pattern).toList();
      if (match.any((r) => r.script == config.suspendedScript)) continue;
      if (match.any((r) => r.script != config.suspendedScript)) {
        skipped.add('$pattern already attached to ${match.first.script}');
        continue;
      }
      await api.createWorkerRoute(zoneId, pattern: pattern, script: config.suspendedScript);
    }
    return (ok: true, skipped: skipped);
  }

  Future<void> unsuspend(String zoneId) async {
    final existing = await api.listWorkerRoutes(zoneId);
    final toDelete = existing.where((r) => r.script == config.suspendedScript).toList();
    for (final r in toDelete) {
      await api.deleteWorkerRoute(zoneId, r.id);
    }
  }
}
