import 'dart:math';

import 'package:datum/datum.dart';
import 'package:test/test.dart';

void main() {
  group('RgaList — local operations', () {
    test('insert / add / value keep visible order', () {
      var list = const RgaList<String>(replicaId: 'a');
      list = list.insert(0, 'b');
      list = list.insert(0, 'a');
      list = list.add('d');
      list = list.insert(2, 'c');
      expect(list.value, ['a', 'b', 'c', 'd']);
      expect(list.length, 4);
    });

    test('removeAt tombstones without breaking order', () {
      var list = const RgaList<int>(replicaId: 'a').insertAll(0, [1, 2, 3, 4]);
      list = list.removeAt(1);
      expect(list.value, [1, 3, 4]);
      list = list.removeAt(0);
      expect(list.value, [3, 4]);
    });

    test('insert after a removed element still anchors correctly', () {
      var list = const RgaList<String>(replicaId: 'a').insertAll(0, ['x', 'y', 'z']);
      list = list.removeAt(1); // tombstone 'y'
      list = list.insert(1, 'Y'); // between x and z (anchored on visible order)
      expect(list.value, ['x', 'Y', 'z']);
    });

    test('range errors on invalid indices', () {
      final list = const RgaList<int>(replicaId: 'a').insertAll(0, [1, 2]);
      expect(() => list.insert(3, 9), throwsRangeError);
      expect(() => list.insert(-1, 9), throwsRangeError);
      expect(() => list.removeAt(2), throwsRangeError);
      expect(() => list.removeRange(1, 2), throwsRangeError);
    });

    test('element ids are stable handles (cursor anchoring)', () {
      var list = const RgaList<String>(replicaId: 'a').insertAll(0, ['a', 'b', 'c']);
      final idOfB = list.elementIdAt(1);
      list = list.insert(0, '!'); // shift everything right
      expect(list.indexOfId(idOfB), 2);
      list = list.removeById(idOfB);
      expect(list.indexOfId(idOfB), -1);
      expect(list.value, ['!', 'a', 'c']);
    });
  });

  group('RgaList — convergence', () {
    test('merge is commutative for concurrent same-position inserts', () {
      final base = const RgaList<String>(replicaId: 'a').insertAll(0, ['H', 'i']);
      final a = RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: 'a').insert(2, 'A');
      final b = RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: 'b').insert(2, 'B');

      final ab = a.merge(b).value.join();
      final ba = b.merge(a).value.join();
      expect(ab, ba, reason: 'both devices must converge to the same order');
      expect(ab.split('').toSet(), {'H', 'i', 'A', 'B'}, reason: 'no element may be dropped');
    });

    test('merge is idempotent and self-merge is a no-op', () {
      final a = const RgaList<int>(replicaId: 'a').insertAll(0, [1, 2, 3]);
      expect(a.merge(a).value, a.value);
      final b = RgaList<int>.fromMap(a.toMap(), (v) => v as int, replicaId: 'b').add(4);
      final once = a.merge(b);
      final twice = a.merge(b).merge(b);
      expect(twice.value, once.value);
    });

    test('three replicas converge regardless of merge order (associativity)', () {
      final base = const RgaList<String>(replicaId: 'a').insertAll(0, ['x']);
      final a = RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: 'a').insert(0, 'A');
      final b = RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: 'b').insert(1, 'B');
      final c = RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: 'c').removeAt(0);

      final r1 = a.merge(b).merge(c).value.join();
      final r2 = c.merge(a).merge(b).value.join();
      final r3 = b.merge(c).merge(a).value.join();
      expect(r1, r2);
      expect(r2, r3);
      expect(r1.contains('x'), isFalse, reason: 'concurrent delete of x must win everywhere');
    });

    test('concurrent runs at the same spot do not interleave characters', () {
      final base = const RgaList<String>(replicaId: 'a').insertAll(0, ['[', ']']);
      final a = RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: 'a').insertAll(1, 'cat'.split(''));
      final b = RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: 'b').insertAll(1, 'dog'.split(''));

      final merged = a.merge(b).value.join();
      expect(merged, anyOf('[catdog]', '[dogcat]'), reason: 'words must stay contiguous, never interleaved');
      expect(merged, b.merge(a).value.join());
    });

    test('delete on one replica + insert-after-that-element on another', () {
      final base = const RgaList<String>(replicaId: 'a').insertAll(0, ['a', 'b', 'c']);
      // Replica A deletes 'b'; replica B concurrently inserts 'X' after 'b'.
      final a = RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: 'a').removeAt(1);
      final b = RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: 'b').insert(2, 'X');

      final merged = a.merge(b);
      // 'b' stays deleted (tombstone anchors X), X survives in position.
      expect(merged.value, ['a', 'X', 'c']);
      expect(merged.value, b.merge(a).value);
    });

    test('randomized fuzz: 3 replicas, random ops, all merge orders agree', () {
      final rand = Random(42); // fixed seed — deterministic test
      for (var round = 0; round < 20; round++) {
        final base = const RgaList<int>(replicaId: 'seed').insertAll(0, [0, 1, 2]);
        final replicas = ['a', 'b', 'c'].map((id) {
          var r = RgaList<int>.fromMap(base.toMap(), (v) => v as int, replicaId: id);
          for (var op = 0; op < 5; op++) {
            if (r.length > 0 && rand.nextBool()) {
              r = r.removeAt(rand.nextInt(r.length));
            } else {
              r = r.insert(rand.nextInt(r.length + 1), 100 * round + op);
            }
          }
          return r;
        }).toList();

        final m1 = replicas[0].merge(replicas[1]).merge(replicas[2]).value;
        final m2 = replicas[2].merge(replicas[0]).merge(replicas[1]).value;
        final m3 = replicas[1].merge(replicas[2]).merge(replicas[0]).value;
        expect(m1, m2, reason: 'round $round diverged');
        expect(m2, m3, reason: 'round $round diverged');
      }
    });
  });

  group('RgaList — serialization', () {
    test('toMap/fromMap round-trips state, order, and tombstones', () {
      var list = const RgaList<String>(replicaId: 'a').insertAll(0, ['a', 'b', 'c']);
      list = list.removeAt(1);
      final restored = RgaList<String>.fromMap(list.toMap(), (v) => v as String);
      expect(restored.value, ['a', 'c']);
      expect(restored, list);
    });

    test('fromMap with a new replicaId: local edits after merge sort correctly', () {
      final a = const RgaList<String>(replicaId: 'a').insertAll(0, ['1', '2']);
      // Device B loads A's state; its counter must advance past A's ops so
      // B's next edit is causally "after" everything it has seen.
      final b = RgaList<String>.fromMap(a.toMap(), (v) => v as String, replicaId: 'b').add('3');
      expect(b.replicaId, 'b');
      expect(b.value, ['1', '2', '3']);
      expect(a.merge(b).value, ['1', '2', '3']);
    });
  });

  group('RgaText — collaborative text editing', () {
    test('typing, inserting mid-string, and deleting', () {
      var doc = RgaText(replicaId: 'a').insert(0, 'hello world');
      doc = doc.delete(0, 1).insert(0, 'H');
      doc = doc.insert(5, ',');
      expect(doc.value, 'Hello, world');
      expect(doc.length, 12);
    });

    test('two devices editing concurrently converge to the same document', () {
      final base = RgaText(replicaId: 'a').insert(0, 'the cat');
      final a = RgaText.fromMap(base.toMap(), replicaId: 'a').insert(7, ' sat'); // 'the cat sat'
      final b = RgaText.fromMap(base.toMap(), replicaId: 'b').insert(4, 'big '); // 'the big cat'

      final mergedA = a.merge(b).value;
      final mergedB = b.merge(a).value;
      expect(mergedA, mergedB);
      expect(mergedA, 'the big cat sat');
    });

    test('concurrent edit + delete of the same word', () {
      final base = RgaText(replicaId: 'a').insert(0, 'red apple');
      final a = RgaText.fromMap(base.toMap(), replicaId: 'a').delete(0, 4); // 'apple'
      final b = RgaText.fromMap(base.toMap(), replicaId: 'b').insert(9, 's'); // 'red apples'

      final merged = a.merge(b).value;
      expect(merged, 'apples');
      expect(merged, b.merge(a).value);
    });

    test('character ids anchor remote cursors across edits', () {
      var doc = RgaText(replicaId: 'a').insert(0, 'abc');
      final cursor = doc.characterIdAt(2); // on 'c'
      doc = doc.insert(0, 'XY');
      expect(doc.indexOfCharacter(cursor), 4);
      doc = doc.delete(4, 1); // delete 'c'
      expect(doc.indexOfCharacter(cursor), -1);
    });

    test('round-trips through toMap/fromMap (persistable in a DatumEntity)', () {
      final doc = RgaText(replicaId: 'a').insert(0, 'persist me');
      final restored = RgaText.fromMap(doc.toMap(), replicaId: 'b');
      expect(restored.value, 'persist me');
      // Continue editing on the restoring device and merge back.
      final edited = restored.insert(10, '!');
      expect(doc.merge(edited).value, 'persist me!');
    });
  });
}
