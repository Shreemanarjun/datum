import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class FailingLocalAdapter extends InMemoryLocalAdapter<TestEntity> {
  FailingLocalAdapter() : super(fromMap: TestEntity.fromJson);
  @override
  Future<void> initialize() async => throw StateError('storage unavailable');
}

MockConnectivityChecker _conn() {
  final c = MockConnectivityChecker();
  when(() => c.isConnected).thenAnswer((_) async => true);
  when(() => c.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return c;
}

void main() {
  tearDown(Datum.resetForTesting);

  test('Datum.initialize returns a typed, throwable DatumError on failure', () async {
    Datum.resetForTesting();
    final result = await Datum.initialize(
      config: const DatumConfig(enableLogging: false),
      connectivityChecker: _conn(),
      registrations: [
        DatumRegistration<TestEntity>(localAdapter: FailingLocalAdapter(), remoteAdapter: MockRemoteAdapter<TestEntity>()),
      ],
    );

    expect(result.isFailure(), isTrue);
    final DatumError? error = result.failure;
    expect(error, isA<DatumError>());
    expect(error, isA<Exception>(), reason: 'DatumError can be rethrown');

    // The failure side is statically typed as DatumError (compile-time proof).
    result.onFailure((e, s) => expect(e, isA<DatumError>()));
  });

  test('successful initialize yields a Datum instance', () async {
    Datum.resetForTesting();
    final result = await Datum.initialize(
      config: const DatumConfig(enableLogging: false),
      connectivityChecker: _conn(),
      registrations: [
        DatumRegistration<TestEntity>(localAdapter: InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson), remoteAdapter: MockRemoteAdapter<TestEntity>()),
      ],
    );
    expect(result.isSuccess(), isTrue);
    expect(result.success, isA<Datum>());
  });
}
