import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/test_entity.dart';

void main() {
  group('DatumRegistration.capture', () {
    test('invokes the callback with the registration entity type', () {
      final registration = DatumRegistration<TestEntity>(
        localAdapter: MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
      );

      final captured = registration.capture(<E extends DatumEntityInterface>() => E);

      expect(captured, TestEntity);
    });

    test('returns the callback result', () {
      final registration = DatumRegistration<TestEntity>(
        localAdapter: MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
      );

      final name = registration.capture(<E extends DatumEntityInterface>() => E.toString());

      expect(name, 'TestEntity');
    });
  });
}
