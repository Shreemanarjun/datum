import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

/// A concrete implementation of [DatumIndexConfig] for testing purposes.
class _TestIndexConfig extends DatumIndexConfig<TestEntity> {
  @override
  final List<String> indexedFields;

  @override
  final List<List<String>> compositeIndexes;

  _TestIndexConfig({
    this.indexedFields = const [],
    this.compositeIndexes = const [],
  });
}

/// A concrete implementation to test the default value of `compositeIndexes`.
class _TestIndexConfigWithDefaults extends DatumIndexConfig<TestEntity> {
  @override
  final List<String> indexedFields;

  _TestIndexConfigWithDefaults({required this.indexedFields});
}

void main() {
  group('DatumIndexConfig', () {
    test('indexedFields returns the provided list of fields', () {
      final config = _TestIndexConfig(indexedFields: ['name', 'modifiedAt']);
      expect(config.indexedFields, ['name', 'modifiedAt']);
    });

    test('compositeIndexes returns the provided list of composite indexes', () {
      final config = _TestIndexConfig(compositeIndexes: [
        ['userId', 'createdAt'],
        ['status', 'priority']
      ]);
      expect(config.compositeIndexes, [
        ['userId', 'createdAt'],
        ['status', 'priority']
      ]);
    });

    test('compositeIndexes returns an empty list by default', () {
      final config = _TestIndexConfigWithDefaults(indexedFields: ['name']);
      expect(config.compositeIndexes, isEmpty);
    });
  });
}
