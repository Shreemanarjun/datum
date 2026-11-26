import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'package:mocktail/mocktail.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

/// Hand-written entity on the mixin's default `diff`, with timestamps stored
/// locally as epoch ms but sent remotely as ISO-8601 (like the example app).
class _Note extends DatumEntity {
  const _Note(this.id, this.text, this.modifiedAt, {this.version = 1});

  factory _Note.fromMap(Map<String, dynamic> map) => _Note(
        map['id'] as String,
        map['text'] as String,
        DateTime.fromMillisecondsSinceEpoch(map['modifiedAt'] as int, isUtc: true),
        version: map['version'] as int,
      );

  @override
  final String id;
  final String text;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  String get userId => 'u1';
  @override
  DateTime get createdAt => DateTime.utc(2026);
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'text': text,
        'version': version,
        'modifiedAt': target == MapTarget.remote ? modifiedAt.toIso8601String() : modifiedAt.millisecondsSinceEpoch,
      };
}

/// Different key names per target (snake_case locally, camelCase remotely).
class _Split extends DatumEntity {
  const _Split(this.id, this.body, this.modifiedAt, {this.version = 1});

  factory _Split.fromMap(Map<String, dynamic> map) => _Split(
        map['id'] as String,
        map['body'] as String,
        DateTime.fromMillisecondsSinceEpoch(map['modified_at'] as int, isUtc: true),
        version: map['version'] as int,
      );

  @override
  final String id;
  final String body;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  String get userId => 'u1';
  @override
  DateTime get createdAt => DateTime.utc(2026);
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => target == MapTarget.remote
      ? {'id': id, 'userId': userId, 'body': body, 'version': version, 'modifiedAt': modifiedAt.toIso8601String()}
      : {'id': id, 'user_id': userId, 'body': body, 'version': version, 'modified_at': modifiedAt.millisecondsSinceEpoch};
}

/// A hand-written diff that reports only [text]; [createdAt] is set once.
class _Pinned extends DatumEntity {
  const _Pinned(this.id, this.text, this.modifiedAt, {required this.createdAt, this.version = 1});

  factory _Pinned.fromMap(Map<String, dynamic> map) => _Pinned(
        map['id'] as String,
        map['text'] as String,
        DateTime.parse(map['modifiedAt'] as String),
        createdAt: DateTime.parse(map['createdAt'] as String),
        version: map['version'] as int,
      );

  @override
  final String id;
  final String text;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  String get userId => 'u1';
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      {'id': id, 'userId': userId, 'text': text, 'version': version, 'modifiedAt': modifiedAt.toIso8601String(), 'createdAt': createdAt.toIso8601String()};

  @override
  Map<String, dynamic>? diff(covariant _Pinned old) => text == old.text ? null : {'text': text, 'version': version, 'modifiedAt': modifiedAt.toIso8601String()};
}

Future<DatumManager<E>> _manager<E extends DatumEntity>(E Function(Map<String, dynamic>) fromMap, {DatumConfig<E>? config, InMemoryLocalAdapter<E>? local}) async {
  final online = MockConnectivityChecker();
  when(() => online.isConnected).thenAnswer((_) async => true);
  when(() => online.onStatusChange).thenAnswer((_) => const Stream.empty());
  final manager = DatumManager<E>(
    localAdapter: local ?? InMemoryLocalAdapter<E>(fromMap: fromMap),
    remoteAdapter: MockRemoteAdapter<E>(fromJson: fromMap),
    connectivity: online,
    datumConfig: config ?? DatumConfig<E>(enableLogging: false),
  );
  await manager.initialize();
  addTearDown(manager.dispose);
  return manager;
}

void main() {
  test('local and remote key names may differ: each side gets its own delta', () async {
    final manager = await _manager(_Split.fromMap);
    final t0 = DateTime.utc(2026, 1, 1), t1 = DateTime.utc(2026, 1, 2);
    await manager.push(item: _Split('s1', 'draft', t0), userId: 'u1');
    await manager.push(item: _Split('s1', 'final', t1, version: 2), userId: 'u1');

    final update = (await manager.getPendingOperations('u1')).last;
    expect(update.delta, {'body': 'final', 'version': 2, 'modifiedAt': t1.toIso8601String()}, reason: 'remote keys and formats');
    final stored = (await manager.read('s1', userId: 'u1'))!;
    expect((stored.body, stored.version, stored.modifiedAt), ('final', 2, t1), reason: 'the local row was patched under its own keys');
  });

  test('a field the entity does not report as changed is left alone on both sides', () async {
    // TestEntity-style custom diff: only `text` counts; createdAt is set once.
    final manager = await _manager(_Pinned.fromMap);
    final t0 = DateTime.utc(2026, 1, 1), t1 = DateTime.utc(2026, 1, 2);
    await manager.push(item: _Pinned('p1', 'a', t0, createdAt: t0), userId: 'u1');
    await manager.synchronize('u1');

    // Same text, different createdAt: not a change, nothing is saved or queued.
    await manager.push(item: _Pinned('p1', 'a', t0, createdAt: t1), userId: 'u1');
    expect((await manager.read('p1', userId: 'u1'))?.createdAt, t0);
    expect(await manager.getPendingCount('u1'), 0);

    // A real change that also carries a different createdAt: the reported
    // fields are saved, createdAt stays what the remote has.
    await manager.push(item: _Pinned('p1', 'b', t1, createdAt: t1, version: 2), userId: 'u1');
    final stored = (await manager.read('p1', userId: 'u1'))!;
    expect((stored.text, stored.version, stored.modifiedAt, stored.createdAt), ('b', 2, t1, t0));
    expect((await manager.getPendingOperations('u1')).single.delta!.keys, unorderedEquals(['text', 'version', 'modifiedAt']));
  });

  test('push(expectedVersion:) refuses to overwrite a row that changed since it was read', () async {
    final manager = await _manager(_Note.fromMap);
    final t0 = DateTime.utc(2026, 1, 1);
    await manager.push(item: _Note('n1', 'v1', t0), userId: 'u1', expectedVersion: null);
    await manager.push(item: _Note('n1', 'v2', t0, version: 2), userId: 'u1', expectedVersion: 1);

    await expectLater(
      manager.push(item: _Note('n1', 'stale edit', t0, version: 2), userId: 'u1', expectedVersion: 1),
      throwsA(isA<ConflictException>().having((e) => e.message, 'message', contains('version 2, expected 1'))),
    );
    expect((await manager.read('n1', userId: 'u1'))?.text, 'v2', reason: 'the newer row is intact');
    expect(await manager.getPendingCount('u1'), 2, reason: 'the refused write queued nothing');

    // Creating with an expectation fails too: there is no such version.
    await expectLater(
      manager.push(item: _Note('n2', 'new', t0), userId: 'u1', expectedVersion: 1),
      throwsA(isA<ConflictException>()),
    );
  });

  test('a store newer than the app is refused when the app versions its schema, and only warned about otherwise', () async {
    final local = InMemoryLocalAdapter<_Note>(fromMap: _Note.fromMap);
    await local.initialize();
    await local.create(_Note('n1', 'from the future', DateTime.utc(2026)));
    await local.setStoredSchemaVersion(5);

    await expectLater(
      _manager(_Note.fromMap, local: local, config: const DatumConfig<_Note>(enableLogging: false, schemaVersion: 2)),
      throwsA(isA<MigrationException>()),
    );
    expect(await local.getStoredSchemaVersion(), 5);
    expect((await local.read('n1', userId: 'u1'))?.text, 'from the future', reason: 'nothing was rewritten');
    expect(await local.getMigrationHistory(), isEmpty);

    // An app that never versioned its schema (0, no migrations) still opens.
    final unversioned = await _manager(_Note.fromMap, local: local);
    expect((await unversioned.read('n1', userId: 'u1'))?.text, 'from the future');
  });

  test('default diff sends remote-format values upstream and patches the local store in local format', () async {
    final online = MockConnectivityChecker();
    when(() => online.isConnected).thenAnswer((_) async => true);
    when(() => online.onStatusChange).thenAnswer((_) => const Stream.empty());
    final local = InMemoryLocalAdapter<_Note>(fromMap: _Note.fromMap);
    final manager = DatumManager<_Note>(
      localAdapter: local,
      remoteAdapter: MockRemoteAdapter<_Note>(fromJson: _Note.fromMap),
      connectivity: online,
      datumConfig: const DatumConfig<_Note>(enableLogging: false),
    );
    await manager.initialize();
    addTearDown(manager.dispose);

    final t0 = DateTime.utc(2026, 1, 1);
    final t1 = DateTime.utc(2026, 1, 2);
    await manager.push(item: _Note('n1', 'draft', t0), userId: 'u1');
    await manager.push(item: _Note('n1', 'final', t1, version: 2), userId: 'u1');

    final update = (await manager.getPendingOperations('u1')).last;
    expect(update.delta, {'text': 'final', 'version': 2, 'modifiedAt': t1.toIso8601String()},
        reason: 'the remote gets ISO timestamps, not epoch ms (Postgres rejects those)');
    final stored = (await manager.read('n1', userId: 'u1'))!;
    expect(stored.text, 'final');
    expect(stored.modifiedAt, t1, reason: 'local patch kept the local epoch-ms format');
  });

  test('retrying a parked update sends the full entity, not its stored delta', () {
    final now = DateTime.utc(2026);
    final parked = DatumSyncOperation<_Note>(
      id: 'op',
      userId: 'u1',
      entityId: 'n1',
      type: DatumOperationType.update,
      timestamp: now,
      data: _Note('n1', 'x', now),
      delta: const {'modifiedAt': 1767225600000},
      parkedError: 'timestamp out of range',
    );
    final retried = parked.unparked();
    expect(retried.isParked, isFalse);
    expect(retried.delta, isNull);
    expect(retried.data?.text, 'x');
    final deleteOp = DatumSyncOperation<_Note>(id: 'd', userId: 'u1', entityId: 'n1', type: DatumOperationType.delete, timestamp: now, delta: const {'k': 1}, parkedError: 'e');
    expect(deleteOp.unparked().delta, {'k': 1}, reason: 'no entity to fall back to');
  });
}
