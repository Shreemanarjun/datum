/// Reads the **actual** stored shape of an entity's data so the
/// auto-migration differ can compare it against the declared [DatumSchema].
library;

import 'package:datum/source/adapter/adapter_capabilities.dart';
import 'package:datum/source/adapter/local_adapter.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/query/datum_query_sql_converter.dart';
import 'package:datum/source/core/query/datum_raw_query.dart';

/// The observed shape of a store.
///
/// On the SQL path [allKeys] and [universalKeys] are identical (every row has
/// every column); on the raw-data path [allKeys] is the union and
/// [universalKeys] the intersection of keys across rows — a key in the union
/// but not the intersection exists on some rows only and still needs an
/// add-with-backfill.
typedef SchemaShape = ({Set<String> allKeys, Set<String> universalKeys, int rowCount});

/// Produces a [SchemaShape] for one entity store.
abstract interface class SchemaIntrospector {
  Future<SchemaShape> introspect();
}

/// Introspects a SQL table's real columns through the adapter's own
/// [RawQueryCapable.rawQuery] — `PRAGMA table_info` on SQLite,
/// `information_schema.columns` on PostgreSQL. No adapter API changes needed.
class SqlSchemaIntrospector implements SchemaIntrospector {
  SqlSchemaIntrospector({required this.adapter, required this.table, required this.dialect}) : assert(dialect != SqlDialect.custom, 'custom dialects use the raw-data introspector');

  final RawQueryCapable adapter;
  final String table;
  final SqlDialect dialect;

  @override
  Future<SchemaShape> introspect() async {
    final (sql, args, nameKey) = switch (dialect) {
      SqlDialect.sqlite => ('PRAGMA table_info("${table.replaceAll('"', '""')}")', const <Object?>[], 'name'),
      _ => (
          'SELECT column_name FROM information_schema.columns WHERE table_name = ?',
          <Object?>[table],
          'column_name',
        ),
    };
    final rows = await adapter.rawQuery(DatumRawQuery(sql: sql, args: args));
    final columns = {for (final row in rows) row[nameKey] as String};
    final countRows = await adapter.rawQuery(
      DatumRawQuery(sql: 'SELECT COUNT(*) AS c FROM "${table.replaceAll('"', '""')}"'),
    );
    final count = (countRows.first.values.first as num).toInt();
    return (allKeys: columns, universalKeys: columns, rowCount: count);
  }
}

/// Introspects a schemaless store (Hive, in-memory, …) from its raw rows —
/// one `getAllRawData()` pass computing the key union, intersection, and
/// row count.
class RawDataSchemaIntrospector<T extends DatumEntityInterface> implements SchemaIntrospector {
  RawDataSchemaIntrospector(this.adapter);

  final LocalAdapter<T> adapter;

  @override
  Future<SchemaShape> introspect() async {
    final rows = await adapter.getAllRawData();
    if (rows.isEmpty) {
      return (allKeys: const <String>{}, universalKeys: const <String>{}, rowCount: 0);
    }
    final union = <String>{};
    Set<String>? intersection;
    for (final row in rows) {
      final keys = row.keys.toSet();
      union.addAll(keys);
      intersection = intersection == null ? keys : intersection.intersection(keys);
    }
    return (allKeys: union, universalKeys: intersection!, rowCount: rows.length);
  }
}
