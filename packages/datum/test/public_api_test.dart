@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Golden set of the public barrel exports (`lib/datum.dart`).
///
/// This guardrail makes any change to the public API surface a **deliberate,
/// reviewed diff**. If this test fails you either:
///   1. Added/removed a `lib/` file (regenerate the barrel and update this set), or
///   2. Accidentally changed the public surface — revert it.
///
/// Update this set only when the export change is intentional.
const _expectedExports = <String>{
  'package:datum/source/core/errors/datum_exception.dart',
  'source/adapter/adapter_capabilities.dart',
  'source/adapter/in_memory_local_adapter.dart',
  'source/adapter/local_adapter.dart',
  'source/adapter/remote_adapter.dart',
  'source/config/datum_config.dart',
  'source/core/cascade_delete.dart',
  'source/core/engine/_internal.dart',
  'source/core/engine/conflict_detector.dart',
  'source/core/engine/datum_core.dart',
  'source/core/engine/datum_observer.dart',
  'source/core/engine/datum_sync_engine.dart',
  'source/core/engine/isolate_helper.dart',
  'source/core/engine/queue_manager.dart',
  'source/core/errors/datum_error.dart',
  'source/core/events/conflict_detected_event.dart',
  'source/core/events/conflict_resolved_event.dart',
  'source/core/events/data_change_event.dart',
  'source/core/events/datum_event.dart',
  'source/core/events/datum_sync_statistics.dart',
  'source/core/events/initial_sync_event.dart',
  'source/core/events/user_switched_event.dart',
  'source/core/health/datum_health.dart',
  'source/core/manager/datum_manager.dart',
  'source/core/manager/datum_sync_request_strategy.dart',
  'source/core/manager/disposable.dart',
  'source/core/middleware/datum_middleware.dart',
  'source/core/migration/migration_executor.dart',
  'source/core/migration/migration.dart',
  'source/core/migration/migration_plan.dart',
  'source/core/migration/schema_migration.dart',
  'source/core/models/cold_start_strategy.dart',
  'source/core/models/conflict_context.dart',
  'source/core/models/crdt.dart',
  'source/core/models/data_fetch_strategy.dart',
  'source/core/models/data_source.dart',
  'source/core/models/datum_change_detail.dart',
  'source/core/models/datum_either.dart',
  'source/core/models/datum_entity.dart',
  'source/core/models/datum_index_config.dart',
  'source/core/models/datum_metrics.dart',
  'source/core/models/datum_operation.dart',
  'source/core/models/datum_pagination.dart',
  'source/core/models/datum_registration.dart',
  'source/core/models/datum_sync_conflict_summary.dart',
  'source/core/models/datum_sync_metadata.dart',
  'source/core/models/datum_sync_operation.dart',
  'source/core/models/datum_sync_options.dart',
  'source/core/models/datum_sync_result.dart',
  'source/core/models/datum_sync_scope.dart',
  'source/core/models/datum_sync_status_snapshot.dart',
  'source/core/models/error_strategy.dart',
  'source/core/models/excludable_entity.dart',
  'source/core/models/relational_datum_entity.dart',
  'source/core/models/relation_schema.dart',
  'source/core/models/user_switch_models.dart',
  'source/core/models/vector_clock.dart',
  'source/core/query/datum_query_builder.dart',
  'source/core/query/datum_query_matcher.dart',
  'source/core/query/datum_raw_query.dart',
  'source/core/query/datum_query_sql_converter.dart',
  'source/core/query/datum_query.dart',
  'source/core/resolver/conflict_resolution.dart',
  'source/core/resolver/crdt_resolver.dart',
  'source/core/resolver/last_write_wins_resolver.dart',
  'source/core/resolver/local_priority_resolver.dart',
  'source/core/resolver/merge_resolver.dart',
  'source/core/resolver/remote_priority_resolver.dart',
  'source/core/resolver/user_prompt_resolver.dart',
  'source/core/sync/datum_sync_execution_strategy.dart',
  'source/utils/connectivity_checker.dart',
  'source/utils/datum_logger.dart',
  'source/utils/duration_formatter.dart',
  'source/utils/hash_generator.dart',
};

Set<String> _actualExports() {
  // Locate lib/datum.dart relative to the package root (cwd during tests).
  final barrel = File('lib/datum.dart');
  if (!barrel.existsSync()) {
    fail('Could not find lib/datum.dart from cwd ${Directory.current.path}');
  }
  final exportRe = RegExp(r"""export\s+'([^']+)'""");
  return barrel.readAsLinesSync().map((l) => exportRe.firstMatch(l)).whereType<RegExpMatch>().map((m) => m.group(1)!).toSet();
}

void main() {
  test('public barrel export surface matches the golden set', () {
    final actual = _actualExports();

    final added = actual.difference(_expectedExports);
    final removed = _expectedExports.difference(actual);

    expect(
      added,
      isEmpty,
      reason: 'New public exports detected. If intentional, add them to '
          '_expectedExports in this test:\n  ${added.join('\n  ')}',
    );
    expect(
      removed,
      isEmpty,
      reason: 'Public exports were removed (potential breaking change). If '
          'intentional, remove them from _expectedExports:\n  ${removed.join('\n  ')}',
    );
  });
}
