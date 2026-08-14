---
title: Collaborative Editing & CRDTs
description: Conflict-free counters, sets, ordered lists, and text — build multi-device editors that merge instead of fight.
---

Last-write-wins is the right default for records like a task's title: one
writer should win. But some data is *jointly owned* — a shared counter, a
tag set, the text of a note two people edit on a train. For those, Datum
ships **CRDTs** (Conflict-free Replicated Data Types): structures whose
merges are commutative, associative, and idempotent, so every device
converges to the same value no matter the sync order.

| Type | Shape | Concurrent behavior |
|---|---|---|
| `PNCounter` | increment/decrement counter | all deltas count |
| `ORSet<T>` | add/remove set | concurrent add wins over remove of the same element |
| `RgaList<T>` | ordered sequence | concurrent inserts keep both, deterministic order |
| `RgaText` | collaborative text | runs of typing never interleave |

Every type is immutable (operations return a new instance), serializes via
`toMap`/`fromMap`, and merges with `merge`.

## Counters and sets in sixty seconds

```dart
var likesOnPhone = const PNCounter();
var likesOnLaptop = const PNCounter();

likesOnPhone = likesOnPhone.increment('phone');
likesOnPhone = likesOnPhone.increment('phone');
likesOnLaptop = likesOnLaptop.increment('laptop');

// Merge in any order — both devices converge on 3.
print(likesOnPhone.merge(likesOnLaptop).value); // 3
print(likesOnLaptop.merge(likesOnPhone).value); // 3
```

```dart
var tagsA = const ORSet<String>();
var tagsB = ORSet<String>.fromMap(tagsA.toMap(), (raw) => raw as String);

// Each add carries a unique tag (a uuid in a real app).
tagsA = tagsA.add('urgent', 'a-1');
tagsB = tagsB.add('urgent', 'b-1');
tagsB = tagsB.remove('urgent'); // B removes the adds IT has observed…
tagsA = tagsA.add('home', 'a-2');

final merged = tagsA.merge(tagsB);
// …but A's concurrent add survives: add-wins semantics.
print(merged.value.contains('urgent')); // true
print(merged.value.contains('home'));   // true
```

## Collaborative text with `RgaText`

`RgaText` is the sequence CRDT editors need. Each character carries a stable
`(replicaId, counter)` identity and anchors after its predecessor, so
concurrent edits merge deterministically and contiguous runs of typing never
interleave:

```dart
var noteOnA = RgaText(replicaId: 'device-a');
noteOnA = noteOnA.insert(0, 'the cat sat');

// Device B loads the synced state with ITS OWN replica id.
var noteOnB = RgaText.fromMap(noteOnA.toMap(), replicaId: 'device-b');

// Offline, both edit concurrently:
noteOnA = noteOnA.insert(4, 'big ');   // "the big cat sat"
noteOnB = noteOnB.delete(8, 3);        // "the cat "
noteOnB = noteOnB.insert(8, 'slept');  // "the cat slept"

// Any merge order converges:
print(noteOnA.merge(noteOnB).value); // the big cat slept
print(noteOnB.merge(noteOnA).value); // the big cat slept
```

Stable character ids double as **cursor anchors** for remote carets:

```dart
var doc = RgaText(replicaId: 'editor');
doc = doc.insert(0, 'hello');
final anchor = doc.characterIdAt(4);       // id of 'o'
doc = doc.insert(0, '>> ');                // text shifts…
print(doc.indexOfCharacter(anchor));       // …the anchor follows: 7
```

## Wiring a CRDT into an entity

Store the serialized CRDT in a field and merge it in your entity's `merge`,
then let the `CRDTResolver` drive conflict resolution for that type:

```dart
class CollabNote extends DatumEntity {
  const CollabNote({
    required this.id,
    required this.userId,
    required this.body,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  final RgaText body;
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  CollabNote merge(covariant DatumEntityInterface other) {
    final remote = other as CollabNote;
    return CollabNote(
      id: id,
      userId: userId,
      body: body.merge(remote.body), // CRDT merge — no data loss
      createdAt: createdAt,
      modifiedAt: DateTime.now(),
      version: (version > remote.version ? version : remote.version) + 1,
      isDeleted: isDeleted || remote.isDeleted,
    );
  }

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
    'id': id,
    'userId': userId,
    'body': body.toMap(),
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'version': version,
    'isDeleted': isDeleted,
  };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap(target: MapTarget.remote);

  @override
  List<Object?> get props => [...super.props, body];
}
```

```dart
final collabConfig = DatumConfig<Task>(
  // Route conflicts through entity.merge — which the CRDT makes lossless.
  defaultConflictResolver: CRDTResolver(),
);
```

Two ingredients make the editor experience solid:

1. **Per-device replica ids.** Load synced state with the local device's id
   (`RgaText.fromMap(map, replicaId: myDeviceId)`) so local edits carry the
   right identity.
2. **Vector clocks on the entity.** Concurrent same-version edits are then
   detected precisely instead of heuristically — see the collaborative
   editor reference test in the datum repository
   (`test/integration/collaborative_editor_test.dart`) for the complete
   two-device flow against a real backend.

## Compaction: keeping long-lived documents lean

Deleted characters remain as **tombstones** so concurrent inserts anchored
to them still order correctly — and over a document's life they accumulate.
Compact at a synchronization barrier:

```dart
var doc = RgaText(replicaId: 'editor');
doc = doc.insert(0, 'hello world');
doc = doc.delete(5, 6);
print(doc.tombstoneCount); // 6

final compacted = doc.compact();
print(compacted.value);          // hello
print(compacted.tombstoneCount); // 0 — ids and cursor anchors preserved
```

**The contract:** only compact when every replica has merged the current
state (persisting a checkpoint, or a single-writer moment). Merging a
compacted document with a *stale* replica that never observed a deletion
resurrects the deleted content, because the tombstone recording it is gone.
Two replicas that compact the same synced state remain fully convergent.

## When *not* to use a CRDT

CRDTs trade memory and merge cost for losslessness. For a status field, a
price, a due date — anything where "the newer value should simply win" —
stay with the default last-write-wins resolution. Reserve CRDTs for fields
where concurrent contributions are all valid and must all survive.
