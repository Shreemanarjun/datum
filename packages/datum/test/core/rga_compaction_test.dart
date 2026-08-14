import 'package:datum/datum.dart';
import 'package:test/test.dart';

void main() {
  group('RgaList.compacted', () {
    RgaList<String> build() {
      var list = const RgaList<String>(replicaId: 'a').insertAll(0, ['h', 'e', 'l', 'l', 'o']);
      list = list.removeRange(1, 2); // tombstones 'e', first 'l'
      return list; // visible: h l o
    }

    test('purges tombstones and preserves visible order and value', () {
      final list = build();
      expect(list.tombstoneCount, 2);

      final compacted = list.compacted();

      expect(compacted.value, ['h', 'l', 'o']);
      expect(compacted.tombstoneCount, 0);
      expect(compacted.value, list.value, reason: 'compaction must not change the visible sequence');
    });

    test('preserves element ids, keeping cursor anchors valid', () {
      final list = build();
      final anchors = list.idsInOrder;

      final compacted = list.compacted();

      expect(compacted.idsInOrder, anchors);
      expect(compacted.indexOfId(anchors[1]), 1);
    });

    test('editing continues correctly after compaction (no id collisions)', () {
      var list = build().compacted();
      list = list.insert(1, 'X').insert(0, 'Y');

      expect(list.value, ['Y', 'h', 'X', 'l', 'o']);
      expect(list.idsInOrder.toSet().length, 5, reason: 'all ids unique');
    });

    test('two replicas compacting the same synced state stay convergent', () {
      final a = build();
      final b = RgaList<String>.fromMap(a.toMap(), (v) => v as String, replicaId: 'b');

      var ca = a.compacted();
      var cb = b.compacted();
      expect(ca.value, cb.value);

      // Divergent edits after the barrier still merge to the same result.
      ca = ca.insert(3, '!');
      cb = cb.insert(0, '>');
      expect(ca.merge(cb).value, cb.merge(ca).value);
      expect(ca.merge(cb).value, ['>', 'h', 'l', 'o', '!']);
    });

    test('an empty list compacts to an empty list', () {
      const empty = RgaList<String>(replicaId: 'a');
      expect(empty.compacted().value, isEmpty);
      expect(empty.compacted().tombstoneCount, 0);
    });

    test('documented hazard: merging with a stale replica resurrects deletions', () {
      // This pins the coordination contract from the docs: compaction must
      // happen at a sync barrier. 'b' branches BEFORE 'a' deletes, so after
      // 'a' compacts, the tombstone recording the deletion is gone and the
      // merge brings the deleted element back.
      final a0 = const RgaList<String>(replicaId: 'a').insertAll(0, ['x', 'y']);
      final staleB = RgaList<String>.fromMap(a0.toMap(), (v) => v as String, replicaId: 'b');

      final aCompacted = a0.removeAt(1).compacted(); // deletes 'y', purges its tombstone

      expect(aCompacted.merge(staleB).value, ['x', 'y'], reason: 'resurrection is exactly why the barrier is required');
    });
  });

  group('RgaText.compact', () {
    test('preserves text and character anchors, drops tombstones', () {
      var doc = RgaText(replicaId: 'editor');
      doc = doc.insert(0, 'hello world');
      doc = doc.delete(5, 6); // 'hello'
      expect(doc.tombstoneCount, 6);

      final anchorId = doc.characterIdAt(4);
      final compacted = doc.compact();

      expect(compacted.value, 'hello');
      expect(compacted.tombstoneCount, 0);
      expect(compacted.indexOfCharacter(anchorId), 4, reason: 'cursor anchors survive compaction');

      final resumed = compacted.insert(5, '!');
      expect(resumed.value, 'hello!');
    });
  });
}
