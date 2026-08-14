import 'dart:math' as math;

import 'package:datum/datum.dart';
import 'package:test/test.dart';

/// Seeded random-operation fuzz for the CRDTs in `lib/source/core/models/crdt.dart`.
///
/// Property under test: **strong eventual consistency** — after any sequence
/// of concurrent operations, merging the replicas in ANY order or pairing
/// yields the same value (commutativity + associativity), merging twice is a
/// no-op (idempotence), and a replica merged with itself is unchanged.
///
/// Every scenario is deterministic per seed and every failure message embeds
/// the seed for reproduction.
void main() {
  const seeds = [7, 42, 20260814];
  const replicaCount = 3;
  const opsPerReplica = 40;
  const randomMergeShapes = 10;

  /// Merges [replicas] as a random binary tree (random pairings in random
  /// order) — exercises arbitrary merge shapes, not just linear folds.
  T mergeRandomly<T>(List<T> replicas, T Function(T a, T b) merge, math.Random rng) {
    final pool = List<T>.of(replicas)..shuffle(rng);
    while (pool.length > 1) {
      final a = pool.removeAt(rng.nextInt(pool.length));
      final b = pool.removeAt(rng.nextInt(pool.length));
      pool.add(merge(a, b));
    }
    return pool.single;
  }

  /// All permutations of the replica indices (n! linear fold orders).
  List<List<int>> permutations(int n) {
    if (n == 1) {
      return [
        [0],
      ];
    }
    final result = <List<int>>[];
    for (final tail in permutations(n - 1)) {
      for (var i = 0; i <= tail.length; i++) {
        result.add([...tail.sublist(0, i), n - 1, ...tail.sublist(i)]);
      }
    }
    return result;
  }

  /// Asserts every linear fold order and [randomMergeShapes] random merge
  /// trees produce the same rendered value, and returns one merged result.
  T assertMergeOrderIndependent<T>({
    required List<T> replicas,
    required T Function(T a, T b) merge,
    required String Function(T) render,
    required int seed,
    required String what,
    required math.Random rng,
  }) {
    T foldIn(List<int> order) => order.skip(1).fold(replicas[order.first], (acc, i) => merge(acc, replicas[i]));

    final reference = foldIn(List.generate(replicas.length, (i) => i));
    final expected = render(reference);

    for (final order in permutations(replicas.length)) {
      expect(
        render(foldIn(order)),
        expected,
        reason: '$what: linear merge order $order produced a different value (seed $seed)',
      );
    }
    for (var shape = 0; shape < randomMergeShapes; shape++) {
      expect(
        render(mergeRandomly(replicas, merge, rng)),
        expected,
        reason: '$what: random merge shape #$shape produced a different value (seed $seed)',
      );
    }
    return reference;
  }

  group('RgaList<String> fuzz', () {
    /// Applies [opsPerReplica] random inserts/removes (valid indices only) to
    /// [list], tagging inserted values so every element is globally unique.
    RgaList<String> mutate(RgaList<String> list, String tag, math.Random rng) {
      for (var k = 0; k < opsPerReplica; k++) {
        if (list.length > 0 && rng.nextInt(10) < 4) {
          list = list.removeAt(rng.nextInt(list.length));
        } else {
          list = list.insert(rng.nextInt(list.length + 1), '$tag-op$k');
        }
      }
      return list;
    }

    List<RgaList<String>> divergedReplicas(RgaList<String> base, math.Random rng, String phase) => [
          for (var i = 0; i < replicaCount; i++)
            mutate(
              RgaList<String>.fromMap(base.toMap(), (v) => v as String, replicaId: '$phase-r$i'),
              '$phase-r$i',
              rng,
            ),
        ];

    for (final seed in seeds) {
      test('replicas converge under every merge order (seed $seed)', () {
        final rng = math.Random(seed);
        final base = const RgaList<String>(replicaId: 'base').insertAll(0, List.generate(5, (i) => 'base$i'));
        final replicas = divergedReplicas(base, rng, 'p1');

        final merged = assertMergeOrderIndependent<RgaList<String>>(
          replicas: replicas,
          merge: (a, b) => a.merge(b),
          render: (l) => l.value.join('|'),
          seed: seed,
          what: 'RgaList',
          rng: rng,
        );

        // Idempotence: merging the same state again changes nothing.
        expect(
          merged.merge(merged).value.join('|'),
          merged.value.join('|'),
          reason: 'RgaList: merging a merged state with itself changed the value (seed $seed)',
        );
        expect(
          merged.merge(replicas.first).value.join('|'),
          merged.value.join('|'),
          reason: 'RgaList: re-merging an already-absorbed replica changed the value (seed $seed)',
        );

        // Self-merge leaves a replica unchanged (value AND element identity).
        for (final replica in replicas) {
          expect(
            replica.merge(replica).value.join('|'),
            replica.value.join('|'),
            reason: 'RgaList: replica ${replica.replicaId} merged with itself changed value (seed $seed)',
          );
          expect(
            replica.merge(replica).idsInOrder,
            replica.idsInOrder,
            reason: 'RgaList: replica ${replica.replicaId} merged with itself changed element ids (seed $seed)',
          );
        }
      });

      test('compacted() at a synced barrier stays convergent (seed $seed)', () {
        final rng = math.Random(seed);
        final base = const RgaList<String>(replicaId: 'base').insertAll(0, List.generate(5, (i) => 'base$i'));

        // Phase 1: diverge, then bring every replica to the identical synced
        // state (the coordination barrier compaction requires).
        final phase1 = divergedReplicas(base, rng, 'p1');
        final synced = phase1.skip(1).fold(phase1.first, (acc, r) => acc.merge(r));
        expect(synced.tombstoneCount, greaterThan(0), reason: 'RgaList: fuzz produced no tombstones to compact (seed $seed)');

        final compacted = [
          for (var i = 0; i < replicaCount; i++) RgaList<String>.fromMap(synced.toMap(), (v) => v as String, replicaId: 'c-r$i').compacted(),
        ];
        for (var i = 0; i < compacted.length; i++) {
          expect(
            compacted[i].value.join('|'),
            synced.value.join('|'),
            reason: 'RgaList: compaction on replica $i changed the visible value (seed $seed)',
          );
          expect(compacted[i].tombstoneCount, 0, reason: 'RgaList: compaction on replica $i left tombstones (seed $seed)');
        }

        // Compacted replicas of the same synced state remain mergeable.
        assertMergeOrderIndependent<RgaList<String>>(
          replicas: compacted,
          merge: (a, b) => a.merge(b),
          render: (l) => l.value.join('|'),
          seed: seed,
          what: 'RgaList compacted barrier',
          rng: rng,
        );

        // Phase 2: diverge again from the compacted state and re-merge.
        final phase2 = [
          for (var i = 0; i < compacted.length; i++) mutate(compacted[i], 'p2-r${compacted[i].replicaId}', rng),
        ];
        assertMergeOrderIndependent<RgaList<String>>(
          replicas: phase2,
          merge: (a, b) => a.merge(b),
          render: (l) => l.value.join('|'),
          seed: seed,
          what: 'RgaList post-compaction divergence',
          rng: rng,
        );
      });
    }
  });

  group('ORSet<String> fuzz', () {
    const alphabet = ['k0', 'k1', 'k2', 'k3', 'k4', 'k5', 'k6', 'k7'];

    for (final seed in seeds) {
      test('replicas converge under every merge order (seed $seed)', () {
        final rng = math.Random(seed);
        var base = const ORSet<String>();
        base = base.add('k0', 'base-t0').add('k1', 'base-t1');
        base = base.remove('k1');

        final replicas = <ORSet<String>>[];
        for (var i = 0; i < replicaCount; i++) {
          var set = base;
          for (var k = 0; k < opsPerReplica; k++) {
            final current = set.value.toList();
            if (current.isNotEmpty && rng.nextInt(10) < 4) {
              set = set.remove(current[rng.nextInt(current.length)]);
            } else {
              set = set.add(alphabet[rng.nextInt(alphabet.length)], 'r$i-t$k');
            }
          }
          replicas.add(set);
        }

        String render(ORSet<String> s) => (s.value.toList()..sort()).join('|');

        final merged = assertMergeOrderIndependent<ORSet<String>>(
          replicas: replicas,
          merge: (a, b) => a.merge(b),
          render: render,
          seed: seed,
          what: 'ORSet',
          rng: rng,
        );

        expect(
          render(merged.merge(merged)),
          render(merged),
          reason: 'ORSet: merging a merged state with itself changed the value (seed $seed)',
        );
        expect(
          render(merged.merge(replicas.last)),
          render(merged),
          reason: 'ORSet: re-merging an already-absorbed replica changed the value (seed $seed)',
        );
        for (var i = 0; i < replicas.length; i++) {
          expect(
            render(replicas[i].merge(replicas[i])),
            render(replicas[i]),
            reason: 'ORSet: replica $i merged with itself changed value (seed $seed)',
          );
        }
      });
    }
  });

  group('PNCounter fuzz', () {
    for (final seed in seeds) {
      test('replicas converge under every merge order (seed $seed)', () {
        final rng = math.Random(seed);
        final base = const PNCounter().increment('base', 10).decrement('base', 3);

        // Each replica only ever touches ITS OWN replica id (the PNCounter
        // usage contract), so the converged value is exactly base + the sum
        // of every replica's local net effect.
        var expectedValue = base.value;
        final replicas = <PNCounter>[];
        for (var i = 0; i < replicaCount; i++) {
          var counter = base;
          for (var k = 0; k < opsPerReplica; k++) {
            final amount = 1 + rng.nextInt(5);
            if (rng.nextBool()) {
              counter = counter.increment('r$i', amount);
              expectedValue += amount;
            } else {
              counter = counter.decrement('r$i', amount);
              expectedValue -= amount;
            }
          }
          replicas.add(counter);
        }

        final merged = assertMergeOrderIndependent<PNCounter>(
          replicas: replicas,
          merge: (a, b) => a.merge(b),
          render: (c) => '${c.value}',
          seed: seed,
          what: 'PNCounter',
          rng: rng,
        );

        expect(
          merged.value,
          expectedValue,
          reason: 'PNCounter: converged value does not equal the sum of all replica effects (seed $seed)',
        );
        expect(
          merged.merge(merged).value,
          merged.value,
          reason: 'PNCounter: merging a merged state with itself changed the value (seed $seed)',
        );
        expect(
          merged.merge(replicas.first).value,
          merged.value,
          reason: 'PNCounter: re-merging an already-absorbed replica changed the value (seed $seed)',
        );
        for (var i = 0; i < replicas.length; i++) {
          expect(
            replicas[i].merge(replicas[i]).value,
            replicas[i].value,
            reason: 'PNCounter: replica $i merged with itself changed value (seed $seed)',
          );
        }
      });
    }
  });
}
