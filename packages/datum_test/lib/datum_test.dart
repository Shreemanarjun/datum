/// Adapter conformance test kit for the Datum ecosystem.
///
/// Certify any adapter implementation with one call from a test file:
///
/// ```dart
/// import 'package:datum_test/datum_test.dart';
///
/// void main() {
///   runLocalAdapterConformanceTests(
///     name: 'MyAdapter',
///     create: () async {
///       final adapter = MyAdapter<ConformanceEntity>(fromMap: ConformanceEntity.fromMap);
///       await adapter.initialize();
///       return adapter;
///     },
///   );
/// }
/// ```
///
/// Also ships the integration harness used to test the sync engine itself:
/// [LocalSyncServer], a real `dart:io` HTTP server with fault injection
/// (latency, error codes, offline windows, severed sockets, version
/// conflicts, response corruption), and [HttpRemoteAdapter], a reference
/// REST adapter with production-grade error mapping and incremental-pull
/// support.
library;

export 'src/auto_migration_conformance.dart';
export 'src/chaos_profiles.dart';
export 'src/conformance_entity.dart';
export 'src/convergence_fuzz.dart';
export 'src/crash_recovery_conformance.dart';
export 'src/http_remote_adapter.dart';
export 'src/local_adapter_conformance.dart';
export 'src/local_sync_server.dart';
export 'src/migration_conformance.dart';
export 'src/performance_report.dart';
export 'src/remote_adapter_conformance.dart';
export 'src/sync_stack_conformance.dart';
export 'src/typed_query_conformance.dart';
export 'src/watch_conformance.dart';
