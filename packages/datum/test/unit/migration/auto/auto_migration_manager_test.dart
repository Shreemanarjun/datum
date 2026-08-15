import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../mocks/mock_adapters.dart';
import '../../../mocks/mock_connectivity_checker.dart';
import '../../schema/schema_test_entity.dart';

Map<String, dynamic> legacyRow(String id, {String name = 'n'}) => {
      'id': id,
      'userId': 'u1',
      'name': name,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'modifiedAt': '2026-01-01T00:00:00.000Z',
      'version': 1,
      'isDeleted': false,
    };

void main() {
  late MockLocalAdapter<SchemaTask> local;
  late MockRemoteAdapter<SchemaTask> remote;
  late MockConnectivityChecker connectivity;

  setUp(() {
    local = MockLocalAdapter<SchemaTask>(fromJson: SchemaTask.schema.decode);
    remote = MockRemoteAdapter<SchemaTask>(fromJson: SchemaTask.schema.decode);
    connectivity = MockConnectivityChecker();
    when(() => connectivity.isConnected).thenAnswer((_) async => true);
    when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
  });

  DatumManager<SchemaTask> manager(DatumConfig<SchemaTask> config) => DatumManager<SchemaTask>(
        localAdapter: local,
        remoteAdapter: remote,
        connectivity: connectivity,
        datumConfig: config,
      );

  DatumSchema<SchemaTask> autoSchema({String? renamedFrom = 'name'}) => DatumSchema<SchemaTask>(
        name: 'tasks',
        fields: [
          ...SchemaTask.core.all,
          DatumFieldSpec<SchemaTask, String>('title', renamedFrom: renamedFrom, defaultValue: ''),
          DatumFieldSpec<SchemaTask, int>('priority', defaultValue: 5),
        ],
      );

  test('initialize reconciles a legacy store when autoMigrate is on', () async {
    await local.overwriteAllRawData([legacyRow('a', name: 'alpha')]);
    final m = manager(DatumConfig<SchemaTask>(
      enableLogging: false,
      schema: autoSchema(),
      autoMigrate: true,
    ));
    await m.initialize();
    addTearDown(m.dispose);

    final rows = await local.getAllRawData();
    expect(rows.single['title'], 'alpha');
    expect(rows.single['priority'], 5);
    expect(rows.single.containsKey('name'), isFalse);

    final entity = SchemaTask.schema.decode(rows.single);
    expect(entity.title, 'alpha');
    expect(entity.priority, 5);
  });

  test('autoMigrate defaults to off — a schema alone changes nothing', () async {
    await local.overwriteAllRawData([legacyRow('a')]);
    final m = manager(DatumConfig<SchemaTask>(enableLogging: false, schema: autoSchema()));
    await m.initialize();
    addTearDown(m.dispose);
    expect((await local.getAllRawData()).single.containsKey('name'), isTrue);
  });

  test('the manual version chain runs before the auto pass', () async {
    await local.overwriteAllRawData([legacyRow('a', name: 'alpha')]);
    final m = manager(DatumConfig<SchemaTask>(
      enableLogging: false,
      schemaVersion: 1,
      migrations: [
        SchemaMigration(fromVersion: 0, toVersion: 1, operations: [
          ColumnOperation.rename('name', to: 'title'),
        ]),
      ],
      // No renamedFrom hint: if the auto pass ran first it would backfill
      // title with '' and the manual rename would be skipped.
      schema: autoSchema(renamedFrom: null),
      autoMigrate: true,
    ));
    await m.initialize();
    addTearDown(m.dispose);

    final row = (await local.getAllRawData()).single;
    expect(row['title'], 'alpha', reason: 'manual rename preserved the value; auto added nothing');
    expect(row['priority'], 5, reason: 'the auto pass still reconciled the remainder');
    expect(await local.getStoredSchemaVersion(), 1, reason: 'the int version stays chain-owned');
  });

  test('a failing auto pass throws MigrationException from initialize by default', () async {
    await local.overwriteAllRawData([legacyRow('a')]);
    final schema = DatumSchema<SchemaTask>(fields: [
      ...SchemaTask.core.all,
      DatumFieldSpec<SchemaTask, String>('title'), // non-nullable, no default
    ], name: 'tasks');
    final m = manager(DatumConfig<SchemaTask>(enableLogging: false, schema: schema, autoMigrate: true));
    await expectLater(m.initialize(), throwsA(isA<MigrationException>()));
    await m.dispose();
  });

  test('onMigrationError intercepts auto-pass failures', () async {
    await local.overwriteAllRawData([legacyRow('a')]);
    Object? seen;
    final schema = DatumSchema<SchemaTask>(fields: [
      ...SchemaTask.core.all,
      DatumFieldSpec<SchemaTask, String>('title'),
    ], name: 'tasks');
    final m = manager(DatumConfig<SchemaTask>(
      enableLogging: false,
      schema: schema,
      autoMigrate: true,
      onMigrationError: (error, stack) async => seen = error,
    ));
    await m.initialize();
    addTearDown(m.dispose);
    expect(seen, isA<MigrationException>());
    expect((await local.getAllRawData()).single.containsKey('name'), isTrue, reason: 'store untouched');
  });

  test('DatumConfig carries the new fields through copyWith and equality', () {
    final schema = autoSchema();
    final config = DatumConfig<SchemaTask>(schema: schema, autoMigrate: true, autoMigrateDropColumns: true);
    expect(config.props, contains(schema));

    final copied = config.copyWith<SchemaTask>();
    expect(copied.schema, same(schema));
    expect(copied.autoMigrate, isTrue);
    expect(copied.autoMigrateDropColumns, isTrue);

    final retyped = config.sanitizedForIsolate<SchemaTask>();
    expect(retyped.schema, same(schema));
    expect(retyped.autoMigrate, isTrue);

    expect(config, isNot(DatumConfig<SchemaTask>(schema: schema, autoMigrate: false)));
  });
}
