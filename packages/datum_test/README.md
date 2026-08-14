# datum_test

Adapter conformance test kit for the [Datum](https://pub.dev/packages/datum) offline-first sync ecosystem.

Building a custom `LocalAdapter` or `RemoteAdapter`? Certify it with one call — the kit runs the same behavioral contract Datum's own adapters pass: CRUD round-trips, user scoping, `DatumQuery` semantics, pending-operation queueing, sync metadata, schema-version persistence, migration raw-data fidelity, and capability checks (`WatchableAdapter`, `TransactionalAdapter`, `PaginatedAdapter`, `DeltaSyncCapable`).

## Certify a local adapter

```dart
import 'package:datum_test/datum_test.dart';

void main() {
  runLocalAdapterConformanceTests(
    name: 'MyAdapter',
    create: () async {
      final adapter = MyAdapter<ConformanceEntity>(fromMap: ConformanceEntity.fromMap);
      await adapter.initialize();
      return adapter;
    },
    // SQL adapters have fixed columns and can't keep unknown ones:
    // preservesUnknownColumns: false,
  );
}
```

## Certify a remote adapter

```dart
runRemoteAdapterConformanceTests(
  name: 'MyRestAdapter',
  create: () async => MyRestAdapter<ConformanceEntity>(...),
);
```

If your remote adapter mixes in `DeltaSyncCapable`, its `readSince` contract (inclusive watermark, only-changed rows) is verified automatically.

## Certify a whole sync stack

`runSyncStackConformanceTests` runs the full engine behavior matrix — push/pull round-trips, two-device convergence, offline queue replay, conflict resolution with winner push-back, soft-delete propagation, user isolation — over any local/remote adapter **pair**. Passing it certifies the pair as a compatible sync stack.

## Beyond correctness: chaos, crashes, fuzz, migrations, performance

- **`runChaosConformanceTests`** + stock `ChaosProfile`s (`flaky3G`, `unstableSocket`, `proxyCorruption`, `captivePortal`, `offlineWindows`) — certifies eventual convergence with zero loss or duplication once network faults clear.
- **`runCrashRecoveryConformanceTests`** — for persistent local adapters: queued operations survive a crash and deliver exactly once after reopen; mid-sync severed-socket crashes recover cleanly.
- **`runConvergenceFuzzTests`** — seeded random multi-device workloads with random sync interleavings; after quiescence every replica must agree. Failure messages carry the seed for exact reproduction. (This suite found two real engine bugs on its first outing.)
- **`runMigrationConformanceTests`** — the standard schema-migration chain over map-based or SQL executors: version stamping, fail-fast validation, rollback, resume, and relaunch run-once semantics.
- **`measureAdapterPerformance` / `runAdapterPerformanceTests`** — self-verifying ops/sec report per CRUD phase, with optional minimum thresholds (report-only by default, so CI can't flake).

## Integration harness

The kit also ships the harness Datum's own engine is tested with:

- **`LocalSyncServer`** — a real `dart:io` HTTP sync server with fault injection: latency, arbitrary failure status codes, offline windows, severed sockets, server-side version conflicts (409), and response corruption.
- **`HttpRemoteAdapter`** — a reference REST adapter with production-grade error mapping (retryable network errors, 404 → not-found, 409 → conflict, malformed JSON → serialization error) and incremental-pull support.

Use them to integration-test your app's sync flows against a real wire without a backend.
