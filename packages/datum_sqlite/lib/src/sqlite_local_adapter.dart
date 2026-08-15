import 'dart:async';
import 'dart:convert';

import 'package:datum/datum.dart';
import 'package:sqlite3/sqlite3.dart';

/// A [LocalAdapter] backed by a real SQLite database (`package:sqlite3`).
///
/// Unlike schemaless adapters, entities live in a real table with one column
/// per field, which unlocks the SQL-native half of the Datum feature set:
///
/// - **Query pushdown** — [query] compiles the [DatumQuery] to SQL via
///   `toSql` and lets SQLite filter/sort/limit, instead of loading
///   everything and matching in memory.
/// - **Real transactions** — [transaction] maps to `BEGIN`/`COMMIT`/
///   `ROLLBACK`, and SQLite rolls DDL and DML back together.
/// - **Native schema migrations** — mixes in [RawQueryCapable], so
///   `SqlMigrationExecutor` can run `SchemaMigration` chains as real
///   `ALTER TABLE`/`UPDATE` statements against the table.
/// - **Reactive watch streams** — change-notified re-reads, advertised via
///   [WatchableAdapter].
///
/// ```dart
/// final adapter = SqliteLocalAdapter<Task>(
///   database: sqlite3.open('app.db'), // or sqlite3.openInMemory()
///   table: 'tasks',
///   fromMap: Task.fromMap,
///   columns: {'title': 'TEXT', 'priority': 'INTEGER', 'done': 'BOOLEAN'},
/// );
/// await adapter.initialize();
/// ```
///
/// [columns] declares the entity's payload columns (`toDatumMap` keys →
/// SQLite types); the sync core columns (`id`, `userId`, `modifiedAt`,
/// `createdAt`, `version`, `isDeleted`) are created automatically. Columns
/// declared `BOOLEAN` are stored as 0/1 and decoded back to `bool`.
///
/// On Flutter, add `sqlite3_flutter_libs` to bundle the SQLite binary.
class SqliteLocalAdapter<T extends DatumEntityInterface> extends LocalAdapter<T>
    with
        TransactionalAdapter,
        PaginatedAdapter,
        WatchableAdapter,
        RawQueryCapable,
        SqlSchemaCapable,
        SchemaFingerprintCapable {
  SqliteLocalAdapter({
    required this.database,
    required this.table,
    required this.fromMap,
    this.columns = const {},
    this.schema,
    this.strictColumns = false,
  });

  /// The open SQLite database. The adapter does not own it exclusively;
  /// several adapters (one per entity type) can share one database.
  final Database database;

  /// The table entities of type [T] live in.
  final String table;

  /// Deserializes a row map into an entity.
  final T Function(Map<String, dynamic> map) fromMap;

  /// Payload columns: `toDatumMap` key → SQLite column type. When empty and
  /// [schema] is given, the payload columns are derived from it instead.
  final Map<String, String> columns;

  /// The declared runtime schema; derives the payload columns when [columns]
  /// is empty, and backs `DatumConfig.autoMigrate` reconciliation.
  final DatumSchema<T>? schema;

  /// When true, writing or patching a payload key that is not a declared
  /// column throws instead of silently dropping it.
  final bool strictColumns;

  // Rows are keyed by (id, userId): different users may own the same entity
  // id, matching the LocalAdapter contract. A single-column id PK let one
  // user's INSERT OR REPLACE silently overwrite another user's row.
  static const Map<String, String> _coreColumns = {
    'id': 'TEXT NOT NULL',
    'userId': 'TEXT NOT NULL',
    'modifiedAt': 'TEXT',
    'createdAt': 'TEXT',
    'version': 'INTEGER',
    'isDeleted': 'BOOLEAN',
  };

  final _changeController = StreamController<DatumChangeDetail<T>>.broadcast();

  String get _pendingOpsTable => '${table}__pending_ops';
  String get _syncStateTable => '${table}__sync_state';
  String get _metaTable => '${table}__meta';

  @override
  String get sqlTable => table;

  String _q(String ident) => '"${ident.replaceAll('"', '""')}"';

  /// The effective payload columns: explicit [columns] win, else derived
  /// from [schema] (minus the core sync columns it also declares).
  late final Map<String, String> _payloadColumns = columns.isNotEmpty
      ? columns
      : ({...?schema?.sqlColumns()}
          ..removeWhere((key, _) => _coreColumns.containsKey(key)));

  /// Every column of the entity table, in declaration order.
  late final List<String> _allColumns = [
    ..._coreColumns.keys,
    ..._payloadColumns.keys,
  ];

  /// Columns decoded back to `bool` (declared BOOLEAN, or the core flag).
  late final Set<String> _boolColumns = {
    'isDeleted',
    for (final MapEntry(:key, :value) in _payloadColumns.entries)
      if (value.toUpperCase().contains('BOOL')) key,
  };

  @override
  Future<void> initialize() async {
    final defs = [
      for (final MapEntry(:key, :value) in _coreColumns.entries)
        '${_q(key)} $value',
      for (final MapEntry(:key, :value) in _payloadColumns.entries)
        '${_q(key)} $value',
      'PRIMARY KEY (${_q('id')}, ${_q('userId')})',
    ].join(', ');
    database
      ..execute('CREATE TABLE IF NOT EXISTS ${_q(table)} ($defs)')
      ..execute(
        'CREATE TABLE IF NOT EXISTS ${_q(_pendingOpsTable)} '
        '(id TEXT PRIMARY KEY, user_id TEXT NOT NULL, payload TEXT NOT NULL)',
      )
      ..execute(
        'CREATE TABLE IF NOT EXISTS ${_q(_syncStateTable)} '
        '(user_id TEXT PRIMARY KEY, metadata TEXT, last_result TEXT)',
      )
      ..execute(
        'CREATE TABLE IF NOT EXISTS ${_q(_metaTable)} (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    _migrateLegacyPrimaryKey();
  }

  /// Tables created before composite keying carry `id TEXT PRIMARY KEY`,
  /// which lets one user's `INSERT OR REPLACE` overwrite another user's row.
  /// SQLite cannot alter a primary key in place, so rebuild the table with
  /// `PRIMARY KEY (id, userId)`, preserving every existing column (including
  /// ones added by manual migrations that this adapter doesn't declare).
  void _migrateLegacyPrimaryKey() {
    final info = database.select('PRAGMA table_info(${_q(table)})');
    if (info.isEmpty) return;
    final composite = info.any(
      (row) => row['name'] == 'userId' && (row['pk'] as int) > 0,
    );
    if (composite) return;

    final names = [for (final row in info) row['name'] as String];
    final defs = [
      for (final row in info)
        '${_q(row['name'] as String)} ${row['type']}'
            '${(row['notnull'] as int) == 1 ? ' NOT NULL' : ''}'
            '${row['dflt_value'] != null ? ' DEFAULT ${row['dflt_value']}' : ''}',
      'PRIMARY KEY (${_q('id')}, ${_q('userId')})',
    ].join(', ');
    final columnList = names.map(_q).join(', ');
    final rebuilt = '${table}__pk_rebuild';

    database.execute('BEGIN IMMEDIATE');
    try {
      database
        ..execute('CREATE TABLE ${_q(rebuilt)} ($defs)')
        ..execute(
          'INSERT INTO ${_q(rebuilt)} ($columnList) SELECT $columnList FROM ${_q(table)}',
        )
        ..execute('DROP TABLE ${_q(table)}')
        ..execute('ALTER TABLE ${_q(rebuilt)} RENAME TO ${_q(table)}')
        ..execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  // --- Row codecs ----------------------------------------------------------

  Object? _encode(Object? value) => switch (value) {
    bool() => value ? 1 : 0,
    DateTime() => value.toIso8601String(),
    _ => value,
  };

  Map<String, dynamic> _decodeRow(Map<String, Object?> row) => {
    for (final MapEntry(:key, :value) in row.entries)
      key: _boolColumns.contains(key) ? (value == 1 || value == true) : value,
  };

  T _entityFromRow(Map<String, Object?> row) => fromMap(_decodeRow(row));

  void _notify(
    String entityId,
    String userId,
    DatumOperationType type,
    T? data,
  ) {
    if (_changeController.isClosed) return;
    _changeController.add(
      DatumChangeDetail<T>(
        entityId: entityId,
        userId: userId,
        type: type,
        data: data,
        timestamp: DateTime.now(),
      ),
    );
  }

  // --- Reads ---------------------------------------------------------------

  @override
  Future<List<T>> readAll({String? userId}) async {
    final rows = userId == null
        ? database.select('SELECT * FROM ${_q(table)}')
        : database.select(
            'SELECT * FROM ${_q(table)} WHERE ${_q('userId')} = ?',
            [userId],
          );
    return rows.map(_entityFromRow).toList();
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    final rows = userId == null
        ? database.select('SELECT * FROM ${_q(table)} WHERE ${_q('id')} = ?', [
            id,
          ])
        : database.select(
            'SELECT * FROM ${_q(table)} WHERE ${_q('id')} = ? AND ${_q('userId')} = ?',
            [id, userId],
          );
    return rows.isEmpty ? null : _entityFromRow(rows.first);
  }

  @override
  Future<Map<String, T>> readByIds(
    List<String> ids, {
    required String userId,
  }) async {
    if (ids.isEmpty) return {};
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = database.select(
      'SELECT * FROM ${_q(table)} WHERE ${_q('userId')} = ? AND ${_q('id')} IN ($placeholders)',
      [userId, ...ids],
    );
    return {for (final row in rows) row['id'] as String: _entityFromRow(row)};
  }

  @override
  Future<List<String>> getAllUserIds() async {
    return database
        .select('SELECT DISTINCT ${_q('userId')} FROM ${_q(table)}')
        .map((r) => r['userId'] as String)
        .toList();
  }

  @override
  Future<PaginatedResult<T>> readAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) async {
    final where = userId != null ? 'WHERE ${_q('userId')} = ?' : '';
    final args = userId != null ? [userId] : <Object?>[];
    final total =
        database
                .select('SELECT COUNT(*) AS c FROM ${_q(table)} $where', args)
                .first['c']
            as int;

    final page = (config.currentPage ?? 1).clamp(1, 1 << 31);
    final offset = (page - 1) * config.pageSize;
    final rows = database.select(
      'SELECT * FROM ${_q(table)} $where LIMIT ? OFFSET ?',
      [...args, config.pageSize, offset],
    );
    final totalPages = total == 0 ? 0 : (total / config.pageSize).ceil();
    return PaginatedResult(
      items: rows.map(_entityFromRow).toList(),
      totalCount: total,
      currentPage: page,
      totalPages: totalPages,
      hasMore: page < totalPages,
    );
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    // Push the query down to SQLite. User scoping joins the query's own
    // filters so LIMIT/OFFSET apply AFTER scoping, as callers expect.
    // The caller's filters are wrapped in a composite so the userId scope
    // ALWAYS ANDs with them — appending it flat would make it just another
    // alternative under LogicalOperator.or, leaking other users' rows.
    final scoped = userId == null
        ? query
        : DatumQuery(
            filters: [
              if (query.filters.isNotEmpty)
                CompositeFilter(query.filters, query.logicalOperator),
              Filter('userId', FilterOperator.equals, userId),
            ],
            sorting: query.sorting,
            limit: query.limit,
            offset: query.offset,
            logicalOperator: LogicalOperator.and,
          );
    final (:sql, :params) = scoped.toSql(table);
    // Filter values arrive as Dart objects (DateTime, bool) that sqlite3's
    // binder rejects or misreads — encode them like the write path does.
    return database
        .select(sql, params.map(_encode).toList())
        .map(_entityFromRow)
        .toList();
  }

  // --- Writes --------------------------------------------------------------

  /// Throws when [strictColumns] is on and [keys] contains undeclared ones.
  void _checkDeclared(Iterable<String> keys) {
    if (!strictColumns) return;
    final unknown = keys.where((k) => !_allColumns.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw ArgumentError(
        'Undeclared column(s) for "$table": ${unknown.join(', ')}. '
        'Declare them in columns:/schema:, or disable strictColumns.',
      );
    }
  }

  /// Upserts a row from its map form, covering the table's known columns.
  void _insertRow(Map<String, dynamic> map) {
    _checkDeclared(map.keys);
    final cols = _allColumns.where(map.containsKey).toList();
    final placeholders = List.filled(cols.length, '?').join(', ');
    database.execute(
      'INSERT OR REPLACE INTO ${_q(table)} '
      '(${cols.map(_q).join(', ')}) VALUES ($placeholders)',
      [for (final c in cols) _encode(map[c])],
    );
  }

  @override
  Future<void> create(T entity) async {
    _insertRow(entity.toDatumMap());
    _notify(entity.id, entity.userId, DatumOperationType.create, entity);
  }

  @override
  Future<void> update(T entity) async {
    _insertRow(entity.toDatumMap());
    _notify(entity.id, entity.userId, DatumOperationType.update, entity);
  }

  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    _checkDeclared(delta.keys);
    final cols = delta.keys.where(_allColumns.contains).toList();
    if (cols.isNotEmpty) {
      final assignments = cols.map((c) => '${_q(c)} = ?').join(', ');
      final where = userId != null
          ? '${_q('id')} = ? AND ${_q('userId')} = ?'
          : '${_q('id')} = ?';
      database.execute('UPDATE ${_q(table)} SET $assignments WHERE $where', [
        for (final c in cols) _encode(delta[c]),
        id,
        if (userId != null) userId,
      ]);
    }
    final patched = await read(id, userId: userId);
    if (patched == null) {
      throw EntityNotFoundException(
        message: 'Cannot patch $id: not found in $table',
      );
    }
    _notify(id, patched.userId, DatumOperationType.update, patched);
    return patched;
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    final existing = await read(id, userId: userId);
    if (existing == null) return false;
    // Scope the DELETE like the read above — rows are keyed by (id, userId),
    // so an unscoped delete-by-id would take other users' rows with it.
    if (userId != null) {
      database.execute(
        'DELETE FROM ${_q(table)} WHERE ${_q('id')} = ? AND ${_q('userId')} = ?',
        [id, userId],
      );
    } else {
      database.execute('DELETE FROM ${_q(table)} WHERE ${_q('id')} = ?', [id]);
    }
    _notify(id, existing.userId, DatumOperationType.delete, existing);
    return true;
  }

  @override
  Future<void> clearUserData(String userId) async {
    database
      ..execute('DELETE FROM ${_q(table)} WHERE ${_q('userId')} = ?', [userId])
      ..execute('DELETE FROM ${_q(_pendingOpsTable)} WHERE user_id = ?', [
        userId,
      ])
      ..execute('DELETE FROM ${_q(_syncStateTable)} WHERE user_id = ?', [
        userId,
      ]);
    _notify('*', userId, DatumOperationType.delete, null);
  }

  @override
  Future<void> clear() async {
    database
      ..execute('DELETE FROM ${_q(table)}')
      ..execute('DELETE FROM ${_q(_pendingOpsTable)}')
      ..execute('DELETE FROM ${_q(_syncStateTable)}');
    _notify('*', '', DatumOperationType.delete, null);
  }

  // --- Pending operations --------------------------------------------------

  @override
  Future<List<DatumSyncOperation<T>>> getPendingOperations(
    String userId,
  ) async {
    return database
        .select(
          'SELECT payload FROM ${_q(_pendingOpsTable)} WHERE user_id = ?',
          [userId],
        )
        .map(
          (r) => DatumSyncOperation<T>.fromMap(
            Map<String, dynamic>.from(
              jsonDecode(r['payload'] as String) as Map,
            ),
            fromMap,
          ),
        )
        .toList();
  }

  @override
  Future<void> addPendingOperation(
    String userId,
    DatumSyncOperation<T> operation,
  ) async {
    database.execute(
      'INSERT OR REPLACE INTO ${_q(_pendingOpsTable)} (id, user_id, payload) VALUES (?, ?, ?)',
      [operation.id, userId, jsonEncode(operation.toMap())],
    );
  }

  @override
  Future<void> removePendingOperation(String operationId) async {
    database.execute('DELETE FROM ${_q(_pendingOpsTable)} WHERE id = ?', [
      operationId,
    ]);
  }

  // --- Sync state ----------------------------------------------------------

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    final rows = database.select(
      'SELECT metadata FROM ${_q(_syncStateTable)} WHERE user_id = ?',
      [userId],
    );
    final raw = rows.isEmpty ? null : rows.first['metadata'] as String?;
    if (raw == null) return null;
    return DatumSyncMetadata.fromMap(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  @override
  Future<void> updateSyncMetadata(
    DatumSyncMetadata metadata,
    String userId,
  ) async {
    database.execute(
      'INSERT INTO ${_q(_syncStateTable)} (user_id, metadata) VALUES (?, ?) '
      'ON CONFLICT(user_id) DO UPDATE SET metadata = excluded.metadata',
      [userId, jsonEncode(metadata.toMap())],
    );
  }

  @override
  Future<void> saveLastSyncResult(
    String userId,
    DatumSyncResult<T> result,
  ) async {
    database.execute(
      'INSERT INTO ${_q(_syncStateTable)} (user_id, last_result) VALUES (?, ?) '
      'ON CONFLICT(user_id) DO UPDATE SET last_result = excluded.last_result',
      [userId, jsonEncode(result.toMap())],
    );
  }

  @override
  Future<DatumSyncResult<T>?> getLastSyncResult(String userId) async {
    final rows = database.select(
      'SELECT last_result FROM ${_q(_syncStateTable)} WHERE user_id = ?',
      [userId],
    );
    final raw = rows.isEmpty ? null : rows.first['last_result'] as String?;
    if (raw == null) return null;
    return DatumSyncResult<T>.fromMap(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  @override
  Future<int> getStoredSchemaVersion() async {
    final rows = database.select(
      "SELECT value FROM ${_q(_metaTable)} WHERE key = 'schema_version'",
    );
    return rows.isEmpty ? 0 : int.parse(rows.first['value'] as String);
  }

  @override
  Future<void> setStoredSchemaVersion(int version) async {
    database.execute(
      "INSERT OR REPLACE INTO ${_q(_metaTable)} (key, value) VALUES ('schema_version', ?)",
      ['$version'],
    );
  }

  @override
  Future<String?> getStoredSchemaFingerprint() async {
    final rows = database.select(
      "SELECT value FROM ${_q(_metaTable)} WHERE key = 'schema_fingerprint'",
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> setStoredSchemaFingerprint(String fingerprint) async {
    database.execute(
      "INSERT OR REPLACE INTO ${_q(_metaTable)} (key, value) VALUES ('schema_fingerprint', ?)",
      [fingerprint],
    );
  }

  // --- Raw data / migrations ----------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async {
    final rows = userId == null
        ? database.select('SELECT * FROM ${_q(table)}')
        : database.select(
            'SELECT * FROM ${_q(table)} WHERE ${_q('userId')} = ?',
            [userId],
          );
    return rows.map(_decodeRow).toList();
  }

  @override
  Future<void> overwriteAllRawData(
    List<Map<String, dynamic>> data, {
    String? userId,
  }) async {
    if (userId != null) {
      database.execute('DELETE FROM ${_q(table)} WHERE ${_q('userId')} = ?', [
        userId,
      ]);
    } else {
      database.execute('DELETE FROM ${_q(table)}');
    }
    data.forEach(_insertRow);
  }

  @override
  Future<List<DatumRawRow>> rawQuery(
    DatumRawQuery query, {
    String? userId,
  }) async {
    final sql = query.sql;
    if (sql == null) {
      throw ArgumentError(
        'SqliteLocalAdapter.rawQuery requires DatumRawQuery.sql',
      );
    }
    final head = sql.trimLeft().toUpperCase();
    if (head.startsWith('SELECT') || head.startsWith('PRAGMA')) {
      return database.select(sql, query.args).map(_decodeRow).toList();
    }
    database.execute(sql, query.args);
    return const [];
  }

  // --- Transactions --------------------------------------------------------

  @override
  Future<R> transaction<R>(Future<R> Function() action) async {
    database.execute('BEGIN IMMEDIATE');
    try {
      final result = await action();
      database.execute('COMMIT');
      return result;
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  // --- Reactive ------------------------------------------------------------

  @override
  Stream<DatumChangeDetail<T>>? changeStream() => _changeController.stream;

  Stream<S> _watch<S>(
    Future<S> Function() read, {
    String? userId,
    bool includeInitialData = true,
  }) {
    // Stream.multi runs this setup per LISTENER: each gets its own change
    // subscription and initial snapshot (a broadcast controller's onListen
    // fires only for the first listener, starving later concurrent ones).
    return Stream<S>.multi((controller) {
      // Subscribe to changes BEFORE the async initial read so no write in
      // that window is missed; every emission re-reads current state.
      final sub = _changeController.stream
          .where(
            (e) => userId == null || e.userId == userId || e.entityId == '*',
          )
          .listen((_) async {
            if (!controller.isClosed) controller.add(await read());
          });
      if (includeInitialData) {
        unawaited(
          read().then((initial) {
            if (!controller.isClosed) controller.add(initial);
          }),
        );
      }
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Stream<List<T>>? watchAll({String? userId, bool includeInitialData = true}) =>
      _watch(
        () => readAll(userId: userId),
        userId: userId,
        includeInitialData: includeInitialData,
      );

  @override
  Stream<T?>? watchById(String id, {String? userId}) =>
      _watch(() => read(id, userId: userId), userId: userId);

  @override
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) =>
      _watch(() => this.query(query, userId: userId), userId: userId);

  @override
  Stream<int>? watchCount({DatumQuery? query, String? userId}) => _watch(
    () async => query == null
        ? (await readAll(userId: userId)).length
        : (await this.query(query, userId: userId)).length,
    userId: userId,
  );

  @override
  Stream<T?>? watchFirst({DatumQuery? query, String? userId}) =>
      _watch(() async {
        final items = query == null
            ? await readAll(userId: userId)
            : await this.query(query, userId: userId);
        return items.isEmpty ? null : items.first;
      }, userId: userId);

  @override
  Stream<PaginatedResult<T>>? watchAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) => _watch(() => readAllPaginated(config, userId: userId), userId: userId);

  // --- Lifecycle -----------------------------------------------------------

  @override
  Future<int> getStorageSize({String? userId}) async {
    final rows = await getAllRawData(userId: userId);
    return utf8.encode(jsonEncode(rows)).length;
  }

  @override
  Future<void> dispose() async {
    if (!_changeController.isClosed) await _changeController.close();
    // The database is shared/caller-owned; the caller closes it.
  }
}
