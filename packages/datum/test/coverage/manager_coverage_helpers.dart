import 'dart:async';

import 'package:datum/datum.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/test_entity.dart';

/// A simple, always-online connectivity checker (no mocking framework needed).
class OnlineConnectivity implements DatumConnectivityChecker {
  const OnlineConnectivity();

  @override
  Future<bool> get isConnected async => true;

  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}

/// A local adapter whose failure modes can be toggled per test.
class FlakyLocalAdapter<T extends DatumEntityInterface> extends MockLocalAdapter<T> {
  FlakyLocalAdapter({super.fromJson});

  /// When true, [delete] throws.
  bool throwOnDelete = false;

  /// When true, [delete] returns false without deleting.
  bool deleteReturnsFalse = false;

  /// When true, [read] throws when called WITH a userId.
  bool throwOnReadWithUserId = false;

  /// When true, [read] throws when called WITHOUT a userId (the
  /// `performDeleteWithoutEvents` lookup path).
  bool throwOnReadWithoutUserId = false;

  /// When true, [updateAll] throws (persist-fetched-locally path).
  bool throwOnUpdateAll = false;

  /// When true, [getPendingOperations] throws (makes synchronize fail).
  bool throwOnGetPendingOps = false;

  /// Number of times [getPendingOperations] has been invoked.
  int pendingOpsCallCount = 0;

  @override
  Future<bool> delete(String id, {String? userId}) async {
    if (throwOnDelete) throw StateError('delete failure (test)');
    if (deleteReturnsFalse) return false;
    return super.delete(id, userId: userId);
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    if (userId != null && throwOnReadWithUserId) {
      throw StateError('read-with-user failure (test)');
    }
    if (userId == null && throwOnReadWithoutUserId) {
      throw StateError('read-without-user failure (test)');
    }
    return super.read(id, userId: userId);
  }

  @override
  Future<void> updateAll(List<T> entities) async {
    if (throwOnUpdateAll) throw StateError('updateAll failure (test)');
    return super.updateAll(entities);
  }

  @override
  Future<List<DatumSyncOperation<T>>> getPendingOperations(String userId) async {
    pendingOpsCallCount++;
    if (throwOnGetPendingOps) throw StateError('pending ops failure (test)');
    return super.getPendingOperations(userId);
  }
}

/// A local adapter with a test-controlled change stream so errors can be
/// injected into the manager's local change subscription.
class ControlledChangeLocalAdapter<T extends DatumEntityInterface> extends MockLocalAdapter<T> {
  ControlledChangeLocalAdapter({super.fromJson});

  final changeCtrl = StreamController<DatumChangeDetail<T>>.broadcast();

  @override
  Stream<DatumChangeDetail<T>>? changeStream() => changeCtrl.stream;

  @override
  Future<void> dispose() async {
    if (!changeCtrl.isClosed) await changeCtrl.close();
    await super.dispose();
  }
}

/// A remote adapter with a test-controlled change stream so errors can be
/// injected into the manager's remote change subscription.
class ControlledChangeRemoteAdapter<T extends DatumEntityInterface> extends MockRemoteAdapter<T> {
  ControlledChangeRemoteAdapter({super.fromJson});

  final changeCtrl = StreamController<DatumChangeDetail<T>>.broadcast();

  @override
  Stream<DatumChangeDetail<T>>? get changeStream => changeCtrl.stream;

  @override
  Future<void> dispose() async {
    if (!changeCtrl.isClosed) await changeCtrl.close();
    await super.dispose();
  }
}

/// A local adapter whose watch streams are driven directly by the test,
/// allowing stream-level errors to be injected into watchAll/watchById/watchQuery.
class WatchStreamLocalAdapter<T extends DatumEntityInterface> extends MockLocalAdapter<T> {
  WatchStreamLocalAdapter({super.fromJson});

  final watchAllCtrl = StreamController<List<T>>.broadcast();
  final watchByIdCtrl = StreamController<T?>.broadcast();
  final watchQueryCtrl = StreamController<List<T>>.broadcast();

  @override
  Stream<List<T>>? watchAll({String? userId, bool? includeInitialData}) => watchAllCtrl.stream;

  @override
  Stream<T?>? watchById(String id, {String? userId}) => watchByIdCtrl.stream;

  @override
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) => watchQueryCtrl.stream;

  @override
  Future<void> dispose() async {
    if (!watchAllCtrl.isClosed) await watchAllCtrl.close();
    if (!watchByIdCtrl.isClosed) await watchByIdCtrl.close();
    if (!watchQueryCtrl.isClosed) await watchQueryCtrl.close();
    await super.dispose();
  }
}

/// A remote adapter that supports raw queries.
class RawCapableRemoteAdapter<T extends DatumEntityInterface> extends MockRemoteAdapter<T> with RawQueryCapable {
  RawCapableRemoteAdapter({super.fromJson});

  DatumRawQuery? lastRawQuery;

  @override
  Future<List<DatumRawRow>> rawQuery(DatumRawQuery query, {String? userId}) async {
    lastRawQuery = query;
    return [
      {'total': 42},
    ];
  }
}

/// A middleware whose post-fetch transform throws for one entity id and
/// renames every other entity it sees.
class ThrowingAfterFetchMiddleware extends DatumMiddleware<TestEntity> {
  ThrowingAfterFetchMiddleware(this.throwForId);

  final String throwForId;

  @override
  FutureOr<TestEntity> transformAfterFetch(TestEntity item) {
    if (item.id == throwForId) {
      throw StateError('transformAfterFetch failure for ${item.id} (test)');
    }
    return item.copyWith(name: 'transformed-${item.name}');
  }
}

/// A global observer that records delete notifications.
class RecordingGlobalObserver extends GlobalDatumObserver {
  final deleteEndCalls = <(String, bool)>[];

  @override
  void onDeleteEnd(String id, {required bool success}) {
    deleteEndCalls.add((id, success));
  }
}

/// Creates a [TestEntity] with fixed timestamps for deterministic tests.
TestEntity makeEntity(
  String id, {
  String userId = 'u1',
  String name = 'name',
  int value = 0,
  int version = 1,
  DateTime? modifiedAt,
}) =>
    TestEntity(
      id: id,
      userId: userId,
      name: name,
      value: value,
      modifiedAt: modifiedAt ?? DateTime(2024, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      version: version,
    );

/// Creates a remote-style change detail for [entity].
DatumChangeDetail<TestEntity> changeFor(
  TestEntity entity, {
  DatumOperationType type = DatumOperationType.create,
}) =>
    DatumChangeDetail<TestEntity>(
      entityId: entity.id,
      userId: entity.userId,
      type: type,
      timestamp: DateTime.now(),
      data: type == DatumOperationType.delete ? null : entity,
    );

/// Creates a delete change detail for [id].
DatumChangeDetail<TestEntity> deleteChangeFor(String id, {String userId = 'u1'}) => DatumChangeDetail<TestEntity>(
      entityId: id,
      userId: userId,
      type: DatumOperationType.delete,
      timestamp: DateTime.now(),
    );

/// Lets pending microtasks/timers settle.
Future<void> settle([int milliseconds = 30]) => Future<void>.delayed(Duration(milliseconds: milliseconds));
