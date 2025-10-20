import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

// A concrete implementation to test the default methods.
class TestObserver extends DatumObserver<TestEntity> {}

class TestGlobalObserver extends GlobalDatumObserver {}

void main() {
  group('DatumObserver', () {
    late TestObserver observer;

    setUp(() {
      observer = TestObserver();
    });

    test('default method implementations do not throw', () {
      final entity = TestEntity.create('e1', 'u1', 'Test');
      final resolution = DatumConflictResolution<TestEntity>.abort('test');
      final context = DatumConflictContext(
        userId: 'u1',
        entityId: 'e1',
        type: DatumConflictType.bothModified,
        detectedAt: DateTime.now(),
      );
      final syncResult = DatumSyncResult<TestEntity>.skipped('u1', 0);
      final switchResult = DatumUserSwitchResult.success(newUserId: 'u2');

      expect(() => observer.onCreateStart(entity), returnsNormally);
      expect(() => observer.onCreateEnd(entity), returnsNormally);
      expect(() => observer.onUpdateStart(entity), returnsNormally);
      expect(() => observer.onUpdateEnd(entity), returnsNormally);
      expect(() => observer.onDeleteStart('e1'), returnsNormally);
      expect(() => observer.onDeleteEnd('e1', success: true), returnsNormally);
      expect(() => observer.onSyncStart(), returnsNormally);
      expect(() => observer.onSyncEnd(syncResult), returnsNormally);
      expect(
        () => observer.onConflictDetected(entity, entity, context),
        returnsNormally,
      );
      expect(() => observer.onConflictResolved(resolution), returnsNormally);
      expect(
        () => observer.onUserSwitchStart(
          'u1',
          'u2',
          UserSwitchStrategy.keepLocal,
        ),
        returnsNormally,
      );
      expect(() => observer.onUserSwitchEnd(switchResult), returnsNormally);
    });
  });

  group('GlobalDatumObserver', () {
    late TestGlobalObserver observer;

    setUp(() {
      observer = TestGlobalObserver();
    });

    test('default method implementations do not throw', () {
      final entity = TestEntity.create('e1', 'u1', 'Test');
      final resolution = DatumConflictResolution<DatumEntity>.abort('test');
      final context = DatumConflictContext(
        userId: 'u1',
        entityId: 'e1',
        type: DatumConflictType.bothModified,
        detectedAt: DateTime.now(),
      );

      expect(() => observer.onCreateStart(entity), returnsNormally);
      expect(() => observer.onCreateEnd(entity), returnsNormally);
      expect(() => observer.onUpdateStart(entity), returnsNormally);
      expect(() => observer.onUpdateEnd(entity), returnsNormally);
      expect(
        () => observer.onConflictDetected(entity, entity, context),
        returnsNormally,
      );
      expect(() => observer.onConflictResolved(resolution), returnsNormally);
    });
  });
}
