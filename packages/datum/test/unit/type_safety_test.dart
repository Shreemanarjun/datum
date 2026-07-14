import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

void main() {
  group('DatumError.from mapping', () {
    test('maps EntityNotFoundException to NotFoundError', () {
      final err = DatumError.from(
        const EntityNotFoundException(message: 'missing'),
      );
      expect(err, isA<NotFoundError>());
      expect(err.message, 'missing');
      expect(err.cause, isA<EntityNotFoundException>());
    });

    test('maps NetworkException to NetworkError preserving isRetryable', () {
      final retry = DatumError.from(
        const NetworkException(message: 'down', isRetryable: true),
      );
      final noRetry = DatumError.from(
        const NetworkException(message: 'down', isRetryable: false),
      );
      expect(retry, isA<NetworkError>());
      expect((retry as NetworkError).isRetryable, isTrue);
      expect((noRetry as NetworkError).isRetryable, isFalse);
    });

    test('maps ConflictException to ConflictError', () {
      expect(
        DatumError.from(const ConflictException(message: 'c')),
        isA<ConflictError>(),
      );
    });

    test('maps validation/badRequest to ValidationError', () {
      expect(
        DatumError.from(const ValidationException(message: 'v')),
        isA<ValidationError>(),
      );
      expect(
        DatumError.from(const BadRequestException(message: 'b')),
        isA<ValidationError>(),
      );
    });

    test('maps adapter/serialization to StorageError', () {
      expect(
        DatumError.from(const AdapterException(message: 'a', error: 'e')),
        isA<StorageError>(),
      );
      expect(
        DatumError.from(const SerializationException(message: 's')),
        isA<StorageError>(),
      );
    });

    test('maps auth/cancelled/unknown to UnknownError', () {
      expect(
        DatumError.from(const AuthenticationException(message: 'auth')),
        isA<UnknownError>(),
      );
      expect(
        DatumError.from(const CancellationException(message: 'x')),
        isA<UnknownError>(),
      );
    });

    test('wraps arbitrary objects as UnknownError preserving cause', () {
      final err = DatumError.from('boom');
      expect(err, isA<UnknownError>());
      expect(err.message, 'boom');
      expect(err.cause, 'boom');
    });

    test('is idempotent on an existing DatumError', () {
      const original = NotFoundError('x');
      expect(DatumError.from(original), same(original));
    });

    test('equality is by case + message', () {
      expect(const NotFoundError('x'), const NotFoundError('x'));
      expect(const NotFoundError('x'), isNot(const ConflictError('x')));
      expect(
        const NetworkError('x', isRetryable: true),
        isNot(const NetworkError('x', isRetryable: false)),
      );
    });
  });

  group('Typed query field selectors', () {
    const name = DatumQueryField<TestEntity, String>('name');
    const value = DatumQueryField<TestEntity, int>('value');

    test('whereField produces the same query as string where', () {
      final typed = (DatumQueryBuilder<TestEntity>()
            ..whereField(value, isGreaterThanOrEqualTo: 2)
            ..whereField(name, isEqualTo: 'a'))
          .build();
      final stringly = (DatumQueryBuilder<TestEntity>()
            ..where('value', isGreaterThanOrEqualTo: 2)
            ..where('name', isEqualTo: 'a'))
          .build();
      expect(typed.toString(), stringly.toString());
    });

    test('orderByField produces the same sort as string orderBy', () {
      final typed = (DatumQueryBuilder<TestEntity>()..orderByField(value, descending: true)).build();
      final stringly = (DatumQueryBuilder<TestEntity>()..orderBy('value', descending: true)).build();
      expect(typed.toString(), stringly.toString());
    });

    test('field operator helpers build Filters with the right shape', () {
      final f = value.greaterThan(5);
      expect(f.field, 'value');
      expect(f.operator, FilterOperator.greaterThan);
      expect(f.value, 5);

      final inFilter = name.isIn(['a', 'b']);
      expect(inFilter.operator, FilterOperator.isIn);
      expect(inFilter.value, ['a', 'b']);

      expect(value.isNull.operator, FilterOperator.isNull);
      expect(name.isNotNull.operator, FilterOperator.isNotNull);
    });

    test('whereFieldNull / whereFieldNotNull delegate correctly', () {
      final q = (DatumQueryBuilder<TestEntity>()
            ..whereFieldNull(name)
            ..whereFieldNotNull(value))
          .build();
      final filters = q.filters.cast<Filter>();
      expect(filters[0].operator, FilterOperator.isNull);
      expect(filters[1].operator, FilterOperator.isNotNull);
    });
  });

  group('TypeSafeManagerRegistry hardening', () {
    test('tryGet returns null for unregistered type; get throws', () {
      final registry = TypeSafeManagerRegistry();
      expect(registry.tryGet<TestEntity>(), isNull);
      expect(registry.getByTypeOrNull(TestEntity), isNull);
      expect(() => registry.get<TestEntity>(), throwsStateError);
    });

    test('register then get/tryGet return the same manager', () async {
      final manager = DatumManager<TestEntity>(
        localAdapter: MockLocalAdapter<TestEntity>(),
        remoteAdapter: MockRemoteAdapter<TestEntity>(),
        connectivity: _connected(),
        datumConfig: const DatumConfig<TestEntity>(schemaVersion: 0),
      );
      await manager.initialize();
      addTearDown(manager.dispose);

      final registry = TypeSafeManagerRegistry()..register<TestEntity>(manager);
      expect(registry.get<TestEntity>(), same(manager));
      expect(registry.tryGet<TestEntity>(), same(manager));
      expect(registry.getByTypeOrNull(TestEntity), same(manager));
      expect(registry.isRegistered(TestEntity), isTrue);
    });
  });

  group('Manager tryX result API', () {
    late MockLocalAdapter<TestEntity> local;
    late MockRemoteAdapter<TestEntity> remote;
    late DatumManager<TestEntity> manager;

    setUp(() async {
      local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      remote = MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      manager = DatumManager<TestEntity>(
        localAdapter: local,
        remoteAdapter: remote,
        connectivity: _connected(),
        datumConfig: const DatumConfig<TestEntity>(schemaVersion: 0),
      );
      await manager.initialize();
    });

    tearDown(() => manager.dispose());

    test('tryRead returns Success(null) when absent', () async {
      final result = await manager.tryRead('nope', userId: 'u1');
      expect(result.isSuccess(), isTrue);
      expect(result.successOrNull, isNull);
    });

    test('tryPush then tryRead round-trips through Success', () async {
      final pushed = await manager.tryPush(
        item: TestEntity.create('e1', 'u1', 'Hello'),
        userId: 'u1',
      );
      expect(pushed.isSuccess(), isTrue);

      final read = await manager.tryRead('e1', userId: 'u1');
      expect(read.isSuccess(), isTrue);
      expect(read.successOrNull?.name, 'Hello');
    });

    test('tryQuery returns Success with a list', () async {
      await manager.tryPush(item: TestEntity.create('e1', 'u1', 'A'), userId: 'u1');
      final result = await manager.tryQuery(
        (DatumQueryBuilder<TestEntity>()..where('name', isEqualTo: 'A')).build(),
        source: DataSource.local,
        userId: 'u1',
      );
      expect(result.isSuccess(), isTrue);
      expect(result.successOrNull, isNotEmpty);
    });

    test('returns Failure(DatumError) when the call throws', () async {
      // A fresh, un-initialized manager throws StateError from _ensureInitialized.
      final uninitialized = DatumManager<TestEntity>(
        localAdapter: MockLocalAdapter<TestEntity>(),
        remoteAdapter: MockRemoteAdapter<TestEntity>(),
        connectivity: _connected(),
        datumConfig: const DatumConfig<TestEntity>(schemaVersion: 0),
      );
      final result = await uninitialized.tryQuery(
        DatumQueryBuilder<TestEntity>().build(),
        source: DataSource.local,
        userId: 'u1',
      );
      expect(result.isFailure(), isTrue);
      final (error, _) = result.getError();
      expect(error, isA<DatumError>());
    });
  });
}

MockConnectivityChecker _connected() {
  final c = MockConnectivityChecker();
  when(() => c.isConnected).thenAnswer((_) async => true);
  when(() => c.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  return c;
}
