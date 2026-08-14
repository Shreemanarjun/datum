/// End-to-end schema migrations against a REAL SQLite database.
///
/// Everything here executes on an actual in-memory sqlite3 instance — DDL,
/// backfills, scoped updates, and transactional rollback are the database's
/// own behavior, not a fake's. The scenario doubles as the reference example
/// for wiring [SqlMigrationExecutor] to a SQL adapter:
///
///  * v0 -> v1  add a column with a default + rename a column
///  * v1 -> v2  add a column backfilled from a SQL expression
///  * v2 -> v3  scoped in-place transform (`sqlWhere`) + drop a legacy column
///  * v3 -> v4  raw-SQL row rewrite + a custom [SqlConvertibleOperation]
library;

import 'package:datum/datum.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

/// A [LocalAdapter] whose SQL surface is backed by a real sqlite3 database.
///
/// Only the members the SQL migration path touches are real ([rawQuery],
/// schema-version storage, [transaction]); the entity-CRUD surface is
/// inherited from [InMemoryLocalAdapter] and unused here. A production
/// adapter (e.g. Drift-based) would implement both against the same database.
class _SqliteAdapter extends InMemoryLocalAdapter<TestEntity> with RawQueryCapable {
  _SqliteAdapter(this.db) : super(fromMap: TestEntity.fromJson) {
    db.execute('CREATE TABLE IF NOT EXISTS _datum_meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL)');
  }

  final Database db;

  @override
  Future<List<DatumRawRow>> rawQuery(DatumRawQuery query, {String? userId}) async {
    final sql = query.sql!;
    final head = sql.trimLeft().toUpperCase();
    if (head.startsWith('SELECT') || head.startsWith('PRAGMA')) {
      return db.select(sql).map((row) => Map<String, dynamic>.from(row)).toList();
    }
    db.execute(sql);
    return const [];
  }

  @override
  Future<int> getStoredSchemaVersion() async {
    final rows = db.select("SELECT value FROM _datum_meta WHERE key = 'schema_version'");
    return rows.isEmpty ? 0 : rows.single['value'] as int;
  }

  @override
  Future<void> setStoredSchemaVersion(int version) async {
    db.execute('INSERT OR REPLACE INTO _datum_meta (key, value) VALUES (?, ?)', ['schema_version', version]);
  }

  @override
  Future<R> transaction<R>(Future<R> Function() action) async {
    db.execute('BEGIN');
    try {
      final result = await action();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}

/// A custom operation demonstrating [SqlConvertibleOperation]: the map path
/// treats it as a no-op, the SQL path creates a real index.
class _CreateEmailDomainIndex extends ColumnOperation implements SqlConvertibleOperation {
  @override
  Map<String, dynamic> apply(Map<String, dynamic> row) => row;

  @override
  List<String> toSqlStatements(String table, SqlDialect dialect) => ['CREATE INDEX idx_users_email_domain ON $table (email_domain)'];
}

void main() {
  late Database db;
  late _SqliteAdapter adapter;
  final logger = DatumLogger(enabled: false);

  /// The full production-style chain, exercising every operation kind.
  final chain = [
    SchemaMigration(
      fromVersion: 0,
      toVersion: 1,
      operations: [
        ColumnOperation.add('status', defaultValue: 'active'),
        ColumnOperation.rename('name', to: 'full_name'),
      ],
    ),
    SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      operations: [
        // Dart compute for schemaless stores; SQL backfill for SQL stores.
        ColumnOperation.add(
          'email_domain',
          sqlType: 'TEXT',
          compute: (row) => (row['email'] as String? ?? '').split('@').last.toLowerCase(),
          sqlExpression: "lower(substr(email, instr(email, '@') + 1))",
        ),
      ],
    ),
    SchemaMigration(
      fromVersion: 2,
      toVersion: 3,
      sqlWhere: 'age >= 18',
      where: (row) => (row['age'] as int? ?? 0) >= 18,
      operations: [
        ColumnOperation.transform('age', (v, _) => (v as int? ?? 0) + 1, sqlExpression: 'age + 1'),
      ],
    ),
    SchemaMigration(
      fromVersion: 3,
      toVersion: 4,
      operations: [
        ColumnOperation.remove('legacy_score'),
        ColumnOperation.row(
          (row) => {...row, 'email': (row['email'] as String? ?? '').toLowerCase()},
          sql: ['UPDATE "users" SET "email" = lower(email)'],
        ),
        _CreateEmailDomainIndex(),
      ],
    ),
  ];

  SqlMigrationExecutor<TestEntity> executor({int target = 4}) => SqlMigrationExecutor<TestEntity>(
        localAdapter: adapter,
        table: 'users',
        migrations: chain,
        targetVersion: target,
        logger: logger,
      );

  List<String> columnsOf(String table) => db.select('PRAGMA table_info($table)').map((r) => r['name'] as String).toList();

  Map<String, dynamic> rowById(String id) => Map<String, dynamic>.from(db.select('SELECT * FROM users WHERE id = ?', [id]).single);

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        age INTEGER NOT NULL,
        legacy_score REAL,
        version INTEGER NOT NULL
      )
    ''');
    final insert = db.prepare('INSERT INTO users (id, userId, name, email, age, legacy_score, version) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)');
    insert
      ..execute(['u1', 'acct', 'Ada Lovelace', 'ada@Example.COM', 36, 99.5, 1])
      ..execute(['u2', 'acct', 'Grace Hopper', 'grace@navy.mil', 79, null, 1])
      ..execute(['u3', 'acct', 'Alan Turing', 'alan@bletchley.uk', 17, 12.0, 1])
      ..dispose();
    adapter = _SqliteAdapter(db);
  });

  tearDown(() => db.dispose());

  test('complex 4-step chain migrates a real sqlite schema and its data', () async {
    expect(await executor().needsMigration(), isTrue);

    final result = await executor().execute();
    expect(result.success, isTrue, reason: '${result.migrationError}');

    // Real schema after the chain: renamed + added columns present, dropped gone.
    expect(
      columnsOf('users'),
      containsAll(['id', 'userId', 'full_name', 'email', 'age', 'version', 'status', 'email_domain']),
    );
    expect(columnsOf('users'), isNot(contains('name')));
    expect(columnsOf('users'), isNot(contains('legacy_score')));

    // Data: rename preserved values, default applied to every existing row.
    final ada = rowById('u1');
    expect(ada['full_name'], 'Ada Lovelace');
    expect(ada['status'], 'active');

    // Backfill computed the domain — lowercased from the mixed-case source.
    expect(ada['email_domain'], 'example.com');
    expect(rowById('u2')['email_domain'], 'navy.mil');

    // Scoped transform: only rows with age >= 18 were incremented.
    expect(ada['age'], 37);
    expect(rowById('u2')['age'], 80);
    expect(rowById('u3')['age'], 17, reason: 'u3 was under the sqlWhere threshold');

    // Raw-SQL row rewrite ran.
    expect(ada['email'], 'ada@example.com');

    // The custom SqlConvertibleOperation created a real index.
    final indexes = db.select("SELECT name FROM sqlite_master WHERE type = 'index'").map((r) => r['name']);
    expect(indexes, contains('idx_users_email_domain'));

    expect(await adapter.getStoredSchemaVersion(), 4);
    expect(await executor().needsMigration(), isFalse);
  });

  test('re-running the executor after completion is a strict no-op', () async {
    await executor().execute();
    final agesBefore = db.select('SELECT id, age FROM users ORDER BY id');

    final second = await executor().execute();

    expect(second.success, isTrue);
    expect(db.select('SELECT id, age FROM users ORDER BY id'), agesBefore, reason: 'a second launch must not re-apply transforms');
  });

  test('resuming mid-chain only applies the remaining steps', () async {
    // Simulate an install that already shipped v0 -> v2.
    await executor(target: 2).execute();
    expect(columnsOf('users'), contains('email_domain'));
    expect(rowById('u1')['age'], 36, reason: 'v2 -> v3 not applied yet');

    final result = await executor().execute();

    expect(result.success, isTrue);
    expect(rowById('u1')['age'], 37, reason: 'only the age transform from v2 -> v3 ran once');
    expect(await adapter.getStoredSchemaVersion(), 4);
  });

  test('a failing statement mid-chain rolls back DDL and data atomically', () async {
    final badChain = [
      chain.first, // valid: adds status, renames name
      SchemaMigration(
        fromVersion: 1,
        toVersion: 2,
        operations: [
          ColumnOperation.row((r) => r, sql: ['UPDATE "users" SET "does_not_exist" = 1']),
        ],
      ),
    ];
    final failing = SqlMigrationExecutor<TestEntity>(
      localAdapter: adapter,
      table: 'users',
      migrations: badChain,
      targetVersion: 2,
      logger: logger,
    );

    final result = await failing.execute();

    expect(result.success, isFalse);
    expect(result.migrationError, isA<SqliteException>());
    // Real transactional DDL: step 1's ALTERs are rolled back too.
    expect(columnsOf('users'), contains('name'));
    expect(columnsOf('users'), isNot(contains('status')));
    expect(await adapter.getStoredSchemaVersion(), 0);
  });

  test('the same chain drives a schemaless store via the map-based executor', () async {
    // The exact migration list also runs through MigrationExecutor: Dart
    // closures take over where SQL expressions did (compute / where / row).
    final memory = InMemoryLocalAdapter<TestEntity>(fromMap: TestEntity.fromJson);
    await memory.initialize();
    await memory.overwriteAllRawData([
      {'id': 'm1', 'userId': 'acct', 'name': 'Ada', 'email': 'ada@Example.COM', 'age': 36, 'version': 1},
    ]);

    final result = await MigrationExecutor<TestEntity>(
      localAdapter: memory,
      migrations: chain,
      targetVersion: 4,
      logger: logger,
    ).execute();

    expect(result.success, isTrue);
    expect(await memory.getStoredSchemaVersion(), 4);
  });
}
