import 'package:datum/source/config/config_presets.dart';
import 'package:test/test.dart';

void main() {
  group('DatumConfigPresets', () {
    test('development preset should have correct values', () {
      final config = DatumConfigPresets.development();

      expect(config.autoSyncInterval, const Duration(minutes: 5));
      expect(config.autoStartSync, true);
      expect(config.syncTimeout, const Duration(seconds: 30));
      expect(config.enableLogging, true);
      expect(config.enablePerformanceLogging, true);
      expect(config.performanceLogThreshold, const Duration(milliseconds: 50));
      expect(config.changeCacheDuration, const Duration(seconds: 10));
      expect(config.maxChangeCacheSize, 500);
      expect(config.changeCacheCleanupInterval, const Duration(seconds: 15));
      expect(config.remoteSyncBatchSize, 50);
      expect(config.remoteStreamBatchSize, 25);
      expect(config.progressEventFrequency, 25);
      expect(config.remoteEventDebounceTime, const Duration(milliseconds: 25));
    });

    test('production preset should have correct values', () {
      final config = DatumConfigPresets.production();

      expect(config.autoSyncInterval, const Duration(minutes: 30));
      expect(config.autoStartSync, true);
      expect(config.syncTimeout, const Duration(minutes: 5));
      expect(config.enableLogging, true);
      expect(config.enablePerformanceLogging, false);
      expect(config.changeCacheDuration, const Duration(minutes: 2));
      expect(config.maxChangeCacheSize, 2000);
      expect(config.changeCacheCleanupInterval, const Duration(minutes: 5));
      expect(config.remoteSyncBatchSize, 200);
      expect(config.remoteStreamBatchSize, 100);
      expect(config.progressEventFrequency, 100);
      expect(config.remoteEventDebounceTime, const Duration(milliseconds: 100));
    });

    test('highPerformance preset should have correct values', () {
      final config = DatumConfigPresets.highPerformance();

      expect(config.autoSyncInterval, const Duration(hours: 1));
      expect(config.autoStartSync, true);
      expect(config.syncTimeout, const Duration(minutes: 10));
      expect(config.enableLogging, false);
      expect(config.enablePerformanceLogging, false);
      expect(config.changeCacheDuration, const Duration(minutes: 5));
      expect(config.maxChangeCacheSize, 5000);
      expect(config.changeCacheCleanupInterval, const Duration(minutes: 15));
      expect(config.remoteSyncBatchSize, 500);
      expect(config.remoteStreamBatchSize, 250);
      expect(config.progressEventFrequency, 250);
      expect(config.remoteEventDebounceTime, const Duration(milliseconds: 200));
    });

    test('lowMemory preset should have correct values', () {
      final config = DatumConfigPresets.lowMemory();

      expect(config.autoSyncInterval, const Duration(hours: 2));
      expect(config.autoStartSync, false);
      expect(config.syncTimeout, const Duration(minutes: 2));
      expect(config.enableLogging, true);
      expect(config.enablePerformanceLogging, false);
      expect(config.changeCacheDuration, const Duration(seconds: 30));
      expect(config.maxChangeCacheSize, 200);
      expect(config.changeCacheCleanupInterval, const Duration(seconds: 30));
      expect(config.remoteSyncBatchSize, 25);
      expect(config.remoteStreamBatchSize, 10);
      expect(config.progressEventFrequency, 10);
      expect(config.remoteEventDebounceTime, const Duration(milliseconds: 10));
    });

    test('testing preset should have correct values', () {
      final config = DatumConfigPresets.testing();

      expect(config.autoSyncInterval, const Duration(hours: 1));
      expect(config.autoStartSync, false);
      expect(config.syncTimeout, const Duration(seconds: 10));
      expect(config.enableLogging, false);
      expect(config.enablePerformanceLogging, false);
      expect(config.changeCacheDuration, const Duration(seconds: 5));
      expect(config.maxChangeCacheSize, 50);
      expect(config.changeCacheCleanupInterval, const Duration(seconds: 5));
      expect(config.remoteSyncBatchSize, 10);
      expect(config.remoteStreamBatchSize, 5);
      expect(config.progressEventFrequency, 5);
      expect(config.remoteEventDebounceTime, const Duration(milliseconds: 1));
    });

    test('offlineFirst preset should have correct values', () {
      final config = DatumConfigPresets.offlineFirst();

      expect(config.autoSyncInterval, const Duration(minutes: 15));
      expect(config.autoStartSync, true);
      expect(config.syncTimeout, const Duration(minutes: 3));
      expect(config.enableLogging, true);
      expect(config.enablePerformanceLogging, false);
      expect(config.changeCacheDuration, const Duration(minutes: 10));
      expect(config.maxChangeCacheSize, 1000);
      expect(config.changeCacheCleanupInterval, const Duration(minutes: 10));
      expect(config.remoteSyncBatchSize, 100);
      expect(config.remoteStreamBatchSize, 50);
      expect(config.progressEventFrequency, 50);
      expect(config.remoteEventDebounceTime, const Duration(milliseconds: 50));
    });

    test('realTime preset should have correct values', () {
      final config = DatumConfigPresets.realTime();

      expect(config.autoSyncInterval, const Duration(seconds: 30));
      expect(config.autoStartSync, true);
      expect(config.syncTimeout, const Duration(seconds: 30));
      expect(config.enableLogging, true);
      expect(config.enablePerformanceLogging, false);
      expect(config.changeCacheDuration, const Duration(seconds: 10));
      expect(config.maxChangeCacheSize, 100);
      expect(config.changeCacheCleanupInterval, const Duration(seconds: 10));
      expect(config.remoteSyncBatchSize, 20);
      expect(config.remoteStreamBatchSize, 10);
      expect(config.progressEventFrequency, 10);
      expect(config.remoteEventDebounceTime, const Duration(milliseconds: 10));
    });

    test('custom preset should extend base configuration', () {
      final baseConfig = DatumConfigPresets.development();
      final customConfig = DatumConfigPresets.custom(
        base: baseConfig,
        autoSyncInterval: const Duration(minutes: 10),
        enableLogging: false,
        maxChangeCacheSize: 1000,
      );

      // Modified values
      expect(customConfig.autoSyncInterval, const Duration(minutes: 10));
      expect(customConfig.enableLogging, false);
      expect(customConfig.maxChangeCacheSize, 1000);

      // Unmodified values should remain from base
      expect(customConfig.autoStartSync, baseConfig.autoStartSync);
      expect(customConfig.remoteSyncBatchSize, baseConfig.remoteSyncBatchSize);
    });

    test('custom preset exposes the newer config flags', () {
      final config = DatumConfigPresets.custom(
        base: DatumConfigPresets.production(),
        enableQueryCache: true,
        detectRemoteDeletions: true,
        excludedSyncUserIds: {'system'},
      );
      expect(config.enableQueryCache, isTrue);
      expect(config.detectRemoteDeletions, isTrue);
      expect(config.excludedSyncUserIds, {'system'});
      // Defaults preserved when not overridden.
      expect(DatumConfigPresets.production().enableQueryCache, isFalse);
    });
  });
}
