import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

// ===========================================================================
// End-to-end collaborative-editor scenario: a document entity whose body is an
// RgaText CRDT, synced between two "devices" through the real engine with
// CRDTResolver. Concurrent edits on both devices must converge on BOTH sides
// without losing either edit.
// ===========================================================================

class CollabNote extends DatumEntity {
  CollabNote({
    required this.id,
    required this.userId,
    required this.body,
    required this.version,
    this.vectorClock,
    DateTime? at,
  })  : modifiedAt = at ?? DateTime(2024),
        createdAt = DateTime(2024);

  factory CollabNote.fromMap(Map<String, dynamic> map) => CollabNote(
        id: map['id'] as String,
        userId: map['userId'] as String,
        body: RgaText.fromMap(Map<String, dynamic>.from(map['body'] as Map)),
        version: map['version'] as int? ?? 1,
        vectorClock: map['vectorClock'] != null ? VectorClock.fromMap(Map<String, dynamic>.from(map['vectorClock'] as Map)) : null,
      );

  @override
  final String id;
  @override
  final String userId;

  /// The collaborative document body — a convergent text CRDT.
  final RgaText body;

  @override
  final int version;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  bool get isDeleted => false;

  /// Vector clocks are essential for editors: they let the engine DETECT that
  /// two same-version copies are concurrent edits (a bare version number
  /// cannot), which is what routes the pair into the CRDT merge.
  @override
  final VectorClock? vectorClock;

  @override
  CollabNote incrementClock(String replicaId) => CollabNote(
        id: id,
        userId: userId,
        body: body,
        version: version,
        vectorClock: (vectorClock ?? const VectorClock()).increment(replicaId),
        at: modifiedAt,
      );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'body': body.toMap(),
        'version': version,
        'vectorClock': vectorClock?.toMap(),
      };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface old) => toDatumMap(target: MapTarget.remote);

  /// CRDT merge: the resolver calls this on conflict; both edit histories are
  /// combined (text AND clocks) so every replica converges on the same text.
  @override
  CollabNote merge(covariant DatumEntityInterface other) {
    final o = other as CollabNote;
    return CollabNote(
      id: id,
      userId: userId,
      body: body.merge(o.body),
      version: (version > o.version ? version : o.version) + 1,
      vectorClock: (vectorClock ?? const VectorClock()).merge(o.vectorClock ?? const VectorClock()),
      at: DateTime(2032),
    );
  }
}

MockConnectivityChecker _connected() {
  final c = MockConnectivityChecker();
  when(() => c.isConnected).thenAnswer((_) async => true);
  when(() => c.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return c;
}

DatumManager<CollabNote> _device(String deviceId, MockRemoteAdapter<CollabNote> sharedRemote) {
  return DatumManager<CollabNote>(
    localAdapter: InMemoryLocalAdapter<CollabNote>(fromMap: CollabNote.fromMap),
    remoteAdapter: sharedRemote,
    connectivity: _connected(),
    // deviceId makes push() auto-increment the entity's vector clock.
    deviceId: deviceId,
    datumConfig: const DatumConfig<CollabNote>(
      defaultConflictResolver: CRDTResolver<CollabNote>(),
    ),
  );
}

void main() {
  test('two devices edit the same document offline and converge via CRDT merge', () async {
    // Both devices share the same backend ("remote").
    final remote = MockRemoteAdapter<CollabNote>(fromJson: CollabNote.fromMap);
    final deviceA = _device('device-a', remote);
    final deviceB = _device('device-b', remote);
    await deviceA.initialize();
    await deviceB.initialize();
    addTearDown(deviceA.dispose);
    addTearDown(deviceB.dispose);

    // Device A creates the document and syncs it up.
    final original = CollabNote(
      id: 'doc1',
      userId: 'u1',
      body: RgaText(replicaId: 'device-a').insert(0, 'the cat'),
      version: 1,
    );
    await deviceA.push(item: original, userId: 'u1');
    await deviceA.synchronize('u1');

    // Device B pulls the document.
    await deviceB.synchronize('u1');
    final onB = await deviceB.read('doc1', userId: 'u1');
    expect(onB!.body.value, 'the cat');
    final onA = await deviceA.read('doc1', userId: 'u1');

    // Both devices now edit CONCURRENTLY (each on its own local copy). push()
    // auto-increments each device's vector clock entry, which is what lets the
    // engine later recognize the two v2 copies as CONCURRENT (a bare version
    // number can't distinguish "same version" from "conflicting edits").
    final editedA = CollabNote(
      id: 'doc1',
      userId: 'u1',
      body: RgaText.fromMap(onA!.body.toMap(), replicaId: 'device-a').insert(7, ' sat'), // 'the cat sat'
      version: 2,
      vectorClock: onA.vectorClock,
      at: DateTime(2030),
    );
    final editedB = CollabNote(
      id: 'doc1',
      userId: 'u1',
      body: RgaText.fromMap(onB.body.toMap(), replicaId: 'device-b').insert(4, 'big '), // 'the big cat'
      version: 2,
      vectorClock: onB.vectorClock,
      at: DateTime(2030, 2),
    );
    await deviceA.push(item: editedA, userId: 'u1');
    await deviceB.push(item: editedB, userId: 'u1');

    // A syncs first (its edit reaches the backend), then B syncs — B's push
    // lands its own copy, but the concurrent clocks mean the divergence is
    // detected on the NEXT pulls and routed through CRDTResolver, which calls
    // CollabNote.merge -> RgaText.merge. The engine pushes the merged winner
    // (this session's convergence fix), so a couple of sync rounds later every
    // replica AND the backend hold both edits.
    await deviceA.synchronize('u1');
    await deviceB.synchronize('u1');
    await deviceA.synchronize('u1');
    await deviceA.synchronize('u1');
    await deviceB.synchronize('u1');

    final mergedOnA = await deviceA.read('doc1', userId: 'u1');
    final mergedOnB = await deviceB.read('doc1', userId: 'u1');
    final mergedOnRemote = await remote.read('doc1', userId: 'u1');

    expect(mergedOnA!.body.value, 'the big cat sat', reason: 'A must hold both edits merged');
    expect(mergedOnB!.body.value, 'the big cat sat', reason: 'B must converge to the same text');
    expect(mergedOnRemote!.body.value, 'the big cat sat', reason: 'backend must converge too');
  });
}
