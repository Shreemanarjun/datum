/// The main entry point for the `datum` package.
///
/// This library exports all the public-facing APIs of the package,
/// making it easy for consumers to use its features.
library;

// Core functionality
export 'source/core/engine/datum_core.dart';
export 'source/core/manager/datum_manager.dart';
export 'source/core/engine/datum_observer.dart';
export 'source/core/engine/queue_manager.dart';
export 'source/core/health/datum_health.dart';
export 'source/core/metrics/datum_metrics.dart';

// Adapters (for users to implement)
export 'source/adapter/local_adapter.dart';
export 'source/adapter/remote_adapter.dart';

// Configuration & Middleware
export 'source/config/datum_config.dart';
export 'source/core/middleware/datum_middleware.dart';
export 'source/core/migration/migration.dart';

// Querying
export 'source/core/query/datum_query.dart';
export 'source/core/query/datum_query_builder.dart';
export 'source/core/query/datum_query_sql_converter.dart';

// Models (data structures for public API)
export 'source/core/models/conflict_context.dart';
export 'source/core/models/datum_exception.dart';
export 'source/core/models/datum_entity.dart';
export 'source/core/models/datum_pagination.dart';
export 'source/core/models/datum_sync_options.dart';
export 'source/core/models/datum_sync_result.dart';
export 'source/core/models/datum_sync_scope.dart';
export 'source/core/models/datum_sync_status_snapshot.dart';
export 'source/core/models/datum_sync_operation.dart';
export 'source/core/models/datum_change_detail.dart';
export 'source/core/models/datum_operation.dart';
export 'source/core/models/error_strategy.dart';
export 'source/core/models/user_switch_models.dart';
export 'source/core/models/datum_sync_metadata.dart';
export 'source/core/models/excludable_entity.dart';
export 'source/core/models/datum_registration.dart';
export 'source/core/models/relational_datum_entity.dart';

// Events
export 'source/core/events/datum_event.dart';
export 'source/core/events/data_change_event.dart';
export 'source/core/events/initial_sync_event.dart';
export 'source/core/events/conflict_detected_event.dart';
export 'source/core/events/conflict_resolved_event.dart';
export 'source/core/events/user_switched_event.dart';

// Sync Strategy
export 'source/core/sync/datum_sync_execution_strategy.dart';

// Conflict Resolution
export 'source/core/resolver/conflict_resolution.dart';
export 'source/core/resolver/last_write_wins_resolver.dart';
export 'source/core/resolver/local_priority_resolver.dart';
export 'source/core/resolver/remote_priority_resolver.dart';
export 'source/core/resolver/merge_resolver.dart';
export 'source/core/resolver/user_prompt_resolver.dart';

// Utilities
export 'source/utils/connectivity_checker.dart';
export 'source/utils/datum_logger.dart';
