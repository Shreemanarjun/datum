import 'package:datum/datum.dart';
import 'package:test/test.dart';

void main() {
  group('PNCounter', () {
    test('value equality is based on internal p/n state (props)', () {
      final a = const PNCounter().increment('r1', 2).decrement('r2');
      final b = const PNCounter().increment('r1', 2).decrement('r2');
      final c = const PNCounter().increment('r1', 3).decrement('r2');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString reports the current counter value', () {
      final counter = const PNCounter().increment('r1', 5).decrement('r2', 2);
      expect(counter.value, 3);
      expect(counter.toString(), 'PNCounter(value: 3)');
    });

    test('merge takes the per-replica maximum', () {
      final a = const PNCounter().increment('r1', 2);
      final b = const PNCounter().increment('r1', 5).decrement('r2');
      final merged = a.merge(b);
      expect(merged.value, 4);
      // Merge is commutative.
      expect(b.merge(a), equals(merged));
    });
  });

  group('ORSet', () {
    test('fromMap restores both add and remove sets', () {
      final map = {
        'add': {
          'apple': ['t1', 't2'],
          'banana': ['t3'],
        },
        'remove': {
          'apple': ['t1'],
        },
      };

      final set = ORSet<String>.fromMap(map, (raw) => raw as String);

      // 'apple' still visible: tag t2 was never removed.
      expect(set.value, {'apple', 'banana'});

      // Removing with all observed tags hides the element.
      final fullRemoveMap = {
        'add': {
          'apple': ['t1'],
        },
        'remove': {
          'apple': ['t1'],
        },
      };
      final removedSet = ORSet<String>.fromMap(fullRemoveMap, (raw) => raw as String);
      expect(removedSet.value, isEmpty);
    });

    test('toMap/fromMap round-trip preserves equality (props)', () {
      final original = const ORSet<String>().add('a', 't1').add('b', 't2').remove('a');
      final restored = ORSet<String>.fromMap(original.toMap(), (raw) => raw as String);

      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
      expect(restored.value, {'b'});
    });

    test('sets with different histories are not equal', () {
      final a = const ORSet<String>().add('x', 't1');
      final b = const ORSet<String>().add('x', 't2');
      expect(a, isNot(equals(b)));
    });
  });

  group('RgaList', () {
    test('isEmpty and idsInOrder on an empty list', () {
      const list = RgaList<String>(replicaId: 'a');
      expect(list.isEmpty, isTrue);
      expect(list.length, 0);
      expect(list.idsInOrder, isEmpty);
    });

    test('idsInOrder matches elementIdAt for visible elements', () {
      final list = const RgaList<String>(replicaId: 'a').insertAll(0, ['x', 'y', 'z']);
      expect(list.isEmpty, isFalse);
      expect(list.idsInOrder, ['a:1', 'a:2', 'a:3']);
      expect(list.idsInOrder, [
        list.elementIdAt(0),
        list.elementIdAt(1),
        list.elementIdAt(2),
      ]);
    });

    test('idsInOrder skips tombstoned elements', () {
      final list = const RgaList<String>(replicaId: 'a').insertAll(0, ['x', 'y', 'z']).removeAt(1);
      expect(list.value, ['x', 'z']);
      expect(list.idsInOrder, ['a:1', 'a:3']);
      expect(list.isEmpty, isFalse);
    });

    test('toString includes replicaId and visible value', () {
      final list = const RgaList<String>(replicaId: 'dev-a').insertAll(0, ['h', 'i']);
      expect(list.toString(), 'RgaList(replicaId: dev-a, value: [h, i])');
    });

    test('concurrent edits on two replicas converge after merge', () {
      var a = const RgaList<String>(replicaId: 'device-a').insertAll(0, ['h', 'i']);
      var b = RgaList<String>.fromMap(a.toMap(), (v) => v as String, replicaId: 'device-b');

      a = a.insert(2, '!');
      b = b.insert(0, '>');

      final mergedA = a.merge(b);
      final mergedB = b.merge(a);
      expect(mergedA.value.join(), mergedB.value.join());
      expect(mergedA.value.join(), '>hi!');
    });
  });

  group('RgaText', () {
    test('replicaId is exposed from the underlying list', () {
      final doc = RgaText(replicaId: 'device-a').insert(0, 'hello');
      expect(doc.replicaId, 'device-a');
      expect(doc.value, 'hello');
      expect(doc.length, 5);
    });

    test('documents with identical histories are equal (props)', () {
      final a = RgaText(replicaId: 'device-a').insert(0, 'hi');
      final b = RgaText(replicaId: 'device-a').insert(0, 'hi');
      final c = RgaText(replicaId: 'device-a').insert(0, 'ho');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString includes replicaId and current text', () {
      final doc = RgaText(replicaId: 'device-a').insert(0, 'hey');
      expect(doc.toString(), 'RgaText(replicaId: device-a, value: "hey")');
    });

    test('concurrent text edits converge after merge', () {
      var docA = RgaText(replicaId: 'device-a').insert(0, 'hello');
      var docB = RgaText.fromMap(docA.toMap(), replicaId: 'device-b');

      docA = docA.insert(5, ' world');
      docB = docB.delete(0, 1).insert(0, 'H');

      final merged = docA.merge(docB);
      expect(merged.value, docB.merge(docA).value);
      expect(merged.value, 'Hello world');
    });
  });
}
