import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

/// A concrete implementation of LocalAdapter that uses mocktail for its methods.
/// It intentionally does NOT override `watchStorageSize` so we can test the
/// default implementation from the abstract class.
class TestableLocalAdapter extends Mock implements LocalAdapter<TestEntity> {
  // By not overriding watchStorageSize, calls to it will use the default
  // implementation in the `LocalAdapter` abstract class, which is what we want to test.
}

void main() {
  group('LocalAdapter.watchStorageSize default implementation', () {
    late TestableLocalAdapter adapter;
    late StreamController<DatumChangeDetail<TestEntity>> changeController;

    setUp(() {
      adapter = TestableLocalAdapter();
      changeController = StreamController<DatumChangeDetail<TestEntity>>.broadcast();

      // The default implementation of watchStorageSize calls the adapter's own methods.
      // We use `thenAnswer` to delegate the call to the real implementation on the abstract class.
      when(() => adapter.watchStorageSize(userId: any(named: 'userId'))).thenAnswer(
        (invocation) {
          final userId = invocation.namedArguments[#userId] as String?;
          return LocalAdapter.defaultWatchStorageSize(adapter, userId: userId);
        },
      );
    });

    tearDown(() {
      changeController.close();
    });

    test('emits initial size and then new size on relevant change', () async {
      // Arrange
      // Stub the dependencies of watchStorageSize
      when(() => adapter.changeStream()).thenAnswer((_) => changeController.stream);
      when(() => adapter.getStorageSize(userId: 'user1')).thenAnswer((_) async => 1024); // Initial size

      // Act
      final stream = adapter.watchStorageSize(userId: 'user1');

      // Assert: Expect the initial value first.
      final expectation = expectLater(
        stream,
        emitsInOrder([
          1024, // Initial emission
          2048, // Emission after change
        ]),
      );

      // Allow the stream to emit its initial value before we change the stub.
      await Future<void>.delayed(Duration.zero);

      // Arrange for the second emission
      when(() => adapter.getStorageSize(userId: 'user1')).thenAnswer((_) async => 2048); // New size

      // Act: Simulate a change event for the correct user.
      changeController.add(
        DatumChangeDetail(
          entityId: 'e1',
          userId: 'user1',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
        ),
      );

      await expectation; // Wait for the stream expectations to be met.
    });

    test('does not emit new size on irrelevant change (different user)', () async {
      // Arrange
      when(() => adapter.changeStream()).thenAnswer((_) => changeController.stream);
      when(() => adapter.getStorageSize(userId: 'user1')).thenAnswer((_) async => 1024);

      // Act & Assert
      final receivedValues = <int>[];
      final completer = Completer<void>();

      final stream = adapter.watchStorageSize(userId: 'user1');
      final subscription = stream.listen((size) {
        receivedValues.add(size);
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      // Wait for the initial value to be emitted.
      await completer.future;
      expect(receivedValues, [1024]);

      // Act: Simulate a change event for a DIFFERENT user.
      changeController.add(
        DatumChangeDetail(
          entityId: 'e2',
          userId: 'user2', // Irrelevant user
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
        ),
      );

      // Give a small delay to ensure no new events are (incorrectly) processed.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Assert: No new values should have been added.
      expect(receivedValues, [1024]);

      await subscription.cancel();
    });

    test('returns a stream with 0 if changeStream is null', () async {
      // Arrange
      // Stub changeStream to return null, simulating an adapter that doesn't support it.
      when(() => adapter.changeStream()).thenReturn(null);

      // Act
      final stream = adapter.watchStorageSize(userId: 'user1');

      // Assert: The stream should emit a single value, 0, and then close.
      await expectLater(stream, emitsInOrder([0, emitsDone]));
    });

    test('with null userId, emits new size on any change', () async {
      // Arrange
      // Stub the dependencies of watchStorageSize
      when(() => adapter.changeStream()).thenAnswer((_) => changeController.stream);
      // When userId is null, it should call getStorageSize with null.
      when(() => adapter.getStorageSize(userId: null)).thenAnswer((_) async => 4096); // Initial global size

      // Act
      final stream = adapter.watchStorageSize(userId: null);

      // Assert: Expect the initial value first.
      final expectation = expectLater(
        stream,
        emitsInOrder([
          4096, // Initial emission
          8192, // Emission after change
        ]),
      );

      // Allow the stream to emit its initial value before we change the stub.
      await Future<void>.delayed(Duration.zero);

      // Arrange for the second emission
      when(() => adapter.getStorageSize(userId: null)).thenAnswer((_) async => 8192); // New global size

      // Act: Simulate a change event for an arbitrary user.
      changeController.add(
        DatumChangeDetail(
          entityId: 'e-any',
          userId: 'any-user-id', // The specific user doesn't matter
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
        ),
      );

      await expectation; // Wait for the stream expectations to be met.
    });
  });
}
