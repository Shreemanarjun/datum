---
title: Testing Your Sync Stack
description: datum_test — certify adapters and whole stacks with one call, then go further with chaos, crash-recovery, and convergence fuzzing.
---

Sync bugs are the worst kind: they surface as *someone else's* stale data,
days later. The [`datum_test`](https://pub.dev/packages/datum_test) package
turns Datum's own test discipline into suites you run against **your**
adapters and backends — the same contracts every official adapter passes.

```bash
dart pub add dev:datum_test
```

Everything below runs inside plain `dart test` / `flutter test`.

## 1. Certify a local adapter (one call)

Wire your adapter for the kit's standard `ConformanceEntity` and hand in a
factory. You get the full behavioral contract — CRUD round-trips, user
scoping, `DatumQuery` semantics, pending-operation queueing, sync metadata,
schema-version persistence, migration raw-data fidelity, and capability
checks for watch streams, transactions, and pagination:

```dart no-verify
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

Remote adapters get the mirror suite — including the `readSince` inclusive
watermark contract when your adapter supports
[incremental sync](/guides/performance/incremental_sync):

```dart no-verify
runRemoteAdapterConformanceTests(
  name: 'MyRestAdapter',
  create: () async => MyRestAdapter<ConformanceEntity>(baseUrl: testServerUrl),
);
```

## 2. Certify a whole stack

Adapter conformance proves each half; **stack conformance** proves the pair
syncs correctly *together* — push/pull round-trips, two-device convergence,
offline queue replay, conflict resolution with winner push-back, soft-delete
propagation, stale-write protection, and user isolation:

```dart no-verify
runSyncStackConformanceTests(
  name: 'Hive + MyBackend',
  createLocal: () async => openHiveAdapter(),
  createRemote: () async => MyRestAdapter<ConformanceEntity>(baseUrl: testServerUrl),
  resetBackend: () async => wipeTestBackend(),
);
```

The contract: `createRemote` may be called several times per test and every
instance must hit the same backend state; `resetBackend` wipes it between
tests.

## 3. Integration-test your app without a backend

The kit ships the harness Datum's own engine is tested with: a real
`dart:io` HTTP server with fault injection, plus a reference REST adapter
with production-grade error mapping:

```dart
Future<void> integrationExample() async {
  final server = LocalSyncServer();
  await server.start();

  final local = InMemoryLocalAdapter<Task>(fromMap: Task.fromMap);
  final manager = DatumManager<Task>(
    localAdapter: local,
    remoteAdapter: HttpRemoteAdapter<Task>(baseUri: server.baseUri, fromMap: Task.fromMap),
    connectivity: const SnippetConnectivity(),
    datumConfig: const DatumConfig<Task>(enableLogging: false),
  );
  await manager.initialize();

  // Seed the "backend", sync, and assert — all over real sockets.
  server.seed('u1', {'id': 't1', 'userId': 'u1', 'title': 'from-server', 'version': 1, 'modifiedAt': DateTime.now().toIso8601String()});
  await manager.synchronize('u1');
  final pulled = await local.read('t1', userId: 'u1');
  print(pulled?.title); // from-server

  // Fault injection between requests:
  server.latency = Duration(milliseconds: 200); // slow network
  server.remainingFailures = 2;                 // next 2 requests fail 500
  server.offline = true;                        // everything 503s
  server.dropConnections = true;                // sever sockets mid-request
  server.corruptNextResponses = 1;              // 200 with garbage body

  await manager.dispose();
  await server.stop();
}
```

## 4. Chaos: certify recovery, not just the happy path

Five stock network-chaos profiles (`flaky3G`, `unstableSocket`,
`proxyCorruption`, `captivePortal`, `offlineWindows`) run sync cycles under
injected faults, then assert **eventual convergence with zero loss or
duplication** once conditions clear — and prove each profile actually fired:

```dart no-verify
runChaosConformanceTests(
  name: 'MyAdapter under chaos',
  createLocal: () async => openMyAdapter(),
);
```

## 5. Crash recovery: exactly-once after a kill

For persistent local adapters, the crash suite verifies that operations
queued before a crash survive a reopen and deliver exactly once — including
a crash *mid-sync* with a severed socket:

```dart no-verify
runCrashRecoveryConformanceTests(
  name: 'MyAdapter crash recovery',
  openLocal: () async => openMyAdapter(),   // same persisted storage each call
  wipeStorage: () async => deleteMyStorage(),
);
```

## 6. Convergence fuzzing: the bugs nobody writes tests for

Seeded random multi-device workloads — creates, updates, soft deletes,
random subsets of devices syncing in random orders — followed by a
quiescence phase after which **every replica must agree**. Failures print
the seed for exact reproduction:

```dart no-verify
runConvergenceFuzzTests(
  name: 'MyAdapter convergence',
  createLocal: () async => openMyAdapter(),
  rounds: 25,
  seed: 42,
);
```

This suite found two real engine bugs on its first run (an undetected
equal-version conflict class and a non-deterministic LWW tie-break). Run it
against your stack; it is the cheapest distributed-systems review you will
ever get.

## 7. Migration + performance conformance

The migration suite runs a standard chain against your adapter — stamping,
fail-fast validation, mid-chain rollback, resume, relaunch run-once — over
either executor path (map-based or SQL). The performance report times each
CRUD phase with integrity checks so a broken adapter can't produce
plausible-looking numbers:

```dart no-verify
runMigrationConformanceTests(
  name: 'MyAdapter migrations',
  createLocal: () async => openMyAdapter(),
  reopenLocal: () async => openMyAdapter(),
);

runAdapterPerformanceTests(
  name: 'MyAdapter perf',
  createLocal: () async => openMyAdapter(),
  entityCount: 500,
  // Report-only by default; opt into thresholds when you have baselines:
  // minOpsPerSec: {'create': 5000},
);
```

## What to run when

| You built… | Run |
|---|---|
| A local adapter | local conformance + migration conformance (+ crash if persistent) |
| A remote adapter | remote conformance |
| A full stack (app) | stack conformance + chaos + fuzz |
| A performance claim | the performance report with thresholds |

All seven suites together are a few hundred milliseconds to a few seconds —
cheap enough for every CI run.
