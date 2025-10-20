import 'package:datum/source/core/health/datum_health.dart';
import 'package:test/test.dart';


void main() {
  group('DatumHealth', () {
    test('constructor provides correct default values', () {
      const health = DatumHealth();
      expect(health.status, DatumSyncHealth.healthy);
      expect(health.localAdapterStatus, AdapterHealthStatus.ok);
      expect(health.remoteAdapterStatus, AdapterHealthStatus.ok);
    });

    test('constructor sets all fields correctly', () {
      const health = DatumHealth(
        status: DatumSyncHealth.degraded,
        localAdapterStatus: AdapterHealthStatus.unhealthy,
        remoteAdapterStatus: AdapterHealthStatus.ok,
      );
      expect(health.status, DatumSyncHealth.degraded);
      expect(health.localAdapterStatus, AdapterHealthStatus.unhealthy);
      expect(health.remoteAdapterStatus, AdapterHealthStatus.ok);
    });

    test('supports value equality', () {
      const health1 = DatumHealth(
        status: DatumSyncHealth.degraded,
        localAdapterStatus: AdapterHealthStatus.unhealthy,
      );
      const health2 = DatumHealth(
        status: DatumSyncHealth.degraded,
        localAdapterStatus: AdapterHealthStatus.unhealthy,
      );
      const health3 = DatumHealth(status: DatumSyncHealth.error);

      expect(health1, equals(health2));
      expect(health1.hashCode, equals(health2.hashCode));
      expect(health1, isNot(equals(health3)));
    });

    test('props list is correct for equality check', () {
      const health = DatumHealth(
        status: DatumSyncHealth.syncing,
        localAdapterStatus: AdapterHealthStatus.ok,
        remoteAdapterStatus: AdapterHealthStatus.unhealthy,
      );
      expect(health.props, [
        DatumSyncHealth.syncing,
        AdapterHealthStatus.ok,
        AdapterHealthStatus.unhealthy,
      ]);
    });

    test('toString provides a useful representation from Equatable', () {
      const health = DatumHealth(status: DatumSyncHealth.offline);
      // Equatable generates a toString like: ClassName(prop1, prop2, ...)
      expect(health.toString(),
          'DatumHealth(DatumSyncHealth.offline, AdapterHealthStatus.ok, AdapterHealthStatus.ok)');
    });
  });
}
