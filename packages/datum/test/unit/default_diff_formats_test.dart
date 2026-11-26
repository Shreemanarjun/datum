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

void main() {
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
