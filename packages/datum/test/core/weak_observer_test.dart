import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';
import '../mocks/forward_bulk_writes.dart';

class MockedLocalAdapter<T extends DatumEntityInterface> extends Mock with ForwardBulkWrites<T> implements LocalAdapter<T> {}

class MockedRemoteAdapter<T extends DatumEntityInterface> extends Mock implements RemoteAdapter<T> {}

void main() {
  group('DatumManager Auto-Sync Streams', () {
    late DatumManager<TestEntity> manager;
    late MockedLocalAdapter<TestEntity> localAdapter;
    late MockedRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    setUp(() async {
      localAdapter = MockedLocalAdapter<TestEntity>();
      remoteAdapter = MockedRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      // Apply default stubs
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
      when(() => localAdapter.getAllUserIds()).thenAnswer((_) async => []);

      manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
      );

      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('watchNextSyncTime emits null when no auto-sync is scheduled', () async {
      final stream = manager.watchNextSyncTime;
      final values = <DateTime?>[];

      final subscription = stream.listen(values.add);

      // BehaviorSubject emits current value immediately
      await Future.delayed(const Duration(milliseconds: 10));

      expect(values, hasLength(1));
      expect(values.first, isNull);

      await subscription.cancel();
    });

    test('watchNextSyncTime emits next sync time when auto-sync is started', () async {
      final stream = manager.watchNextSyncTime;
      final values = <DateTime?>[];

      final subscription = stream.listen(values.add);

      // Start auto-sync
      manager.startAutoSync('user1');

      // Wait for the stream to emit
      await Future.delayed(const Duration(milliseconds: 50));

      expect(values.length, greaterThanOrEqualTo(2)); // Initial null + sync time
      expect(values.last, isNotNull);
      expect(values.last!.isAfter(DateTime.now()), isTrue);

      await subscription.cancel();
    });

    test('watchNextSyncTime emits null when auto-sync is stopped', () async {
      final stream = manager.watchNextSyncTime;
      final values = <DateTime?>[];

      final subscription = stream.listen(values.add);

      // Start auto-sync
      manager.startAutoSync('user1');
      await Future.delayed(const Duration(milliseconds: 50));

      // Stop auto-sync
      manager.stopAutoSync(userId: 'user1');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(values.length, greaterThanOrEqualTo(2));
      expect(values.last, isNull);

      await subscription.cancel();
    });

    test('watchNextSyncDuration emits null when no auto-sync is scheduled', () async {
      final stream = manager.watchNextSyncDuration;
      final values = <Duration?>[];

      final subscription = stream.listen(values.add);

      // BehaviorSubject emits current value immediately
      await Future.delayed(const Duration(milliseconds: 10));

      expect(values, hasLength(1));
      expect(values.first, isNull);

      await subscription.cancel();
    });

    test('watchNextSyncDuration emits duration when auto-sync is scheduled', () async {
      final stream = manager.watchNextSyncDuration;
      final values = <Duration?>[];

      final subscription = stream.listen(values.add);

      // Start auto-sync
      manager.startAutoSync('user1');

      // Wait for emissions
      await Future.delayed(const Duration(milliseconds: 50));

      expect(values.length, greaterThanOrEqualTo(1));

      // First emission should be a positive duration
      final firstDuration = values.firstWhere((d) => d != null, orElse: () => null);
      expect(firstDuration, isNotNull);
      expect(firstDuration!.inMilliseconds, greaterThan(0));

      await subscription.cancel();
    });

    test('watchNextSyncDuration emits null when auto-sync is stopped', () async {
      final stream = manager.watchNextSyncDuration;
      final values = <Duration?>[];

      final subscription = stream.listen(values.add);

      // Start auto-sync
      manager.startAutoSync('user1');
      await Future.delayed(const Duration(milliseconds: 50));

      // Stop auto-sync
      manager.stopAutoSync(userId: 'user1');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(values.length, greaterThanOrEqualTo(2));
      expect(values.last, isNull);

      await subscription.cancel();
    });

    test('getNextSyncTime returns null when no auto-sync is scheduled', () async {
      final nextTime = await manager.getNextSyncTime();
      expect(nextTime, isNull);
    });

    test('getNextSyncTime returns future sync time when auto-sync is scheduled', () async {
      manager.startAutoSync('user1');

      final nextTime = await manager.getNextSyncTime();
      expect(nextTime, isNotNull);
      expect(nextTime!.isAfter(DateTime.now()), isTrue);
    });

    test('getNextSyncDuration returns null when no auto-sync is scheduled', () async {
      final duration = await manager.getNextSyncDuration();
      expect(duration, isNull);
    });

    test('getNextSyncDuration returns positive duration when auto-sync is scheduled', () async {
      manager.startAutoSync('user1');

      final duration = await manager.getNextSyncDuration();
      expect(duration, isNotNull);
      expect(duration!.inMilliseconds, greaterThan(0));
    });

    test('multiple users can have independent auto-sync schedules', () async {
      final stream1 = manager.watchNextSyncTime;
      final stream2 = manager.watchNextSyncTime;

      final values1 = <DateTime?>[];
      final values2 = <DateTime?>[];

      final sub1 = stream1.listen(values1.add);
      final sub2 = stream2.listen(values2.add);

      // Start auto-sync for user1
      manager.startAutoSync('user1');
      await Future.delayed(const Duration(milliseconds: 50));

      // Start auto-sync for user2
      manager.startAutoSync('user2');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(values1.length, greaterThanOrEqualTo(1));
      expect(values2.length, greaterThanOrEqualTo(1));

      // Both streams should emit the same values since they share the same subject
      expect(values1.last, equals(values2.last));

      await sub1.cancel();
      await sub2.cancel();
    });

    test('onNextSyncTimeChanged emits null when no auto-sync is scheduled', () async {
      final stream = manager.onNextSyncTimeChanged;
      final values = <DateTime?>[];

      final subscription = stream.listen(values.add);

      // BehaviorSubject emits current value immediately
      await Future.delayed(const Duration(milliseconds: 10));

      expect(values, hasLength(1));
      expect(values.first, isNull);

      await subscription.cancel();
    });

    test('onNextSyncTimeChanged emits next sync time when auto-sync is started', () async {
      final stream = manager.onNextSyncTimeChanged;
      final values = <DateTime?>[];

      final subscription = stream.listen(values.add);

      // Start auto-sync
      manager.startAutoSync('user1');

      // Wait for the stream to emit
      await Future.delayed(const Duration(milliseconds: 50));

      expect(values.length, greaterThanOrEqualTo(2)); // Initial null + sync time
      expect(values.last, isNotNull);
      expect(values.last!.isAfter(DateTime.now()), isTrue);

      await subscription.cancel();
    });

    test('onNextSyncTimeChanged emits null when auto-sync is stopped', () async {
      final stream = manager.onNextSyncTimeChanged;
      final values = <DateTime?>[];

      final subscription = stream.listen(values.add);

      // Start auto-sync
      manager.startAutoSync('user1');
      await Future.delayed(const Duration(milliseconds: 50));

      // Stop auto-sync
      manager.stopAutoSync(userId: 'user1');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(values.length, greaterThanOrEqualTo(2));
      expect(values.last, isNull);

      await subscription.cancel();
    });

    test('onNextSyncTimeChanged is equivalent to watchNextSyncTime', () async {
      final stream1 = manager.watchNextSyncTime;
      final stream2 = manager.onNextSyncTimeChanged;

      final values1 = <DateTime?>[];
      final values2 = <DateTime?>[];

      final sub1 = stream1.listen(values1.add);
      final sub2 = stream2.listen(values2.add);

      // Start auto-sync
      manager.startAutoSync('user1');
      await Future.delayed(const Duration(milliseconds: 50));

      // Stop auto-sync
      manager.stopAutoSync(userId: 'user1');
      await Future.delayed(const Duration(milliseconds: 50));

      // Both streams should emit the same values
      expect(values1, equals(values2));

      await sub1.cancel();
      await sub2.cancel();
    });
  });
}
