import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

TestEntity _e(String id, {int value = 0}) => TestEntity(
      id: id,
      userId: 'u1',
      name: 'name-$id',
      value: value,
      modifiedAt: DateTime(2024),
      createdAt: DateTime(2024),
      version: 1,
    );

void main() {
  const hasher = DatumHashGenerator();

  group('hashEntitiesUnordered', () {
    test('is order-independent', () {
      final a = [_e('1'), _e('2'), _e('3')];
      final b = [_e('3'), _e('1'), _e('2')];
      expect(hasher.hashEntitiesUnordered(a), hasher.hashEntitiesUnordered(b));
    });

    test('changes when an entity changes', () {
      final a = [_e('1', value: 1), _e('2')];
      final b = [_e('1', value: 999), _e('2')];
      expect(hasher.hashEntitiesUnordered(a), isNot(hasher.hashEntitiesUnordered(b)));
    });

    test('empty set hashes to all-zero digest', () {
      expect(hasher.hashEntitiesUnordered(<TestEntity>[]), '0' * 64);
    });
  });

  group('datumEntityDigest', () {
    test('is independent of map key insertion order', () {
      final d1 = datumEntityDigest({'a': 1, 'b': 2, 'c': 3});
      final d2 = datumEntityDigest({'c': 3, 'a': 1, 'b': 2});
      expect(d1, d2);
    });
  });

  group('DatumRollingHash', () {
    test('addAll matches hashEntitiesUnordered', () {
      final entities = [_e('1'), _e('2'), _e('3')];
      final rolling = DatumRollingHash()..addAll(entities);
      expect(rolling.value, hasher.hashEntitiesUnordered(entities));
    });

    test('add then remove returns to empty', () {
      final rolling = DatumRollingHash();
      expect(rolling.isEmpty, isTrue);
      rolling.add(_e('1'));
      expect(rolling.isEmpty, isFalse);
      rolling.remove(_e('1'));
      expect(rolling.isEmpty, isTrue);
      expect(rolling.value, '0' * 64);
    });

    test('incremental update equals full recompute', () {
      final initial = [_e('1', value: 1), _e('2'), _e('3')];
      final rolling = DatumRollingHash()..addAll(initial);

      // Update entity '1' from value 1 -> 42 incrementally.
      final oldOne = _e('1', value: 1);
      final newOne = _e('1', value: 42);
      rolling
        ..remove(oldOne)
        ..add(newOne);

      final updated = [_e('1', value: 42), _e('2'), _e('3')];
      expect(rolling.value, hasher.hashEntitiesUnordered(updated));
    });

    test('reset clears the accumulator', () {
      final rolling = DatumRollingHash()..addAll([_e('1'), _e('2')]);
      expect(rolling.isEmpty, isFalse);
      rolling.reset();
      expect(rolling.isEmpty, isTrue);
    });
  });
}
