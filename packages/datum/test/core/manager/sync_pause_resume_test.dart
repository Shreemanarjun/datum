import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../mocks/mock_adapters.dart';
import '../../mocks/mock_connectivity_checker.dart';
import '../../mocks/test_entity.dart';

void main() {
  late MockLocalAdapter<TestEntity> localAdapter;
  late MockRemoteAdapter<TestEntity> remoteAdapter;
  late MockConnectivityChecker connectivityChecker;
  late DatumManager<TestEntity> manager;

  setUp(() async {
    localAdapter = MockLocalAdapter<TestEntity>();
    remoteAdapter = MockRemoteAdapter<TestEntity>();
    connectivityChecker = MockConnectivityChecker();
    when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

    manager = DatumManager<TestEntity>(
      localAdapter: localAdapter,
      remoteAdapter: remoteAdapter,
      connectivity: connectivityChecker,
      datumConfig: const DatumConfig<TestEntity>(
        schemaVersion: 0,
        autoSyncInterval: Duration(minutes: 15),
      ),
    );
    await manager.initialize();
  });

  tearDown(() {
    manager.dispose();
  });

  test('should restore auto-sync timers after pause and resume', () async {
    const userId = 'test-user';

    // 1. Start auto-sync
    manager.startAutoSync(userId);

    // Verify it's scheduled
    var nextSyncTime = await manager.getNextSyncTime();
    expect(nextSyncTime, isNotNull, reason: 'Auto-sync should be scheduled after startAutoSync');

    // 2. Pause sync
    manager.pauseSync();

    // Verify it's stopped
    nextSyncTime = await manager.getNextSyncTime();
    expect(nextSyncTime, isNull, reason: 'Auto-sync should be stopped after pauseSync');

    // 3. Resume sync
    manager.resumeSync();

    // Verify it's restored
    nextSyncTime = await manager.getNextSyncTime();
    expect(nextSyncTime, isNotNull, reason: 'Auto-sync should be restored after resumeSync');
  });

  test('restores auto-sync for multiple users after pause/resume (#2)', () async {
    manager.startAutoSync('user-a');
    manager.startAutoSync('user-b');
    expect(await manager.getNextSyncTime(), isNotNull);

    manager.pauseSync();
    expect(await manager.getNextSyncTime(), isNull);

    manager.resumeSync();

    // Both users' timers must be restored. getPendingCount is unrelated; we
    // assert both by stopping one and confirming a timer still remains, then
    // stopping the other clears it.
    expect(await manager.getNextSyncTime(), isNotNull, reason: 'timers restored');
    manager.stopAutoSync(userId: 'user-a');
    expect(await manager.getNextSyncTime(), isNotNull, reason: 'user-b still scheduled');
    manager.stopAutoSync(userId: 'user-b');
    expect(await manager.getNextSyncTime(), isNull, reason: 'all stopped');
  });

  test('resume after an explicit stopAutoSync() while paused restores nothing (#2)', () async {
    manager.startAutoSync('user-a');
    manager.pauseSync();

    // Explicitly stopping all auto-sync while paused is an intentional opt-out:
    // resume should NOT bring the timers back.
    manager.stopAutoSync();
    manager.resumeSync();

    expect(await manager.getNextSyncTime(), isNull);
  });
}
