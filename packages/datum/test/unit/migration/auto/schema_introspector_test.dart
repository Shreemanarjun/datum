import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../../schema/schema_test_entity.dart';

class _FakeRawDataAdapter implements LocalAdapter<SchemaTask> {
  _FakeRawDataAdapter(this.rows);
  final List<Map<String, dynamic>> rows;

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async => rows;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSqlAdapter with RawQueryCapable {
  _FakeSqlAdapter({required this.columns, required this.rowCount});
  final List<String> columns;
  final int rowCount;
  final queries = <DatumRawQuery>[];

  @override
  Future<List<DatumRawRow>> rawQuery(DatumRawQuery query, {String? userId}) async {
    queries.add(query);
    final sql = query.sql!;
    if (sql.startsWith('PRAGMA')) {
      return [
        for (final (i, c) in columns.indexed) {'cid': i, 'name': c, 'type': 'TEXT'}
      ];
    }
    if (sql.contains('information_schema')) {
      return [
        for (final c in columns) {'column_name': c}
      ];
    }
    return [
      {'c': rowCount}
    ];
  }
}

void main() {
  group('RawDataSchemaIntrospector', () {
    test('empty store yields empty shape with zero rows', () async {
      final shape = await RawDataSchemaIntrospector(_FakeRawDataAdapter([])).introspect();
      expect(shape.allKeys, isEmpty);
      expect(shape.universalKeys, isEmpty);
      expect(shape.rowCount, 0);
    });

    test('computes union, intersection, and count over heterogeneous rows', () async {
      final shape = await RawDataSchemaIntrospector(_FakeRawDataAdapter([
        {'id': '1', 'title': 'a', 'legacy': true},
        {'id': '2', 'title': 'b', 'priority': 1},
        {'id': '3', 'title': 'c', 'priority': 2},
      ])).introspect();
      expect(shape.allKeys, {'id', 'title', 'legacy', 'priority'});
      expect(shape.universalKeys, {'id', 'title'});
      expect(shape.rowCount, 3);
    });
  });

  group('SqlSchemaIntrospector', () {
    test('sqlite path reads PRAGMA table_info and COUNT', () async {
      final adapter = _FakeSqlAdapter(columns: ['id', 'title', 'priority'], rowCount: 7);
      final shape = await SqlSchemaIntrospector(
        adapter: adapter,
        table: 'tasks',
        dialect: SqlDialect.sqlite,
      ).introspect();
      expect(shape.allKeys, {'id', 'title', 'priority'});
      expect(shape.universalKeys, shape.allKeys);
      expect(shape.rowCount, 7);
      expect(adapter.queries.first.sql, 'PRAGMA table_info("tasks")');
      expect(adapter.queries.last.sql, contains('COUNT(*)'));
    });

    test('postgresql path reads information_schema with a bound table name', () async {
      final adapter = _FakeSqlAdapter(columns: ['id', 'name'], rowCount: 0);
      final shape = await SqlSchemaIntrospector(
        adapter: adapter,
        table: 'tasks',
        dialect: SqlDialect.postgresql,
      ).introspect();
      expect(shape.allKeys, {'id', 'name'});
      expect(adapter.queries.first.sql, contains('information_schema.columns'));
      expect(adapter.queries.first.args, ['tasks']);
    });

    test('table identifiers are quoted against injection', () async {
      final adapter = _FakeSqlAdapter(columns: ['id'], rowCount: 0);
      await SqlSchemaIntrospector(
        adapter: adapter,
        table: 'ta"sks',
        dialect: SqlDialect.sqlite,
      ).introspect();
      expect(adapter.queries.first.sql, 'PRAGMA table_info("ta""sks")');
    });

    test('rejects the custom dialect', () {
      expect(
        () => SqlSchemaIntrospector(
          adapter: _FakeSqlAdapter(columns: const [], rowCount: 0),
          table: 't',
          dialect: SqlDialect.custom,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
