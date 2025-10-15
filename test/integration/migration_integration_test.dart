import 'package:flutter_test/flutter_test.dart';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mock_connectivity_checker.dart';
import '../mocks/mock_adapters.dart';
import '../mocks/test_entity.dart';

// --- Test Migrations ---

/// Renames 'name' to 'title' and adds a 'priority' field.
class V1toV2 extends Migration {
  @override
  int get fromVersion => 1;
  @override
  int get toVersion => 2;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    final newData = Map<String, dynamic>.from(oldData);
    newData['title'] = newData.remove('name'); // Rename field
    newData['priority'] = 'medium'; // Add new field with default value
    return newData;
  }
}

/// Changes 'priority' from a string to an integer.
class V2toV3 extends Migration {
  @override
  int get fromVersion => 2;
  @override
  int get toVersion => 3;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    final newData = Map<String, dynamic>.from(oldData);
    switch (newData['priority']) {
      case 'high':
        newData['priority'] = 1;
      case 'medium':
        newData['priority'] = 2;
      default:
        newData['priority'] = 3;
    }
    return newData;
  }
}

/// A migration that is designed to fail for a specific entity to test rollbacks.
class FailingMigration extends Migration {
  @override
  int get fromVersion => 1;
  @override
  int get toVersion => 2;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> oldData) {
    if (oldData['id'] == 'entity2') {
      throw Exception('Simulated migration failure for entity2');
    }
    // Successfully migrate other entities
    final newData = Map<String, dynamic>.from(oldData);
    newData['title'] = newData.remove('name');
    return newData;
  }
}

void main() {
  group('Schema Migration Integration Tests', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    setUp(() {
      // The fromJson for TestEntity won't work for migrated data,
      // so we use a mock that can handle dynamic maps.
      localAdapter = MockLocalAdapter<TestEntity>(
        fromJson: (json) => TestEntity.fromJson(json),
      );
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();

      // Stub default connectivity behavior
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
    });

    setUpAll(() {
      registerFallbackValue(DatumQueryBuilder<TestEntity>().build());
    });

    (DatumManager<TestEntity>, Future<void>) createManager({
      required int schemaVersion,
      required List<Migration> migrations,
    }) {
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        datumConfig: DatumConfig(
          schemaVersion: schemaVersion,
          migrations: migrations,
        ),
      );
      return (manager, manager.initialize());
    }

    test('runs a single migration successfully (v1 -> v2)', () async {
      // 1. Setup: Pre-populate with V1 data and set stored version to 1.
      final v1Data = {
        'id': 'entity1',
        'userId': 'user1',
        'name': 'V1 Name', // Field to be renamed
        'value': 10,
        'modifiedAt': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'version': 1,
      };
      await localAdapter.overwriteAllRawData([v1Data]);
      await localAdapter.setStoredSchemaVersion(1);

      // 2. Act: Initialize manager with target version 2 and the V1->V2 migration.
      await createManager(schemaVersion: 2, migrations: [V1toV2()]).$2;

      // 3. Assert: Check that data is now in V2 format.
      final migratedData = await localAdapter.getAllRawData();
      expect(migratedData, hasLength(1));
      expect(migratedData.first['name'], isNull); // 'name' field is gone
      expect(migratedData.first['title'], 'V1 Name'); // 'title' field exists
      expect(migratedData.first['priority'], 'medium'); // 'priority' was added

      // Verify schema version was updated in the adapter.
      final storedVersion = await localAdapter.getStoredSchemaVersion();
      expect(storedVersion, 2);
    });

    test('runs a multi-step migration successfully (v1 -> v3)', () async {
      // 1. Setup: Pre-populate with V1 data and set stored version to 1.
      final v1Data = {
        'id': 'entity1',
        'userId': 'user1',
        'name': 'V1 Name',
        'value': 10,
        'modifiedAt': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'version': 1,
      };
      await localAdapter.overwriteAllRawData([v1Data]);
      await localAdapter.setStoredSchemaVersion(1);

      // 2. Act: Initialize with target version 3 and both migrations.
      await createManager(
        schemaVersion: 3,
        migrations: [V1toV2(), V2toV3()],
      ).$2;

      // 3. Assert: Check that data is now in V3 format.
      final migratedData = await localAdapter.getAllRawData();
      expect(migratedData, hasLength(1));
      expect(migratedData.first['name'], isNull);
      expect(migratedData.first['title'], 'V1 Name');
      expect(migratedData.first['priority'], 2); // 'medium' became 2

      final storedVersion = await localAdapter.getStoredSchemaVersion();
      expect(storedVersion, 3);
    });

    test('throws MigrationException if migration path is not found', () async {
      // 1. Setup: Stored version is 1.
      await localAdapter.setStoredSchemaVersion(1);

      // 2. Act & Assert: Try to migrate to version 3 with only a V2->V3 migration.
      // The manager will look for a migration starting from version 1 and fail.
      final (_, initializeFuture) = createManager(
        schemaVersion: 3,
        migrations: [V2toV3()],
      );
      expect(
        initializeFuture,
        throwsA(
          isA<MigrationException>().having(
            (e) => e.message,
            'message',
            contains(
              'Migration path broken: No migration found from version 1',
            ),
          ),
        ),
      );
    });

    test(
      'does not run migration if schema version is already current',
      () async {
        // 1. Setup: Pre-populate with V1 data and set stored version to 2.
        final v1Data = {'id': 'entity1', 'name': 'V1 Name'};
        await localAdapter.overwriteAllRawData([v1Data]);
        await localAdapter.setStoredSchemaVersion(2);

        // 2. Act: Initialize with target version 2.
        await createManager(schemaVersion: 2, migrations: [V1toV2()]).$2;

        // 3. Assert: Check that data was NOT migrated.
        final rawData = await localAdapter.getAllRawData();
        expect(rawData.first['name'], 'V1 Name'); // Still has 'name'
        expect(rawData.first['title'], isNull); // Does not have 'title'

        final storedVersion = await localAdapter.getStoredSchemaVersion();
        expect(storedVersion, 2);
      },
    );

    test('onMigrationError callback is invoked on migration failure', () async {
      // 1. Arrange: Setup a scenario for failure (missing migration path from v1).
      await localAdapter.setStoredSchemaVersion(1);

      var callbackWasCalled = false;
      Object? capturedError;

      Future<void> errorHandler(Object error, StackTrace stack) async {
        callbackWasCalled = true;
        capturedError = error;
      }

      // 2. Act: Create a manager with the error handler and initialize it.
      // This should NOT throw an exception because the handler catches it.
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        datumConfig: DatumConfig(
          schemaVersion: 3, // Target version that cannot be reached
          migrations: [V2toV3()], // Missing V1->V2 migration
          onMigrationError: errorHandler,
        ),
      );
      await manager.initialize();

      // 3. Assert: Verify the callback was called with the correct error.
      expect(
        callbackWasCalled,
        isTrue,
        reason: 'onMigrationError should have been called.',
      );
      expect(capturedError, isA<MigrationException>());
      // Use a `having` matcher for a combined type and property check.
      expect(
        capturedError,
        isA<MigrationException>().having(
          (e) => e.message,
          'message',
          contains('Migration path broken'),
        ),
      );
    });

    test('rolls back changes if a migration fails mid-process', () async {
      // 1. Arrange: Setup with two entities and a migration that will fail on the second one.
      final v1Data1 = {
        'id': 'entity1',
        'userId': 'user1',
        'name': 'Will Succeed',
        'modifiedAt': DateTime.now().toIso8601String(),
      };
      final v1Data2 = {
        'id': 'entity2',
        'userId': 'user1',
        'name': 'Will Fail',
        'modifiedAt': DateTime.now().toIso8601String(),
      };
      final originalData = [v1Data1, v1Data2];
      await localAdapter.overwriteAllRawData(originalData);
      await localAdapter.setStoredSchemaVersion(1);

      // 2. Act & Assert: Attempt to run the failing migration.
      final (_, initializeFuture) = createManager(
        schemaVersion: 2,
        migrations: [FailingMigration()],
      );

      // The initialization should throw the exception from the migration.
      await expectLater(
        initializeFuture,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Simulated migration failure for entity2'),
          ),
        ),
      );

      // 3. Assert: Verify that the database state was rolled back.
      // The schema version should NOT have been updated.
      final storedVersion = await localAdapter.getStoredSchemaVersion();
      expect(storedVersion, 1, reason: 'Schema version should be rolled back');

      // The data should be identical to the original data.
      final currentData = await localAdapter.getAllRawData();
      expect(currentData, orderedEquals(originalData));
    });

    test('runs migration successfully on an empty database', () async {
      // 1. Arrange: Set the stored version to 1, but don't add any data.
      await localAdapter.setStoredSchemaVersion(1);

      // 2. Act: Initialize manager with a migration path.
      await createManager(schemaVersion: 2, migrations: [V1toV2()]).$2;

      // 3. Assert: The schema version should be updated, and no errors thrown.
      final storedVersion = await localAdapter.getStoredSchemaVersion();
      expect(storedVersion, 2);

      // Verify that overwriteAllRawData was called with an empty list,
      // ensuring the migration logic for empty data is correct.
      final capturedData = await localAdapter.getAllRawData();
      expect(capturedData, isEmpty);
    });
  });
}
