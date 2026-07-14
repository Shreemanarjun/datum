import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

void main() {
  group('DatumConfig.copyWith<T>() resolver preservation (bug fix)', () {
    test('preserves a global default resolver when deriving a typed config', () {
      // A global resolver is typed <DatumEntityInterface>.
      final global = DatumConfig(
        defaultConflictResolver: LastWriteWinsResolver<DatumEntityInterface>(),
      );

      // Deriving a per-entity config must NOT drop the resolver (the bug).
      final derived = global.copyWith<TestEntity>();

      expect(derived.defaultConflictResolver, isNotNull);
      expect(
        derived.defaultConflictResolver,
        isA<DatumConflictResolver<TestEntity>>(),
      );
    });

    test('the adapted resolver actually resolves and returns typed data', () async {
      final global = DatumConfig(
        defaultConflictResolver: LastWriteWinsResolver<DatumEntityInterface>(),
      );
      final derived = global.copyWith<TestEntity>();

      final local = TestEntity.create('e1', 'u1', 'local').copyWith(version: 1, modifiedAt: DateTime(2024, 1, 1));
      final remote = TestEntity.create('e1', 'u1', 'remote').copyWith(version: 2, modifiedAt: DateTime(2024, 1, 2));

      final resolution = await derived.defaultConflictResolver!.resolve(
        local: local,
        remote: remote,
        context: DatumConflictContext(
          userId: 'u1',
          entityId: 'e1',
          type: DatumConflictType.bothModified,
          detectedAt: DateTime(2024, 1, 2),
        ),
      );

      // Last-write-wins picks the higher version (remote), and the result is
      // correctly typed as TestEntity (not DatumEntityInterface).
      expect(resolution.resolvedData, isA<TestEntity>());
      expect(resolution.resolvedData?.name, 'remote');
    });

    test('an already-correctly-typed resolver is passed through unchanged', () {
      final resolver = LastWriteWinsResolver<TestEntity>();
      final config = DatumConfig<TestEntity>(defaultConflictResolver: resolver);
      final copied = config.copyWith<TestEntity>();
      expect(copied.defaultConflictResolver, same(resolver));
    });

    test('null resolver stays null', () {
      const global = DatumConfig();
      final derived = global.copyWith<TestEntity>();
      expect(derived.defaultConflictResolver, isNull);
    });

    test('TypeAdaptedConflictResolver forwards name', () {
      final base = LastWriteWinsResolver<DatumEntityInterface>();
      final adapted = TypeAdaptedConflictResolver<TestEntity, DatumEntityInterface>(base);
      expect(adapted.name, base.name);
    });
  });
}
