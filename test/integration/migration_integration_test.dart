import 'package:test/test.dart';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';

import '../core/auto_start_sync_test.dart';
import '../mocks/mock_connectivity_checker.dart';
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
    newData['priority'] = 'low'; // Add a field to make it a valid V2 entity
    return newData;
  }
}

// A mock migration class for testing failure scenarios.
class MockMigration extends Mock implements Migration {}

// Mocktail-based adapters for this test suite.
class MockLocalAdapter<T extends DatumEntity> extends Mock implements LocalAdapter<T> {}

class MockRemoteAdapter<T extends DatumEntity> extends Mock implements RemoteAdapter<T> {}

void main() {
  group('Schema Migration Integration Tests', () {
    late MockLocalAdapter<TestEntity> localAdapter;
    late MockRemoteAdapter<TestEntity> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;
    // Add a mock logger to verify error logging
    late MockLogger mockLogger;

    setUp(() {
      // The fromJson for TestEntity won't work for migrated data,
      // so we use a mock that can handle dynamic maps.
      localAdapter = MockLocalAdapter<TestEntity>();
      remoteAdapter = MockRemoteAdapter<TestEntity>();
      connectivityChecker = MockConnectivityChecker();
      mockLogger = MockLogger();

      // Stub default connectivity behavior
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      // Stub logger to prevent console noise and allow verification
      when(() => mockLogger.copyWith(enabled: any(named: 'enabled'))).thenReturn(mockLogger);
      when(() => mockLogger.info(any())).thenAnswer((_) {});
      when(() => mockLogger.error(any(), any())).thenAnswer((_) {});

      // Stub default behaviors for the mocktail-based local adapter
      when(() => localAdapter.initialize()).thenAnswer((_) async {});
      when(() => localAdapter.dispose()).thenAnswer((_) async {});
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 0);
      when(() => localAdapter.setStoredSchemaVersion(any())).thenAnswer((_) async {});
      when(() => localAdapter.getAllRawData(userId: any(named: 'userId'))).thenAnswer((_) async => []);
      when(() => localAdapter.getAllRawData()).thenAnswer((_) async => []);
      when(() => localAdapter.overwriteAllRawData(any(), userId: any(named: 'userId'))).thenAnswer((_) async {});
      when(() => localAdapter.transaction<MigrationResult>(any())).thenAnswer((invocation) async {
        final action = invocation.positionalArguments.first as Future<MigrationResult> Function();
        try {
          return await action();
        } catch (e) {
          rethrow;
        }
      });

      // Stub remote adapter lifecycle methods
      when(() => remoteAdapter.initialize()).thenAnswer((_) async {});
      when(() => remoteAdapter.dispose()).thenAnswer((_) async {});
    });

    setUpAll(() {
      registerFallbackValue(DatumQueryBuilder<TestEntity>().build());
      registerFallbackValue(StackTrace.empty);
      // Fallback for the transaction action parameter used with `any()`.
      // This ensures mocktail can match the function argument when stubbing transaction(...)
      // and avoids runtime null-type issues.
      registerFallbackValue(() async {});
    });

    (DatumManager<TestEntity>, Future<void>) createManager({
      required int schemaVersion,
      required List<Migration> migrations,
    }) {
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        // Pass the logger to the manager
        logger: mockLogger,
        datumConfig: DatumConfig(
          schemaVersion: schemaVersion,
          migrations: migrations,
          enableLogging: true, // Ensure logging is on
        ),
      );
      return (manager, manager.initialize());
    }

    test('runs a single migration successfully (v1 -> v2)', () async {
      // 1. Setup: Pre-populate with V1 data and set stored version to 1.
      final v1Data = <String, dynamic>{
        'id': 'entity1',
        'userId': 'user1',
        'name': 'V1 Name', // Field to be renamed
        'value': 10,
        'modifiedAt': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'version': 1,
      };
      // Stub both calls to getAllRawData (outside and inside the transaction).
      when(() => localAdapter.getAllRawData()).thenAnswer((_) async => [v1Data]);
      when(() => localAdapter.getAllRawData(userId: any(named: 'userId'))).thenAnswer((_) async => [v1Data]);
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 1);

      // 2. Act: Initialize manager with target version 2 and the V1->V2 migration.
      await createManager(schemaVersion: 2, migrations: [V1toV2()]).$2;

      // 3. Assert: Check that data is now in V2 format.
      final migratedData = verify(() => localAdapter.overwriteAllRawData(captureAny())).captured.last as List<Map<String, dynamic>>;
      expect(migratedData, hasLength(1));
      expect(migratedData.first['name'], isNull); // 'name' field is gone
      expect(migratedData.first['title'], 'V1 Name'); // 'title' field exists
      expect(migratedData.first['priority'], 'medium'); // 'priority' was added

      // Verify schema version was updated in the adapter.
      verify(() => localAdapter.setStoredSchemaVersion(2)).called(1);
    });

    test('runs a multi-step migration successfully (v1 -> v3)', () async {
      // 1. Setup: Pre-populate with V1 data and set stored version to 1.

      final v1Data = <String, dynamic>{
        'id': 'entity1',
        'userId': 'user1',
        'name': 'V1 Name',
        'value': 10,
        'modifiedAt': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'version': 1,
      };
      // Stub the first call to getAllRawData to return the V1 data.
      when(() => localAdapter.getAllRawData()).thenAnswer((_) async => [v1Data]);
      when(() => localAdapter.getAllRawData(userId: any(named: 'userId'))).thenAnswer((_) async => [v1Data]);

      // After the first migration, the data should be in V2 format.
      final v2Data = <String, dynamic>{
        'id': 'entity1',
        'userId': 'user1',
        'title': 'V1 Name',
        'value': 10,
        'modifiedAt': v1Data['modifiedAt'],
        'createdAt': v1Data['createdAt'],
        'version': 1,
        'priority': 'medium',
      };

      // Stub the second call to getAllRawData to return the V2 data.
      when(() => localAdapter.getAllRawData()).thenAnswer((_) async => [v2Data]);
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 1);

      // 2. Act: Initialize with target version 3 and both migrations.
      await createManager(
        schemaVersion: 3,
        migrations: [V1toV2(), V2toV3()],
      ).$2;
      // 3. Assert: Check that data is now in V3 format.
      final migratedData = verify(() => localAdapter.overwriteAllRawData(captureAny())).captured.last as List<Map<String, dynamic>>;
      expect(migratedData, hasLength(1));
      expect(migratedData.first['name'], isNull);
      expect(migratedData.first['title'], 'V1 Name');
      expect(migratedData.first['priority'], 2); // 'medium' became 2

      verify(() => localAdapter.setStoredSchemaVersion(3)).called(1);
    });

    test('throws MigrationException if migration path is not found', () async {
      // 1. Setup: Stored version is 1.
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 1);

      // 2. Act & Assert: Try to migrate to version 3 with only a V2->V3 migration.
      // The manager will look for a migration starting from version 1 and fail.
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        logger: mockLogger,
        datumConfig: DatumConfig(
          schemaVersion: 3,
          migrations: [V2toV3()],
        ),
      );

      try {
        await manager.initialize();
        fail('Expected MigrationException, but no exception was thrown.');
      } catch (e) {
        expect(
          e,
          isA<MigrationException>().having(
            (e) => e.message,
            'message',
            contains(
              'Migration path broken: No migration found from version 1',
            ),
          ),
        );
      }
    });

    test(
      'does not run migration if schema version is already current',
      () async {
        // 1. Setup: Pre-populate with V1 data and set stored version to 2.
        when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 2);

        // 2. Act: Initialize with target version 2.
        await createManager(schemaVersion: 2, migrations: [V1toV2()]).$2;

        // 3. Assert: Check that overwriteAllRawData was never called because
        // the migration executor should not have run.
        verifyNever(() => localAdapter.overwriteAllRawData(any()));
      },
    );

    test('onMigrationError callback is invoked on migration failure', () async {
      // 1. Arrange: Setup a scenario for failure (missing migration path from v1).
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 1);

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
        logger: mockLogger,
        datumConfig: DatumConfig(
          schemaVersion: 3, // Target version that cannot be reached
          migrations: [V2toV3()], // Missing V1->V2 migration
          onMigrationError: errorHandler,
        ),
        connectivity: connectivityChecker,
      );
      await manager.initialize();
      await Future.delayed(Duration.zero); // Allow the error handler to complete

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

      // Stub the local adapter to return the original data.
      when(() => localAdapter.getAllRawData(userId: any(named: 'userId'))).thenAnswer((_) async => originalData);
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 1);

      // 2. Act & Assert: Attempt to run the failing migration.
      final (manager, initFuture) = createManager(
        schemaVersion: 2,
        migrations: [FailingMigration()],
      );

      try {
        await initFuture;
        fail('Expected an exception, but none was thrown.');
      } catch (e) {
        expect(
          e,
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Simulated migration failure for entity2'),
          ),
        );
      }

      // 3. Assert: Verify that the database state was rolled back.
      // The migration executor should have restored the original schema version.
      verify(() => localAdapter.setStoredSchemaVersion(1)).called(1);

      // The executor should have overwritten the data with the original data.
      final capturedData = verify(() => localAdapter.overwriteAllRawData(captureAny())).captured;
      expect(capturedData.last, orderedEquals(originalData));
    });

    test('runs migration successfully on an empty database', () async {
      // 1. Arrange: Set the stored version to 1, but don't add any data.
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 1);
      // Stub the inner call to return an empty list.
      when(() => localAdapter.getAllRawData()).thenAnswer((_) async => []);
      when(() => localAdapter.getAllRawData(userId: any(named: 'userId'))).thenAnswer((_) async => []);

      // 2. Act: Initialize manager with a migration path.
      await createManager(schemaVersion: 2, migrations: [V1toV2()]).$2;

      // 3. Assert: The schema version should be updated, and no errors thrown.
      verify(() => localAdapter.setStoredSchemaVersion(2)).called(1);

      // Verify that overwriteAllRawData was called with an empty list,
      // ensuring the migration logic for empty data is correct.
      final capturedData = verify(() => localAdapter.overwriteAllRawData(captureAny())).captured.last as List<Map<String, dynamic>>;
      expect(capturedData, isEmpty);
    });

    test('re-throws original migration error if rollback also fails', () async {
      // 1. Arrange: Setup with data and a migration that will fail.
      final originalData = [
        {'id': 'entity1', 'name': 'Data'}
      ];
      final migrationException = Exception('Simulated migration failure');
      final rollbackException = Exception('Simulated rollback failure');

      // Stub the adapter's state and behavior.
      when(() => localAdapter.getStoredSchemaVersion()).thenAnswer((_) async => 1);
      when(() => localAdapter.getAllRawData(userId: any(named: 'userId'))).thenAnswer((_) async => originalData);

      // Stub the migration to throw an error.
      final mockMigration = MockMigration();
      when(() => mockMigration.fromVersion).thenReturn(1);
      when(() => mockMigration.toVersion).thenReturn(2);
      when(() => mockMigration.migrate(any())).thenThrow(migrationException);

      // Stub the restore operation to also fail.
      when(() => localAdapter.overwriteAllRawData(originalData)).thenThrow(rollbackException);

      // 2. Act: Initialize the manager.
      final manager = DatumManager<TestEntity>(
        localAdapter: localAdapter,
        remoteAdapter: remoteAdapter,
        connectivity: connectivityChecker,
        logger: mockLogger,
        datumConfig: DatumConfig(
          schemaVersion: 2,
          migrations: [mockMigration],
        ),
      );

      // 3. Assert: The initialization should throw the ORIGINAL migration error.
      try {
        await manager.initialize();
        fail('Expected an exception, but none was thrown.');
      } catch (e) {
        expect(e, same(migrationException));
      }

      // Verify that both errors were logged.
      verify(
        () => mockLogger.error(
          'Migration failed, attempting to restore original state: $migrationException',
          any(),
        ),
      ).called(1);
      verify(
        () => mockLogger.error(
          'Failed to restore original state after migration failure: $rollbackException',
          any(),
        ),
      ).called(1);
    });
  });
}