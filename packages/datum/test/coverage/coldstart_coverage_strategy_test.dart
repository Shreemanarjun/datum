import 'package:datum/datum.dart';
import 'package:test/test.dart';

void main() {
  group('ColdStartConfig', () {
    test('copyWith replaces the provided fields', () {
      const original = ColdStartConfig();

      final copy = original.copyWith(
        strategy: ColdStartStrategy.fullSync,
        maxDuration: const Duration(seconds: 42),
        syncThreshold: const Duration(minutes: 30),
        initialDelay: const Duration(milliseconds: 5),
      );

      expect(copy.strategy, ColdStartStrategy.fullSync);
      expect(copy.maxDuration, const Duration(seconds: 42));
      expect(copy.syncThreshold, const Duration(minutes: 30));
      expect(copy.initialDelay, const Duration(milliseconds: 5));

      // Original is unchanged.
      expect(original.strategy, ColdStartStrategy.adaptive);
      expect(original.maxDuration, const Duration(seconds: 15));
      expect(original.syncThreshold, const Duration(hours: 1));
      expect(original.initialDelay, const Duration(milliseconds: 500));
    });

    test('copyWith without arguments keeps the existing values', () {
      const original = ColdStartConfig(
        strategy: ColdStartStrategy.incremental,
        maxDuration: Duration(seconds: 3),
        syncThreshold: Duration(minutes: 7),
        initialDelay: Duration(milliseconds: 20),
      );

      final copy = original.copyWith();

      expect(copy.strategy, ColdStartStrategy.incremental);
      expect(copy.maxDuration, const Duration(seconds: 3));
      expect(copy.syncThreshold, const Duration(minutes: 7));
      expect(copy.initialDelay, const Duration(milliseconds: 20));
    });
  });

  group('ColdStartMetrics', () {
    test('constructor applies defaults', () {
      final start = DateTime(2024, 1, 1, 12);
      final metrics = ColdStartMetrics(startTime: start);

      expect(metrics.startTime, start);
      expect(metrics.endTime, isNull);
      expect(metrics.entitiesSynced, 0);
      expect(metrics.bytesTransferred, 0);
      expect(metrics.duration, isNull);
      expect(metrics.completed, isFalse);
      expect(metrics.failureReason, isNull);
    });

    test('copyWith replaces provided fields and preserves startTime', () {
      final start = DateTime(2024, 1, 1, 12);
      final end = DateTime(2024, 1, 1, 12, 0, 10);
      final metrics = ColdStartMetrics(startTime: start);

      final copy = metrics.copyWith(
        endTime: end,
        entitiesSynced: 12,
        bytesTransferred: 4096,
        duration: const Duration(seconds: 10),
        completed: true,
        failureReason: 'none really',
      );

      expect(copy.startTime, start);
      expect(copy.endTime, end);
      expect(copy.entitiesSynced, 12);
      expect(copy.bytesTransferred, 4096);
      expect(copy.duration, const Duration(seconds: 10));
      expect(copy.completed, isTrue);
      expect(copy.failureReason, 'none really');
    });

    test('copyWith without arguments keeps existing values', () {
      final start = DateTime(2023, 5, 5);
      final metrics = ColdStartMetrics(
        startTime: start,
        entitiesSynced: 3,
        bytesTransferred: 100,
        duration: const Duration(seconds: 4),
        completed: true,
        failureReason: 'partial',
      );

      final copy = metrics.copyWith();

      expect(copy.startTime, start);
      expect(copy.entitiesSynced, 3);
      expect(copy.bytesTransferred, 100);
      expect(copy.duration, const Duration(seconds: 4));
      expect(copy.completed, isTrue);
      expect(copy.failureReason, 'partial');
    });

    test('performanceScore is 0.0 when duration is null', () {
      final metrics = ColdStartMetrics(startTime: DateTime(2024));
      expect(metrics.performanceScore, 0.0);
    });

    test('performanceScore normalizes entities-per-second against 50/s', () {
      // 25 entities in 2 seconds = 12.5/s -> 12.5 / 50 = 0.25.
      final metrics = ColdStartMetrics(
        startTime: DateTime(2024),
        entitiesSynced: 25,
        duration: const Duration(seconds: 2),
      );
      expect(metrics.performanceScore, closeTo(0.25, 0.0001));
    });

    test('performanceScore clamps to 1.0 for very fast syncs', () {
      // 200 entities in 1 second = 200/s -> clamped to 1.0.
      final metrics = ColdStartMetrics(
        startTime: DateTime(2024),
        entitiesSynced: 200,
        duration: const Duration(seconds: 1),
      );
      expect(metrics.performanceScore, 1.0);
    });
  });
}
