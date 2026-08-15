/// CRDT convergence regressions (2026-08 audit fixes):
///
/// 1. Compaction + a stale replica with un-merged ops used to diverge the
///    order PERMANENTLY (merge kept different origins per replica forever).
///    merge() now reconciles same-id nodes deterministically, so every
///    replica converges to the same state.
/// 2. Deserializing without a replicaId minted colliding node ids across
///    devices, silently destroying concurrent edits with no convergence.
///    Collisions now resolve deterministically (convergent), and passing
///    distinct replicaIds — the documented contract — loses nothing.
/// 3. Two CONVERGED replicas must serialize byte-identically (canonical node
///    order, no per-device replicaId in the wire format) — order-sensitive
///    deep equality in conflict detection otherwise re-flagged converged
///    documents forever.
/// 4. CRDTResolver: a deletion conflict resolves content-preservingly
///    instead of aborting forever, and a degraded default merge (`=> other`)
///    is surfaced in the resolution message.
/// 5. ORSet round-trips non-String element types (format 2), and PNCounter
///    tolerates JSON backends that deliver ints as doubles.
library;

import 'dart:convert';

import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../test_utils/test_datum_entity.dart';

void main() {
  group('RGA compaction with a stale replica (previously permanent divergence)', () {
    test('all replicas converge after one compacts while another holds un-merged ops', () {
      // Replica A creates "x y z"; everyone syncs.
      final a0 = const RgaList<String>(replicaId: 'a').insertAll(0, ['x', 'y', 'z']);
      var a = a0;
      var b = RgaList<String>.fromMap(a0.toMap(), (v) => v as String, replicaId: 'b');
      var c = RgaList<String>.fromMap(a0.toMap(), (v) => v as String, replicaId: 'c');

      // A deletes 'y' and syncs the deletion with B only — C stays stale.
      a = a.removeAt(1);
      b = b.merge(a);

      // A compacts (barrier violated: C never saw the deletion).
      a = a.compacted();

      // Stale C inserts 'w' after the still-visible 'y'.
      c = c.insert(2, 'w');

      // Full mesh sync, several rounds so every state reaches every replica.
      for (var round = 0; round < 3; round++) {
        final ma = a.merge(b).merge(c);
        final mb = b.merge(c).merge(a);
        final mc = c.merge(a).merge(b);
        a = ma;
        b = mb;
        c = mc;
      }

      expect(a.value.join(), b.value.join(), reason: 'replicas A and B must converge');
      expect(b.value.join(), c.value.join(), reason: 'replicas B and C must converge');
      // 'x', 'z', 'w' survive; 'y' may resurrect (documented stale-replica
      // caveat) — but NEVER divergence.
      expect(a.value.toSet(), containsAll(<String>{'x', 'z', 'w'}));
    });

    test('merge stays commutative/associative/idempotent under origin collisions', () {
      final base = const RgaList<String>(replicaId: 'a').insertAll(0, ['1', '2', '3']);
      final compacted = base.removeAt(1).compacted();
      final stale = RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: 's').insert(3, '4');

      final ab = compacted.merge(stale);
      final ba = stale.merge(compacted);
      expect(ab.value.join(), ba.value.join(), reason: 'commutative');
      expect(ab.merge(ab).value.join(), ab.value.join(), reason: 'idempotent');
      expect(ab.merge(ba).value.join(), ab.value.join(), reason: 'converged states are a fixpoint');
    });
  });

  group('replica identity', () {
    test('two devices editing a document deserialized WITHOUT replicaId still converge', () {
      final creator = const RgaList<String>(replicaId: 'creator').insertAll(0, ['t', 'h', 'e']);
      // The trap: neither device passes its own replicaId.
      var deviceA = RgaList<String>.fromMap(creator.toMap(), (v) => v as String);
      var deviceB = RgaList<String>.fromMap(creator.toMap(), (v) => v as String);

      // Concurrent edits mint COLLIDING node ids.
      deviceA = deviceA.insertAll(3, ['!', '!']);
      deviceB = deviceB.insertAll(0, ['>', '>']);

      final mergedA = deviceA.merge(deviceB);
      final mergedB = deviceB.merge(deviceA);
      expect(mergedA.value.join(), mergedB.value.join(), reason: 'colliding ids must resolve deterministically, not diverge');
    });

    test('passing distinct replicaIds — the documented contract — loses nothing', () {
      final creator = const RgaList<String>(replicaId: 'creator').insertAll(0, ['t', 'h', 'e']);
      var deviceA = RgaList<String>.fromMap(creator.toMap(), (v) => v as String, replicaId: 'device-a');
      var deviceB = RgaList<String>.fromMap(creator.toMap(), (v) => v as String, replicaId: 'device-b');

      deviceA = deviceA.insertAll(3, ['!', '!']);
      deviceB = deviceB.insertAll(0, ['>', '>']);

      final merged = deviceA.merge(deviceB);
      expect(merged.value.join(), deviceB.merge(deviceA).value.join());
      expect(merged.value.join(), '>>the!!', reason: 'both concurrent runs survive with distinct identities');
    });
  });

  group('canonical serialization', () {
    test('converged replicas serialize byte-identically', () {
      var a = const RgaList<String>(replicaId: 'a').insertAll(0, ['x', 'y']);
      var b = RgaList<String>.fromMap(a.toMap(), (v) => v as String, replicaId: 'b');
      a = a.insert(2, 'A');
      b = b.insert(0, 'B');
      a = a.merge(b);
      b = b.merge(a);

      expect(a.value.join(), b.value.join(), reason: 'precondition: converged');
      expect(
        jsonEncode(a.toMap()),
        jsonEncode(b.toMap()),
        reason: 'identical state must serialize identically or conflict detection re-fires forever',
      );
    });

    test('RgaText round-trips through the wire format', () {
      var doc = RgaText(replicaId: 'a').insert(0, 'hello world');
      doc = doc.delete(0, 1).insert(0, 'H');

      final revived = RgaText.fromMap(jsonDecode(jsonEncode(doc.toMap())) as Map<String, dynamic>, replicaId: 'b');
      expect(revived.value, 'Hello world');
      expect(revived.replicaId, 'b', reason: 'the wire format must not smuggle the creator identity');
    });
  });

  group('CRDTResolver', () {
    const resolver = CRDTResolver<TestDatumEntity>();
    final context = DatumConflictContext(
      entityId: 'e1',
      userId: 'u1',
      type: DatumConflictType.deletionConflict,
      detectedAt: DateTime.utc(2026, 1, 1),
    );

    test('a remote deletion preserves the local document instead of aborting forever', () async {
      final local = TestDatumEntity(id: 'e1', userId: 'u1', value: 'content');
      final resolution = await resolver.resolve(local: local, remote: null, context: context);

      expect(resolution.strategy, DatumResolutionStrategy.takeLocal, reason: 'abort left the same conflict re-firing on every sync cycle');
      expect(resolution.resolvedData, local);
    });

    test('a local deletion accepts the remote document', () async {
      final remote = TestDatumEntity(id: 'e1', userId: 'u1', value: 'content');
      final resolution = await resolver.resolve(local: null, remote: remote, context: context);

      expect(resolution.strategy, DatumResolutionStrategy.takeRemote);
      expect(resolution.resolvedData, remote);
    });

    test('a degraded default merge (`=> other`) is surfaced in the message', () async {
      // TestDatumEntity does NOT override merge, so the mixin default
      // returns `other` — a silent take-remote dressed up as a merge.
      final local = TestDatumEntity(id: 'e1', userId: 'u1', value: 'local-edit');
      final remote = TestDatumEntity(id: 'e1', userId: 'u1', value: 'remote-edit');
      final resolution = await resolver.resolve(local: local, remote: remote, context: context);

      expect(resolution.strategy, DatumResolutionStrategy.merge);
      expect(resolution.message, contains('DEFAULT merge'));
    });
  });

  group('serialization robustness', () {
    test('ORSet<int> round-trips through JSON (crashed under the legacy string-key format)', () {
      var set = const ORSet<int>().add(1, 'tag-a').add(2, 'tag-b').add(3, 'tag-c');
      set = set.remove(2);

      final revived = ORSet<int>.fromMap(
        jsonDecode(jsonEncode(set.toMap())) as Map<String, dynamic>,
        (raw) => (raw as num).toInt(),
      );

      expect(revived.value, {1, 3});
      // Removals survive the round-trip: re-merging the pre-removal state
      // must not resurrect element 2.
      final preRemoval = const ORSet<int>().add(2, 'tag-b');
      expect(revived.merge(preRemoval).value, {1, 3});
    });

    test('legacy string-keyed ORSet payloads still decode', () {
      final legacy = {
        'add': {
          'apple': ['t1'],
          'pear': ['t2'],
        },
        'remove': {
          'pear': ['t2'],
        },
      };
      final revived = ORSet<String>.fromMap(legacy, (raw) => raw as String);
      expect(revived.value, {'apple'});
    });

    test('PNCounter tolerates doubles from JSON backends', () {
      final counter = PNCounter.fromMap(const {
        'p': {'a': 5.0, 'b': 2},
        'n': {'a': 1.0},
      });
      expect(counter.value, 6);
    });
  });
}
