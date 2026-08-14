import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'support/task.dart';

Task _task(String id, int priority, {String user = 'u1'}) => Task(
  id: id,
  userId: user,
  title: 'T$id',
  priority: priority,
  modifiedAt: DateTime(2024),
  createdAt: DateTime(2024),
  version: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late HiveLocalAdapter<Task> adapter;
  var counter = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('datum_hive_test');
    Hive.init(dir.path);
    adapter = HiveLocalAdapter<Task>(entityBoxName: 'tasks_${counter++}', fromMap: Task.fromMap);
    await adapter.initialize();
  });

  tearDown(() async {
    await adapter.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('query honors filters and sorting (no longer falls back to readAll)', () async {
    await adapter.create(_task('a', 5));
    await adapter.create(_task('b', 1));
    await adapter.create(_task('c', 3));

    final result = await adapter.query(
      (DatumQueryBuilder<Task>()
            ..where('priority', isGreaterThanOrEqualTo: 3)
            ..orderBy('priority', descending: true))
          .build(),
      userId: 'u1',
    );

    expect(result.map((t) => t.id).toList(), ['a', 'c']);
  });

  test('query limit/offset applied', () async {
    for (var i = 0; i < 5; i++) {
      await adapter.create(_task('e$i', i));
    }
    final result = await adapter.query(
      (DatumQueryBuilder<Task>()
            ..orderBy('priority')
            ..limit(2)
            ..offset(1))
          .build(),
      userId: 'u1',
    );
    expect(result.map((t) => t.priority).toList(), [1, 2]);
  });

  test('readAllPaginated returns pages', () async {
    for (var i = 0; i < 5; i++) {
      await adapter.create(_task('e$i', i));
    }
    final page = await adapter.readAllPaginated(const PaginationConfig(pageSize: 2, currentPage: 1), userId: 'u1');
    expect(page.items, hasLength(2));
    expect(page.totalCount, 5);
    expect(page.totalPages, 3);
    expect(page.hasMore, isTrue);
  });
}
