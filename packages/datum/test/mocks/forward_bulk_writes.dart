import 'package:datum/datum.dart';

/// Routes bulk writes through the per-item methods, like [LocalAdapter]'s
/// defaults, so a mocktail mock's `create`/`update` stubs and verifies keep
/// working when the engine applies a pull batch via `createAll`/`updateAll`.
mixin ForwardBulkWrites<T extends DatumEntityInterface> implements LocalAdapter<T> {
  @override
  Future<void> createAll(List<T> entities) async {
    for (final entity in entities) {
      await create(entity);
    }
  }

  @override
  Future<void> updateAll(List<T> entities) async {
    for (final entity in entities) {
      await update(entity);
    }
  }
}
