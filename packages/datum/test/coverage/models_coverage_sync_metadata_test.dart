import 'package:datum/datum.dart';
import 'package:test/test.dart';

Matcher throwsFormatExceptionWith(String messageFragment) => throwsA(
      isA<FormatException>().having(
        (e) => e.message,
        'message',
        contains(messageFragment),
      ),
    );

void main() {
  group('DatumSyncMetadata.fromMap error handling', () {
    test('throws when the required userId field is missing', () {
      expect(
        () => DatumSyncMetadata.fromMap(const {}),
        throwsFormatExceptionWith('Required field "userId" is missing'),
      );
    });

    test('wraps all parse failures in a descriptive FormatException', () {
      expect(
        () => DatumSyncMetadata.fromMap(const {}),
        throwsFormatExceptionWith('Failed to parse DatumSyncMetadata'),
      );
    });

    test('throws for an unparsable date string', () {
      expect(
        () => DatumSyncMetadata.fromMap(const {
          'userId': 'user-1',
          'lastSyncTime': 'not-a-date',
        }),
        throwsFormatExceptionWith('Invalid date format for field'),
      );
    });

    test('throws when a date field is not a string', () {
      expect(
        () => DatumSyncMetadata.fromMap(const {
          'userId': 'user-1',
          'lastSyncTime': 12345,
        }),
        throwsFormatExceptionWith('Date field must be a string'),
      );
    });

    test('parses a valid devices map into DateTimes', () {
      final metadata = DatumSyncMetadata.fromMap(const {
        'userId': 'user-1',
        'devices': {
          'device-1': '2024-01-01T00:00:00.000Z',
          'device-2': '2024-06-15T12:30:00.000Z',
        },
      });

      expect(metadata.devices, hasLength(2));
      expect(metadata.devices!['device-1'], DateTime.utc(2024));
      expect(metadata.hasDeviceSynced('device-2'), isTrue);
      expect(metadata.getDeviceLastSync('device-2'), DateTime.utc(2024, 6, 15, 12, 30));
      expect(metadata.deviceCount, 2);
      expect(metadata.allDeviceIds, containsAll(['device-1', 'device-2']));
    });

    test('throws for an invalid date inside the devices map', () {
      expect(
        () => DatumSyncMetadata.fromMap(const {
          'userId': 'user-1',
          'devices': {'device-1': 'garbage'},
        }),
        throwsFormatExceptionWith('Invalid date format in devices map for key "device-1"'),
      );
    });

    test('throws when devices is not a map', () {
      expect(
        () => DatumSyncMetadata.fromMap(const {
          'userId': 'user-1',
          'devices': 'not-a-map',
        }),
        throwsFormatExceptionWith('Devices field must be a map'),
      );
    });

    test('throws for malformed entity counts entries', () {
      expect(
        () => DatumSyncMetadata.fromMap(const {
          'userId': 'user-1',
          'entityCounts': {'todos': 'not-a-map'},
        }),
        throwsFormatExceptionWith('Invalid entity counts format for key "todos"'),
      );
    });

    test('throws when entity counts is not a map', () {
      expect(
        () => DatumSyncMetadata.fromMap(const {
          'userId': 'user-1',
          'entityCounts': ['not', 'a', 'map'],
        }),
        throwsFormatExceptionWith('Entity counts field must be a map'),
      );
    });

    test('falls back to neverSynced for an unknown sync status string', () {
      final metadata = DatumSyncMetadata.fromMap(const {
        'userId': 'user-1',
        'syncStatus': 'definitely-not-a-status',
      });
      expect(metadata.syncStatus, SyncStatus.neverSynced);
    });

    test('throws when sync status is not a string', () {
      expect(
        () => DatumSyncMetadata.fromMap(const {
          'userId': 'user-1',
          'syncStatus': 42,
        }),
        throwsFormatExceptionWith('Sync status must be a string'),
      );
    });
  });

  group('DatumSyncMetadata lifecycle transitions', () {
    const base = DatumSyncMetadata(userId: 'user-1', deviceId: 'device-1');

    test('markSyncStarted moves to syncing and stamps lastSyncTime', () {
      final started = base.markSyncStarted();
      expect(started.syncStatus, SyncStatus.syncing);
      expect(started.isSyncing, isTrue);
      expect(started.lastSyncTime, isNotNull);
      expect(started.userId, 'user-1');
    });

    test('markSyncCompleted records success and the syncing device', () {
      const details = DatumEntitySyncDetails(count: 3, pendingChanges: 1);
      final completed = base.copyWith(retryCount: 4, conflictCount: 2).markSyncCompleted(
            dataHash: 'hash-1',
            entityCounts: const {'todos': details},
            serverTimestamp: DateTime.utc(2024, 2),
            syncDuration: 1500,
          );

      expect(completed.syncStatus, SyncStatus.synced);
      expect(completed.isLastSyncSuccessful, isTrue);
      expect(completed.lastSuccessfulSyncTime, isNotNull);
      expect(completed.dataHash, 'hash-1');
      expect(completed.entityCounts, {'todos': details});
      expect(completed.totalPendingChanges, 1);
      expect(completed.serverTimestamp, DateTime.utc(2024, 2));
      expect(completed.syncDuration, 1500);
      expect(completed.conflictCount, 0);
      expect(completed.retryCount, 0);
      // The completing device is recorded in the devices map.
      expect(completed.devices, contains('device-1'));
    });

    test('markSyncCompleted without a deviceId leaves devices empty', () {
      const noDevice = DatumSyncMetadata(userId: 'user-1');
      final completed = noDevice.markSyncCompleted();
      expect(completed.devices, isEmpty);
      expect(completed.syncStatus, SyncStatus.synced);
    });

    test('markSyncFailed increments the retry count by default', () {
      final failed = base.markSyncFailed(errorMessage: 'network down');
      expect(failed.syncStatus, SyncStatus.failed);
      expect(failed.errorMessage, 'network down');
      expect(failed.retryCount, 1);

      final failedAgain = failed.markSyncFailed(errorMessage: 'still down');
      expect(failedAgain.retryCount, 2);
    });

    test('markSyncFailed can skip the retry increment', () {
      final failed = base.markSyncFailed(errorMessage: 'fatal', incrementRetry: false);
      expect(failed.syncStatus, SyncStatus.failed);
      expect(failed.retryCount, 0);
    });

    test('markConflicts moves to conflict with the given count', () {
      final conflicted = base.markConflicts(3);
      expect(conflicted.syncStatus, SyncStatus.conflict);
      expect(conflicted.conflictCount, 3);
      expect(conflicted.hasConflicts, isTrue);
      expect(conflicted.isNeverSynced, isFalse);
    });
  });

  group('DatumSyncMetadata serialization', () {
    test('toMap serializes the devices map to UTC ISO strings', () {
      final metadata = DatumSyncMetadata(
        userId: 'user-1',
        deviceId: 'device-1',
        devices: {
          'device-1': DateTime.utc(2024, 3, 5, 10),
          'device-2': DateTime.utc(2024, 3, 6, 11, 30),
        },
      );

      final map = metadata.toMap();
      expect(map['devices'], {
        'device-1': '2024-03-05T10:00:00.000Z',
        'device-2': '2024-03-06T11:30:00.000Z',
      });
    });

    test('toMap -> fromMap round-trip preserves equality', () {
      final metadata = DatumSyncMetadata(
        userId: 'user-1',
        lastSyncTime: DateTime.utc(2024, 1, 2),
        lastSuccessfulSyncTime: DateTime.utc(2024, 1, 1),
        dataHash: 'abc',
        deviceId: 'device-1',
        devices: {'device-1': DateTime.utc(2024, 1, 2)},
        customMetadata: const {'k': 'v'},
        entityCounts: {
          'todos': DatumEntitySyncDetails(
            count: 2,
            hash: 'h',
            lastModified: DateTime.utc(2024),
            pendingChanges: 1,
          ),
        },
        syncStatus: SyncStatus.synced,
        syncVersion: 2,
        serverTimestamp: DateTime.utc(2024, 1, 3),
        conflictCount: 1,
        errorMessage: 'previous error',
        retryCount: 2,
        syncDuration: 900,
      );

      final restored = DatumSyncMetadata.fromMap(metadata.toMap());
      expect(restored, equals(metadata));
    });
  });
}
