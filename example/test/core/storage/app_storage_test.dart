import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:example/core/local_storage/app_storage.dart';
import 'package:example/core/local_storage/app_storage_pod.dart';

Object? errorOf(void Function() cb) {
  try {
    cb();
    return null;
  } catch (e) {
    return e;
  }
}

Future<void> main() async {
  group('App Storage Test', () {
    AppStorage appStorage = AppStorage(null);
    setUp(() async {
      await appStorage.init(isTest: true);
    });

    test('throw exception without intialization', () {
      final container = ProviderContainer();
      final exception = errorOf(() => container.read(appStorageProvider));
      expect(
        exception,
        isA<UnimplementedError>().having(
          (s) => s.message,
          'exception',
          equals('appBoxProvider is not overriden'),
        ),
      );
    });
    test('intiailize and check box have no data', () {
      final container = ProviderContainer(
        overrides: [appStorageProvider.overrideWithValue(appStorage)],
      );
      final storage = container.read(appStorageProvider);
      expect(storage.appBox?.values.isEmpty, true);
      expect(storage.appBox?.toMap(), equals({}));
    });
    test('store a value and check not null in the box', () async {
      final container = ProviderContainer(
        overrides: [appStorageProvider.overrideWithValue(appStorage)],
      );
      final storage = container.read(appStorageProvider);
      await storage.put(key: 'hello', value: 'world');
      expect(storage.appBox?.values.isEmpty, false);
      expect(storage.appBox?.toMap(), equals({'hello': 'world'}));
      expect(storage.get(key: 'hello'), isNotNull);
      expect(storage.get(key: 'hello'), equals('world'));
    });
    test('check cleardata and box should be null', () async {
      final container = ProviderContainer(
        overrides: [appStorageProvider.overrideWithValue(appStorage)],
      );
      final storage = container.read(appStorageProvider);
      await storage.put(key: 'hello', value: 'world');
      await storage.clearAllData();
      expect(storage.appBox?.values.isEmpty, true);
      expect(storage.appBox?.toMap(), equals({}));
      expect(storage.get(key: 'hello'), isNull);
    });
  });
}
