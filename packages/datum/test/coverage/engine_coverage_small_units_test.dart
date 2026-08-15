import 'dart:async';

import 'package:datum/datum.dart';
import 'package:datum/source/core/engine/error_boundary.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

/// Extends the abstract base WITHOUT overriding [DatumSyncRequestStrategy.dispose],
/// so calling dispose() executes the base class implementation body.
class _BaseDisposeStrategy extends DatumSyncRequestStrategy {
  @override
  Future<T> execute<T>(
    Future<T> Function() action, {
    required bool Function() isSyncInProgress,
    required T Function() onSkipped,
  }) =>
      action();
}

TestEntity _entity(String id, {int version = 1, String name = 'n'}) => TestEntity(
      id: id,
      userId: 'u1',
      name: name,
      value: 0,
      modifiedAt: DateTime(2024),
      createdAt: DateTime(2024),
      version: version,
    );

DatumConflictContext _context() => DatumConflictContext(
      userId: 'u1',
      entityId: 'e1',
      type: DatumConflictType.bothModified,
      detectedAt: DateTime(2024),
    );

void main() {
  group('ErrorBoundary.executeVoid', () {
    test('retry strategy retries once and contains the failure when the retry also fails', () async {
      var attempts = 0;
      final boundary = ErrorBoundary<void>(
        config: const ErrorBoundaryConfig(
          strategy: ErrorBoundaryStrategy.retry,
          maxRetries: 3,
          retryDelay: Duration(milliseconds: 1),
        ),
        logger: DatumLogger(enabled: false),
      );

      // Must complete normally even though both the original attempt and the
      // retry throw: the boundary contains the error.
      await boundary.executeVoid(() async {
        attempts++;
        throw StateError('always fails');
      });

      expect(attempts, 2, reason: 'initial attempt + exactly one retry');
    });

    test('retry strategy with maxRetries=0 gives up without retrying', () async {
      var attempts = 0;
      final boundary = ErrorBoundary<void>(
        config: const ErrorBoundaryConfig(
          strategy: ErrorBoundaryStrategy.retry,
          maxRetries: 0,
          retryDelay: Duration(milliseconds: 1),
        ),
        logger: DatumLogger(enabled: false),
      );

      await boundary.executeVoid(() async {
        attempts++;
        throw StateError('always fails');
      });

      expect(attempts, 1, reason: 'max retries exceeded before any retry');
    });

    test('fallback strategy swallows the error without retrying', () async {
      var attempts = 0;
      final boundary = ErrorBoundary<void>(
        config: const ErrorBoundaryConfig(strategy: ErrorBoundaryStrategy.fallback),
        logger: DatumLogger(enabled: false),
      );

      await boundary.executeVoid(() async {
        attempts++;
        throw StateError('boom');
      });

      expect(attempts, 1);
    });
  });

  group('CRDTResolver', () {
    // Constructed WITHOUT const on purpose: const instances are canonicalized
    // at compile time, so only a runtime invocation executes the constructor.
    // ignore: prefer_const_constructors
    final resolver = CRDTResolver<TestEntity>();

    test('exposes its strategy name', () {
      expect(resolver.name, 'CRDTMerge');
    });

    test('aborts when neither local nor remote is supplied', () async {
      final resolution = await resolver.resolve(context: _context());
      expect(resolution.strategy, DatumResolutionStrategy.abort);
      expect(resolution.resolvedData, isNull);
      expect(resolution.message, contains('No entities supplied'));
    });

    test('preserves the surviving side of a deletion conflict', () async {
      // Aborting here (the old behavior) left the same deletion conflict
      // re-firing on every sync cycle forever; the CRDT-flavored choice is
      // that content survives.
      final onlyLocal = await resolver.resolve(local: _entity('e1'), context: _context());
      expect(onlyLocal.strategy, DatumResolutionStrategy.takeLocal);

      final onlyRemote = await resolver.resolve(remote: _entity('e1'), context: _context());
      expect(onlyRemote.strategy, DatumResolutionStrategy.takeRemote);
    });
  });

  group('CascadeAnalytics.copyWith', () {
    final base = CascadeAnalytics(
      totalDuration: const Duration(seconds: 1),
      queriesExecuted: 1,
      relationshipsTraversed: 2,
      entitiesProcessedByType: const {TestEntity: 3},
      entitiesDeletedByType: const {TestEntity: 2},
      restrictViolations: 0,
      setNullOperations: 4,
      errorsEncountered: 0,
      wasDryRun: false,
      startedAt: DateTime(2024),
      completedAt: DateTime(2024, 1, 1, 0, 0, 1),
    );

    test('overrides queriesExecuted and restrictViolations, preserving the rest', () {
      final updated = base.copyWith(queriesExecuted: 9, restrictViolations: 5);
      expect(updated.queriesExecuted, 9);
      expect(updated.restrictViolations, 5);
      expect(updated.totalDuration, base.totalDuration);
      expect(updated.relationshipsTraversed, base.relationshipsTraversed);
      expect(updated.entitiesProcessedByType, base.entitiesProcessedByType);
      expect(updated.entitiesDeletedByType, base.entitiesDeletedByType);
      expect(updated.setNullOperations, base.setNullOperations);
      expect(updated.errorsEncountered, base.errorsEncountered);
      expect(updated.wasDryRun, base.wasDryRun);
      expect(updated.startedAt, base.startedAt);
      expect(updated.completedAt, base.completedAt);
    });

    test('with no arguments returns an equivalent copy', () {
      final copy = base.copyWith();
      expect(copy.queriesExecuted, base.queriesExecuted);
      expect(copy.restrictViolations, base.restrictViolations);
      expect(copy.totalDuration, base.totalDuration);
      expect(copy.wasDryRun, base.wasDryRun);
    });
  });

  group('Sync execution strategies (runtime construction)', () {
    test('ParallelStrategy runtime instance processes every operation and reports progress', () async {
      // Runtime (non-const) construction so the constructor line executes.
      // ignore: prefer_const_constructors
      final strategy = ParallelStrategy(batchSize: 2, failFast: false);
      expect(strategy.batchSize, 2);
      expect(strategy.failFast, isFalse);

      final ops = List.generate(
        3,
        (i) => DatumSyncOperation<TestEntity>(
          id: 'op$i',
          userId: 'u1',
          entityId: 'e$i',
          type: DatumOperationType.create,
          timestamp: DateTime(2024),
          data: _entity('e$i'),
        ),
      );
      final processed = <String>[];
      var lastProgress = 0;
      await strategy.execute<TestEntity>(
        ops,
        (op) async => processed.add(op.id),
        () => false,
        (done, total) => lastProgress = done,
      );
      expect(processed.toSet(), {'op0', 'op1', 'op2'});
      expect(lastProgress, 3);
    });

    test('IsolateStrategy runtime instance wraps its delegate and short-circuits on empty input', () async {
      // ignore: prefer_const_constructors
      final strategy = IsolateStrategy(SequentialStrategy(), forceIsolateInTest: false);
      expect(strategy.delegate, isA<SequentialStrategy>());
      expect(strategy.forceIsolateInTest, isFalse);

      // An empty operation list must return before any isolate is spawned.
      var called = false;
      await strategy.execute<TestEntity>(
        [],
        (op) async => called = true,
        () => false,
        (done, total) {},
      );
      expect(called, isFalse);
    });
  });

  group('DatumSyncRequestStrategy', () {
    test('base dispose() is a usable no-op for subclasses that do not override it', () async {
      final strategy = _BaseDisposeStrategy();
      final result = await strategy.execute<int>(
        () async => 41,
        isSyncInProgress: () => false,
        onSkipped: () => -1,
      );
      expect(result, 41);
      expect(strategy.dispose, returnsNormally);
    });

    test('SkipConcurrentStrategy runtime instance skips while a sync is in progress', () async {
      // ignore: prefer_const_constructors
      final strategy = SkipConcurrentStrategy();

      final skipped = await strategy.execute<String>(
        () async => 'ran',
        isSyncInProgress: () => true,
        onSkipped: () => 'skipped',
      );
      expect(skipped, 'skipped');

      final ran = await strategy.execute<String>(
        () async => 'ran',
        isSyncInProgress: () => false,
        onSkipped: () => 'skipped',
      );
      expect(ran, 'ran');
      expect(strategy.dispose, returnsNormally);
    });
  });

  group('DatumConflictResolution.copyWith', () {
    test('resolvedData: override, preservation, and explicit clearing', () {
      final a = _entity('e1');
      final b = _entity('e2');
      final resolution = DatumConflictResolution<TestEntity>.useLocal(a);

      final overridden = resolution.copyWith(resolvedData: b);
      expect(overridden.resolvedData, same(b));
      expect(overridden.strategy, DatumResolutionStrategy.takeLocal);

      final preserved = resolution.copyWith(message: 'kept');
      expect(preserved.resolvedData, same(a));
      expect(preserved.message, 'kept');

      final cleared = resolution.copyWith(setResolvedDataToNull: true);
      expect(cleared.resolvedData, isNull);
      expect(cleared.strategy, DatumResolutionStrategy.takeLocal);
    });
  });
}
