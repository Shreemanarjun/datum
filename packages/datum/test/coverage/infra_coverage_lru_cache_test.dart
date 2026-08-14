import 'package:datum/source/core/utils/lru_cache.dart';
import 'package:test/test.dart';

void main() {
  group('LRUCache view accessors', () {
    late LRUCache<String, int> cache;

    setUp(() {
      cache = LRUCache<String, int>(3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
    });

    test('toMap returns an unmodifiable snapshot of the contents', () {
      final map = cache.toMap();

      expect(map, {'a': 1, 'b': 2, 'c': 3});
      expect(() => map['d'] = 4, throwsUnsupportedError);
      // Failed mutation of the snapshot never touches the cache.
      expect(cache.length, 3);
    });

    test('keys iterate from least to most recently used', () {
      // Touch 'a' so it becomes the most recently used.
      expect(cache.get('a'), 1);

      expect(cache.keys.toList(), ['b', 'c', 'a']);
    });

    test('values iterate in the same order as keys', () {
      expect(cache.get('a'), 1);

      expect(cache.values.toList(), [2, 3, 1]);
    });

    test('entries returns a list of key/value pairs in LRU order', () {
      final entries = cache.entries;

      expect(entries, hasLength(3));
      expect(entries.first.key, 'a');
      expect(entries.first.value, 1);
      expect(entries.last.key, 'c');
      expect(entries.last.value, 3);
    });

    test('view accessors reflect eviction of the least recently used entry', () {
      cache.put('d', 4); // Evicts 'a', the least recently used.

      expect(cache.keys.toList(), ['b', 'c', 'd']);
      expect(cache.toMap().containsKey('a'), isFalse);
      expect(cache.entries.map((e) => e.value).toList(), [2, 3, 4]);
    });
  });
}
