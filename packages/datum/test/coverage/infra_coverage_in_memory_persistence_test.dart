import 'package:datum/datum.dart';
import 'package:datum/source/core/persistence/in_memory_datum_persistence.dart';
import 'package:test/test.dart';

/// Waits for pending microtasks/events so that async stream emissions settle.
Future<void> _pump([int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('InMemoryDatumPersistence listener notifications', () {
    late InMemoryDatumPersistence persistence;

    setUp(() async {
      persistence = InMemoryDatumPersistence();
      await persistence.initialize();
    });

    tearDown(() async {
      await persistence.dispose();
    });

    test('deleteSyncMetadata notifies active watchers with null', () async {
      final events = <DatumSyncMetadata?>[];
      final sub = persistence.watchSyncMetadata('user-1').listen(events.add);
      await _pump();
      expect(events, [isNull], reason: 'initial value is emitted');

      const metadata = DatumSyncMetadata(userId: 'user-1');
      await persistence.saveSyncMetadata('user-1', metadata);
      await _pump();
      expect(events.last, metadata);

      await persistence.deleteSyncMetadata('user-1');
      await _pump();

      expect(events, hasLength(3));
      expect(events.last, isNull);
      expect(await persistence.getSyncMetadata('user-1'), isNull);

      await sub.cancel();
    });

    test('deleteConfig notifies active watchers with null', () async {
      final events = <dynamic>[];
      final sub = persistence.watchConfig('theme').listen(events.add);
      await _pump();

      await persistence.saveConfig('theme', 'dark');
      await _pump();
      expect(events.last, 'dark');

      await persistence.deleteConfig('theme');
      await _pump();

      expect(events.last, isNull);
      expect(await persistence.getConfig('theme'), isNull);

      await sub.cancel();
    });

    test('deleteData notifies active watchers with null', () async {
      final events = <dynamic>[];
      final sub = persistence.watchData('cursor').listen(events.add);
      await _pump();

      await persistence.saveData('cursor', 42);
      await _pump();
      expect(events.last, 42);

      await persistence.deleteData('cursor');
      await _pump();

      expect(events.last, isNull);
      expect(await persistence.getData('cursor'), isNull);

      await sub.cancel();
    });

    test('clearUserData removes user state and notifies all its watchers', () async {
      await persistence.saveSyncMetadata(
        'user-1',
        const DatumSyncMetadata(userId: 'user-1'),
      );
      await persistence.saveConfig('config_user-1', 'a');
      await persistence.saveConfig('config_other', 'keep');
      await persistence.saveData('data_user-1', 1);
      await persistence.saveData('data_other', 2);

      final metadataEvents = <DatumSyncMetadata?>[];
      final configEvents = <dynamic>[];
      final dataEvents = <dynamic>[];
      final metadataSub = persistence.watchSyncMetadata('user-1').listen(metadataEvents.add);
      final configSub = persistence.watchConfig('config_user-1').listen(configEvents.add);
      final dataSub = persistence.watchData('data_user-1').listen(dataEvents.add);
      await _pump();

      expect(metadataEvents.last, isNotNull);
      expect(configEvents.last, 'a');
      expect(dataEvents.last, 1);

      await persistence.clearUserData('user-1');
      await _pump();

      expect(metadataEvents.last, isNull);
      expect(configEvents.last, isNull);
      expect(dataEvents.last, isNull);

      expect(await persistence.getSyncMetadata('user-1'), isNull);
      expect(await persistence.getConfig('config_user-1'), isNull);
      expect(await persistence.getData('data_user-1'), isNull);
      // Keys not containing the userId are retained.
      expect(await persistence.getConfig('config_other'), 'keep');
      expect(await persistence.getData('data_other'), 2);

      await metadataSub.cancel();
      await configSub.cancel();
      await dataSub.cancel();
    });

    test('clearAllData wipes everything and notifies every watcher', () async {
      await persistence.saveSyncMetadata(
        'user-1',
        const DatumSyncMetadata(userId: 'user-1'),
      );
      await persistence.saveConfig('some-config', 'x');
      await persistence.saveData('some-data', 'y');

      final metadataEvents = <DatumSyncMetadata?>[];
      final configEvents = <dynamic>[];
      final dataEvents = <dynamic>[];
      final metadataSub = persistence.watchSyncMetadata('user-1').listen(metadataEvents.add);
      final configSub = persistence.watchConfig('some-config').listen(configEvents.add);
      final dataSub = persistence.watchData('some-data').listen(dataEvents.add);
      await _pump();

      expect(metadataEvents.last, isNotNull);
      expect(configEvents.last, 'x');
      expect(dataEvents.last, 'y');

      await persistence.clearAllData();
      await _pump();

      expect(metadataEvents.last, isNull);
      expect(configEvents.last, isNull);
      expect(dataEvents.last, isNull);

      expect(await persistence.getAllUserIds(), isEmpty);
      expect(await persistence.getConfig('some-config'), isNull);
      expect(await persistence.getData('some-data'), isNull);

      await metadataSub.cancel();
      await configSub.cancel();
      await dataSub.cancel();
    });
  });
}
