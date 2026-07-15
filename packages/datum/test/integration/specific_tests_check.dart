import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

void main() {
  late MockLocalAdapter<TestEntity> localAdapter;
  late MockRemoteAdapter<TestEntity> remoteAdapter;
  late MockConnectivityChecker connectivityChecker;

  setUp(() async {
    localAdapter = MockLocalAdapter<TestEntity>();
    remoteAdapter = MockRemoteAdapter<TestEntity>();
    connectivityChecker = MockConnectivityChecker();

    // Reset Datum for testing
    Datum.resetForTesting();
  });

  tearDown(() async {
    await Datum.instance.dispose();
  });

  group('Specific Test Checks', () {
    test('cold start state management works correctly', () async {
      await Datum.initialize(
        config: const DatumConfig(
          coldStartConfig: ColdStartConfig(
            strategy: ColdStartStrategy.disabled, // Disable to test state management
          ),
        ),
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<TestEntity>(
            localAdapter: localAdapter,
            remoteAdapter: remoteAdapter,
          ),
        ],
      );

      final manager = Datum.manager<TestEntity>();
      const userId = 'testUser';

      // Initially should be cold start (default state)
      expect(Datum.instance.isColdStartForUser<TestEntity>(userId), isTrue);

      // Reset cold start state (useful for testing)
      manager.coldStartManager.resetForUser(userId);
      expect(Datum.instance.isColdStartForUser<TestEntity>(userId), isTrue); // Reset keeps it as cold start

      // Verify that resetForUser maintains cold start state
      expect(manager.coldStartManager.isColdStartForUser(userId), isTrue);

      // Verify last cold start time is reset
      expect(manager.coldStartManager.getLastColdStartTimeForUser(userId), isNull);
    });
  });
}
