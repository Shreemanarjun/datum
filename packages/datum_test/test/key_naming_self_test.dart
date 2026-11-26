import 'package:datum/datum.dart';
import 'package:datum_test/datum_test.dart';

void main() {
  runKeyNamingConformanceTests(
    name: 'InMemoryLocalAdapter',
    create: () async {
      final adapter = InMemoryLocalAdapter<SnakeKeyedEntity>(fromMap: SnakeKeyedEntity.fromMap);
      await adapter.initialize();
      return adapter;
    },
  );
}
