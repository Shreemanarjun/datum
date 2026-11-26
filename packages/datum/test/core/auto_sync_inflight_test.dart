import 'dart:async';

import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';

class _Item extends DatumEntity {
  const _Item(this.id);
  @override
  final String id;
  @override
  String get userId => 'u1';
  @override
  DateTime get modifiedAt => DateTime.utc(2026);
  @override
  DateTime get createdAt => DateTime.utc(2026);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;
  static _Item fromMap(Map<String, dynamic> m) => _Item(m['id'] as String);
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      {'id': id, 'userId': userId, 'modifiedAt': modifiedAt.toIso8601String(), 'createdAt': createdAt.toIso8601String(), 'version': version, 'isDeleted': isDeleted};
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => null;
}

/// A remote whose pulls block until released, to hold a sync in flight.
class _GatedRemote extends MockRemoteAdapter<_Item> {
  _GatedRemote() : super(fromJson: _Item.fromMap);
  int pulls = 0;
  Completer<void> gate = Completer<void>();
  final _inFlight = StreamController<void>.broadcast();
  Stream<void> get pullStarted => _inFlight.stream;

  @override
  Future<List<_Item>> readAll({String? userId, DatumSyncScope? scope}) async {
    pulls++;
    _inFlight.add(null);
    await gate.future;
    return super.readAll(userId: userId, scope: scope);
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => null; // never skip
}

class _Online implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}

/// The auto-sync timer removes itself while its sync runs. A stop/pause that
/// lands in that window must still end the schedule — previously the
/// in-flight run rescheduled itself forever after `stopAutoSync()`, and
/// `pauseSync()` forgot the user so `resumeSync()` never restarted it.
void main() {
  late _GatedRemote remote;
  late DatumManager<_Item> m;

  setUp(() async {
    remote = _GatedRemote();
    m = DatumManager<_Item>(
      localAdapter: InMemoryLocalAdapter<_Item>(fromMap: _Item.fromMap),
      remoteAdapter: remote,
      connectivity: _Online(),
      datumConfig: const DatumConfig(enableLogging: false, autoStartSync: false),
    );
    await m.initialize();
  });

  tearDown(() async {
    if (!remote.gate.isCompleted) remote.gate.complete();
    await m.dispose();
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

  test('stopAutoSync during an in-flight sync ends the schedule', () async {
    m.startAutoSync('u1', interval: const Duration(milliseconds: 5));
    await remote.pullStarted.first; // sync #1 is now in flight, timer gone
    m.stopAutoSync(userId: 'u1');
    remote.gate.complete();
    await settle();
    expect(remote.pulls, 1, reason: 'the in-flight run must not reschedule');
    expect(await m.getNextSyncTime(), isNull);

    // Restarting works and stop-all also ends an in-flight run.
    remote.gate = Completer<void>();
    m.startAutoSync('u1', interval: const Duration(milliseconds: 5));
    await remote.pullStarted.first;
    m.stopAutoSync();
    remote.gate.complete();
    await settle();
    expect(remote.pulls, 2);
  });

  test('pause during an in-flight sync is resumed with the same interval', () async {
    m.startAutoSync('u1', interval: const Duration(milliseconds: 5));
    await remote.pullStarted.first;
    m.pauseSync();
    remote.gate.complete();
    await settle();
    expect(remote.pulls, 1, reason: 'paused: no new cycles');

    m.resumeSync();
    await settle();
    expect(remote.pulls, greaterThan(3), reason: 'resumed at the 5ms interval, not the 10-minute default');
    m.stopAutoSync();
  });
}
