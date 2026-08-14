import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

MockConnectivityChecker _connected() {
  final c = MockConnectivityChecker();
  when(() => c.isConnected).thenAnswer((_) async => true);
  when(() => c.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return c;
}

void main() {
  tearDown(() async {
    if (Datum.instanceOrNull != null) {
      await Datum.instance.dispose();
    }
    Datum.resetForTesting();
  });

  test('CustomManagerConfig injects the provided manager during Datum.initialize', () async {
    Datum.resetForTesting();

    final local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    final remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
    final connectivity = _connected();

    final injected = DatumManager<TestEntity>(
      localAdapter: local,
      remoteAdapter: remote,
      connectivity: connectivity,
      datumConfig: const DatumConfig<TestEntity>(enableLogging: false),
    );

    final customConfig = CustomManagerConfig<TestEntity>(injected);
    expect(customConfig.mockManager, same(injected));

    final result = await Datum.initialize(
      config: const DatumConfig(enableLogging: false),
      connectivityChecker: connectivity,
      registrations: [
        DatumRegistration<TestEntity>(
          localAdapter: local,
          remoteAdapter: remote,
          config: customConfig,
        ),
      ],
    );

    expect(result.isSuccess(), isTrue);
    expect(
      identical(Datum.manager<TestEntity>(), injected),
      isTrue,
      reason: 'the testing hook must hand back the injected manager instead of building a new one',
    );
  });
}
