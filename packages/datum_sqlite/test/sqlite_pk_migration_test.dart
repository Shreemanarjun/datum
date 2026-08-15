import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Tables created before composite keying used `id TEXT PRIMARY KEY`, which
/// let one user's `INSERT OR REPLACE` overwrite another user's same-id row.
/// `initialize()` must rebuild such tables with `PRIMARY KEY (id, userId)`,
/// preserving every row and every column — including columns added by manual
/// migrations that the adapter doesn't declare.
void main() {
  late Database db;

  setUp(() => db = sqlite3.openInMemory());
  tearDown(() => db.dispose());

  void seedLegacyTable() {
    db
      ..execute(
        'CREATE TABLE "tasks" ("id" TEXT PRIMARY KEY, "userId" TEXT NOT NULL, '
        '"modifiedAt" TEXT, "createdAt" TEXT, "version" INTEGER, "isDeleted" BOOLEAN, '
        '"name" TEXT, "value" INTEGER, "legacy_extra" TEXT)',
      )
      ..execute(
        'INSERT INTO "tasks" ("id", "userId", "modifiedAt", "createdAt", "version", "isDeleted", "name", "value", "legacy_extra") '
        "VALUES ('settings', 'u1', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 3, 0, 'keep-me', 41, 'undeclared-survives')",
      );
  }

  SqliteLocalAdapter<ConformanceEntity> adapter() =>
      SqliteLocalAdapter<ConformanceEntity>(
        database: db,
        table: 'tasks',
        fromMap: ConformanceEntity.fromMap,
        columns: const {'name': 'TEXT', 'value': 'INTEGER'},
      );

  test(
    'legacy single-column PK is rebuilt as (id, userId) with rows intact',
    () async {
      seedLegacyTable();
      await adapter().initialize();

      final info = db.select('PRAGMA table_info("tasks")');
      final pkColumns = [
        for (final row in info)
          if ((row['pk'] as int) > 0) row['name'],
      ];
      expect(pkColumns.toSet(), {'id', 'userId'});

      final migrated = db.select('SELECT * FROM "tasks"').single;
      expect(migrated['name'], 'keep-me');
      expect(migrated['value'], 41);
      expect(migrated['version'], 3);
      expect(
        migrated['legacy_extra'],
        'undeclared-survives',
        reason: 'columns the adapter does not declare must survive the rebuild',
      );
    },
  );

  test('after migration, two users own the same id independently', () async {
    seedLegacyTable();
    final local = adapter();
    await local.initialize();

    await local.create(
      ConformanceEntity.make(
        'settings',
        userId: 'u2',
        name: 'second-owner',
        value: 2,
      ),
    );

    expect((await local.read('settings', userId: 'u1'))?.name, 'keep-me');
    expect((await local.read('settings', userId: 'u2'))?.name, 'second-owner');
    expect((await local.readAll()).length, 2);
  });

  test(
    'migration is idempotent: a second initialize leaves the table alone',
    () async {
      seedLegacyTable();
      await adapter().initialize();
      final before = db.select('SELECT * FROM "tasks"');

      await adapter().initialize();
      final after = db.select('SELECT * FROM "tasks"');

      expect(after.length, before.length);
      final info = db.select('PRAGMA table_info("tasks")');
      expect(
        {
          for (final row in info)
            if ((row['pk'] as int) > 0) row['name'],
        },
        {'id', 'userId'},
      );
    },
  );

  test('fresh tables are created with the composite key directly', () async {
    final local = adapter();
    await local.initialize();

    await local.create(
      ConformanceEntity.make('settings', userId: 'u1', value: 1),
    );
    await local.create(
      ConformanceEntity.make('settings', userId: 'u2', value: 2),
    );
    await local.update(
      ConformanceEntity.make('settings', userId: 'u2', value: 22),
    );

    expect((await local.read('settings', userId: 'u1'))?.value, 1);
    expect((await local.read('settings', userId: 'u2'))?.value, 22);
  });
}
