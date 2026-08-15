/// Conformance suite for **typed queries** (`DatumFieldSpec` /
/// `DatumQueryField` through `DatumQueryBuilder`) against a real adapter.
///
/// Certifies, over one deterministic dataset, that for every uniformly
/// supported operator the adapter returns **identical results** for:
/// 1. the typed path (`whereField` / `orderByField` / spec Filter helpers),
/// 2. the equivalent stringly-typed query, and
/// 3. a reference in-memory evaluation of the seeded dataset.
///
/// Passing certifies typed queries as a supported default on the adapter —
/// SQL push-down or map matching, the results must agree.
///
/// ```dart
/// runTypedQueryConformanceTests(
///   name: 'MyAdapter',
///   createLocal: () async {
///     final adapter = MyAdapter<ConformanceEntity>(fromMap: ConformanceEntity.fromMap);
///     await adapter.initialize();
///     return adapter;
///   },
/// );
/// ```
///
/// Not covered (not uniform across stores): `matches` (regex needs a SQLite
/// extension), `arrayContains`/`arrayContainsAny` (list-typed columns), and
/// cross-case `LIKE` semantics (SQLite `LIKE` is ASCII-case-insensitive
/// while map matching is case-sensitive — probe strings here are
/// case-consistent; use `containsIgnoreCase` when you need case folding).
library;

import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'conformance_entity.dart';

/// Typed field specs for [ConformanceEntity]'s payload.
abstract final class ConformanceFields {
  static final name = DatumFieldSpec<ConformanceEntity, String>(
    'name',
    getter: (e) => e.name,
  );
  static final value = DatumFieldSpec<ConformanceEntity, int>(
    'value',
    getter: (e) => e.value,
  );
}

const _userId = 'conformance-user';

/// 20 rows: values 0–19; names cycle `alpha i` / `beta i` / `gamma tag-i` /
/// `delta tag-i` (all lowercase — see the case note in the library docs).
List<ConformanceEntity> typedQueryConformanceDataset() => [
  for (var i = 0; i < 20; i++)
    ConformanceEntity.make(
      'e${i.toString().padLeft(2, '0')}',
      name: switch (i % 4) {
        0 => 'alpha $i',
        1 => 'beta $i',
        2 => 'gamma tag-$i',
        _ => 'delta tag-$i',
      },
      value: i,
    ),
];

/// Registers the typed-query conformance tests for one local adapter.
void runTypedQueryConformanceTests({
  required String name,
  required Future<LocalAdapter<ConformanceEntity>> Function() createLocal,
  Future<void> Function(LocalAdapter<ConformanceEntity> adapter)? destroyLocal,
}) {
  group('$name typed-query conformance', () {
    late LocalAdapter<ConformanceEntity> adapter;
    final dataset = typedQueryConformanceDataset();

    setUp(() async {
      adapter = await createLocal();
      await adapter.createAll(dataset);
    });

    tearDown(() async {
      await destroyLocal?.call(adapter);
    });

    DatumQueryBuilder<ConformanceEntity> builder() =>
        DatumQueryBuilder<ConformanceEntity>();

    /// Runs [typed] and [stringly] against the adapter and compares both to
    /// the reference evaluation over the seeded dataset.
    Future<void> certify(
      DatumQuery typed,
      DatumQuery stringly,
      Iterable<ConformanceEntity> reference, {
      bool ordered = false,
    }) async {
      final typedIds = (await adapter.query(
        typed,
        userId: _userId,
      )).map((e) => e.id).toList();
      final stringIds = (await adapter.query(
        stringly,
        userId: _userId,
      )).map((e) => e.id).toList();
      final referenceIds = reference.map((e) => e.id).toList();
      if (ordered) {
        expect(
          typedIds,
          stringIds,
          reason: 'typed and string paths must agree',
        );
        expect(
          typedIds,
          referenceIds,
          reason: 'adapter must match the reference evaluation',
        );
      } else {
        expect(
          typedIds.toSet(),
          stringIds.toSet(),
          reason: 'typed and string paths must agree',
        );
        expect(
          typedIds.toSet(),
          referenceIds.toSet(),
          reason: 'adapter must match the reference evaluation',
        );
        expect(
          typedIds.length,
          referenceIds.length,
          reason: 'no duplicate rows',
        );
      }
    }

    test('equals / notEquals', () async {
      await certify(
        builder().whereField(ConformanceFields.value, isEqualTo: 7).build(),
        builder().where('value', isEqualTo: 7).build(),
        dataset.where((e) => e.value == 7),
      );
      await certify(
        builder().whereField(ConformanceFields.value, isNotEqualTo: 7).build(),
        builder().where('value', isNotEqualTo: 7).build(),
        dataset.where((e) => e.value != 7),
      );
    });

    test('ordering comparisons: gt / gte / lt / lte', () async {
      await certify(
        builder()
            .whereField(ConformanceFields.value, isGreaterThan: 15)
            .build(),
        builder().where('value', isGreaterThan: 15).build(),
        dataset.where((e) => e.value > 15),
      );
      await certify(
        builder()
            .whereField(ConformanceFields.value, isGreaterThanOrEqualTo: 15)
            .build(),
        builder().where('value', isGreaterThanOrEqualTo: 15).build(),
        dataset.where((e) => e.value >= 15),
      );
      await certify(
        builder().whereField(ConformanceFields.value, isLessThan: 4).build(),
        builder().where('value', isLessThan: 4).build(),
        dataset.where((e) => e.value < 4),
      );
      await certify(
        builder()
            .whereField(ConformanceFields.value, isLessThanOrEqualTo: 4)
            .build(),
        builder().where('value', isLessThanOrEqualTo: 4).build(),
        dataset.where((e) => e.value <= 4),
      );
    });

    test('between is inclusive on both ends', () async {
      await certify(
        builder().whereField(ConformanceFields.value, between: [5, 9]).build(),
        builder().where('value', between: [5, 9]).build(),
        dataset.where((e) => e.value >= 5 && e.value <= 9),
      );
    });

    test('membership: isIn / isNotIn', () async {
      await certify(
        builder()
            .whereField(ConformanceFields.value, isIn: [1, 3, 19, 42])
            .build(),
        builder().where('value', isIn: [1, 3, 19, 42]).build(),
        dataset.where((e) => const {1, 3, 19, 42}.contains(e.value)),
      );
      await certify(
        builder()
            .whereField(ConformanceFields.value, isNotIn: [1, 3, 19])
            .build(),
        builder().where('value', isNotIn: [1, 3, 19]).build(),
        dataset.where((e) => !const {1, 3, 19}.contains(e.value)),
      );
    });

    test(
      'string operators: contains / startsWith / endsWith / containsIgnoreCase',
      () async {
        await certify(
          builder()
              .whereField(ConformanceFields.name, contains: 'tag-')
              .build(),
          builder().where('name', contains: 'tag-').build(),
          dataset.where((e) => e.name.contains('tag-')),
        );
        await certify(
          builder()
              .whereField(ConformanceFields.name, startsWith: 'alpha')
              .build(),
          builder().where('name', startsWith: 'alpha').build(),
          dataset.where((e) => e.name.startsWith('alpha')),
        );
        await certify(
          builder().whereField(ConformanceFields.name, endsWith: '1').build(),
          builder().where('name', endsWith: '1').build(),
          dataset.where((e) => e.name.endsWith('1')),
        );
        await certify(
          builder()
              .whereField(ConformanceFields.name, containsIgnoreCase: 'GAMMA')
              .build(),
          builder().where('name', containsIgnoreCase: 'GAMMA').build(),
          dataset.where((e) => e.name.toLowerCase().contains('gamma')),
        );
      },
    );

    test(
      'null checks on an always-present column: isNull empty, isNotNull all',
      () async {
        await certify(
          builder().whereFieldNull(ConformanceFields.name).build(),
          builder().whereNull('name').build(),
          const <ConformanceEntity>[],
        );
        await certify(
          builder().whereFieldNotNull(ConformanceFields.name).build(),
          builder().whereNotNull('name').build(),
          dataset,
        );
      },
    );

    test('composite AND of typed filters', () async {
      await certify(
        builder()
            .whereField(
              ConformanceFields.value,
              isGreaterThanOrEqualTo: 4,
              isLessThan: 16,
            )
            .whereField(ConformanceFields.name, contains: 'tag-')
            .build(),
        builder()
            .where('value', isGreaterThanOrEqualTo: 4, isLessThan: 16)
            .where('name', contains: 'tag-')
            .build(),
        dataset.where(
          (e) => e.value >= 4 && e.value < 16 && e.name.contains('tag-'),
        ),
      );
    });

    test('composite OR built from spec Filter helpers', () async {
      await certify(
        builder().or([
          ConformanceFields.value.lessThan(2),
          ConformanceFields.name.equalTo('beta 9'),
        ]).build(),
        builder().or([
          const Filter('value', FilterOperator.lessThan, 2),
          const Filter('name', FilterOperator.equals, 'beta 9'),
        ]).build(),
        dataset.where((e) => e.value < 2 || e.name == 'beta 9'),
      );
    });

    test('orderByField ascending and descending are total orders', () async {
      final ascending = [...dataset]
        ..sort((a, b) => a.value.compareTo(b.value));
      await certify(
        builder().orderByField(ConformanceFields.value).build(),
        builder().orderBy('value').build(),
        ascending,
        ordered: true,
      );
      await certify(
        builder()
            .orderByField(ConformanceFields.value, descending: true)
            .build(),
        builder().orderBy('value', descending: true).build(),
        ascending.reversed,
        ordered: true,
      );
    });

    test('pagination composes with typed filters and ordering', () async {
      final expected =
          ([...dataset]..sort((a, b) => a.value.compareTo(b.value)))
              .where((e) => e.value >= 2)
              .skip(3)
              .take(5);
      await certify(
        (builder()
                .whereField(ConformanceFields.value, isGreaterThanOrEqualTo: 2)
                .orderByField(ConformanceFields.value)
              ..limit(5)
              ..offset(3))
            .build(),
        (builder().where('value', isGreaterThanOrEqualTo: 2).orderBy('value')
              ..limit(5)
              ..offset(3))
            .build(),
        expected,
        ordered: true,
      );
    });

    test('spec Filter helpers drive raw filters identically', () async {
      await certify(
        builder()
            .whereRaw(ConformanceFields.value.greaterThanOrEqual(17))
            .build(),
        builder().where('value', isGreaterThanOrEqualTo: 17).build(),
        dataset.where((e) => e.value >= 17),
      );
      await certify(
        builder()
            .whereRaw(ConformanceFields.name.isIn(['alpha 0', 'delta tag-3']))
            .build(),
        builder().where('name', isIn: ['alpha 0', 'delta tag-3']).build(),
        dataset.where((e) => e.name == 'alpha 0' || e.name == 'delta tag-3'),
      );
    });
  });
}
