import 'package:datum/datum.dart';
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Regression tests for query-path bugs found in the 2026-08 audit:
///
/// 1. User scoping was appended flat to the query's filter list, so under
///    `LogicalOperator.or` the `userId = ?` clause became just another OR
///    alternative — returning OTHER USERS' rows (cross-tenant leak) plus
///    same-user rows that didn't match the filters.
/// 2. DateTime filter values were handed raw to sqlite3's binder, which
///    rejects them with an ArgumentError.
/// 3. LIKE values were interpolated unescaped, so `%`/`_` in user values
///    acted as wildcards instead of literals.
/// 4. OFFSET without LIMIT generated invalid SQLite syntax.
void main() {
  late Database db;
  late SqliteLocalAdapter<ConformanceEntity> adapter;

  ConformanceEntity entity(
    String id,
    String userId, {
    String name = '',
    int value = 0,
    DateTime? createdAt,
  }) => ConformanceEntity(
    id: id,
    userId: userId,
    name: name,
    value: value,
    modifiedAt: createdAt ?? DateTime.utc(2026),
    createdAt: createdAt ?? DateTime.utc(2026),
    version: 1,
  );

  setUp(() async {
    db = sqlite3.openInMemory();
    adapter = SqliteLocalAdapter<ConformanceEntity>(
      database: db,
      table: 'regressions',
      fromMap: ConformanceEntity.fromMap,
      columns: const {'name': 'TEXT', 'value': 'INTEGER'},
    );
    await adapter.initialize();
  });

  tearDown(() => db.dispose());

  test('OR queries never leak other users\' rows', () async {
    await adapter.create(entity('a1', 'u1', name: 'alpha', value: 1));
    await adapter.create(entity('a2', 'u1', name: 'beta', value: 2));
    await adapter.create(entity('b1', 'u2', name: 'gamma', value: 3));

    final result = await adapter.query(
      const DatumQuery(
        filters: [
          Filter('value', FilterOperator.equals, 3),
          Filter('name', FilterOperator.equals, 'nope'),
        ],
        logicalOperator: LogicalOperator.or,
      ),
      userId: 'u1',
    );

    expect(
      result,
      isEmpty,
      reason: "u2's value==3 row must not satisfy an OR query scoped to u1",
    );

    final matching = await adapter.query(
      const DatumQuery(
        filters: [
          Filter('value', FilterOperator.equals, 1),
          Filter('name', FilterOperator.equals, 'beta'),
        ],
        logicalOperator: LogicalOperator.or,
      ),
      userId: 'u1',
    );
    expect(
      matching.map((e) => e.id).toSet(),
      {'a1', 'a2'},
      reason: 'OR semantics must survive the scoping',
    );
  });

  test(
    'DateTime filter values are encoded, not rejected by the binder',
    () async {
      await adapter.create(entity('old', 'u1', createdAt: DateTime.utc(2020)));
      await adapter.create(entity('new', 'u1', createdAt: DateTime.utc(2026)));

      final result = await adapter.query(
        DatumQuery(
          filters: [
            Filter('createdAt', FilterOperator.greaterThan, DateTime.utc(2023)),
          ],
        ),
        userId: 'u1',
      );
      expect(result.map((e) => e.id).toList(), ['new']);
    },
  );

  test('LIKE values are literal: % and _ do not act as wildcards', () async {
    await adapter.create(entity('e1', 'u1', name: '100% cotton'));
    await adapter.create(entity('e2', 'u1', name: '100 pct'));
    await adapter.create(entity('e3', 'u1', name: 'xa_cy'));
    await adapter.create(entity('e4', 'u1', name: 'xabcy'));

    final percent = await adapter.query(
      const DatumQuery(
        filters: [Filter('name', FilterOperator.contains, '100%')],
      ),
      userId: 'u1',
    );
    expect(percent.map((e) => e.id).toList(), ['e1']);

    final underscore = await adapter.query(
      const DatumQuery(
        filters: [Filter('name', FilterOperator.contains, 'a_c')],
      ),
      userId: 'u1',
    );
    expect(underscore.map((e) => e.id).toList(), ['e3']);
  });

  test('offset without limit is valid SQL', () async {
    await adapter.create(entity('e1', 'u1', value: 1));
    await adapter.create(entity('e2', 'u1', value: 2));
    await adapter.create(entity('e3', 'u1', value: 3));

    final result = await adapter.query(
      const DatumQuery(sorting: [SortDescriptor('value')], offset: 1),
      userId: 'u1',
    );
    expect(result.map((e) => e.value).toList(), [2, 3]);
  });
}
