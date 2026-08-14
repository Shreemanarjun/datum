---



title: Observers & Middleware
---


The Observers & Middleware module provides hooks for customizing and monitoring Datum operations through observers and middleware.

## Overview

Observers and middleware allow you to intercept, modify, and monitor data operations throughout the Datum system. They provide powerful extension points for logging, validation, transformation, and custom business logic.

## Middleware

### DatumMiddleware<T>

Middleware intercepts and can transform entities as they flow through save and fetch operations. Both hooks return `FutureOr<T>` and default to passing the entity through unchanged.

**Key Methods:**
- `transformBeforeSave(T item)`: Transforms an entity before it is saved via a create or update operation
- `transformAfterFetch(T item)`: Transforms an entity after it has been fetched from a data source

### Creating Middleware

```dart
class EncryptionMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> transformBeforeSave(Task item) async {
    // Encrypt sensitive data before saving
    return item.copyWith(description: await encrypt(item.description ?? ''));
  }

  @override
  Future<Task> transformAfterFetch(Task item) async {
    // Decrypt sensitive data after fetching
    return item.copyWith(description: await decrypt(item.description ?? ''));
  }
}

class ValidationMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> transformBeforeSave(Task item) async {
    // Validate before the entity reaches the adapters
    if (item.title.isEmpty) {
      throw const DatumException(
        code: DatumExceptionCode.validationError,
        message: 'Title is required',
      );
    }
    return item;
  }
}

class AuditMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> transformBeforeSave(Task item) async {
    // Stamp audit information onto the entity before saving
    return item.copyWith(
      description: '${item.description ?? ''} [edited ${DateTime.now().toIso8601String()}]',
    );
  }
}

Future<String> encrypt(String value) async => value; // your cipher here
Future<String> decrypt(String value) async => value; // your cipher here
```

### Registering Middleware

```dart continue
final registrations = [
  DatumRegistration<Task>(
    localAdapter: localAdapter,
    remoteAdapter: remoteAdapter,
    middlewares: [
      EncryptionMiddleware(),
      ValidationMiddleware(),
      AuditMiddleware(),
    ],
  ),
];
```

### Middleware Execution Order

Middleware executes in registration order for **both** hooks:

```dart
// Execution flow for saving:
// 1. EncryptionMiddleware.transformBeforeSave
// 2. ValidationMiddleware.transformBeforeSave
// 3. AuditMiddleware.transformBeforeSave
// 4. Save to local adapter (and queue for remote sync)

// Execution flow when fetching:
// 1. EncryptionMiddleware.transformAfterFetch
// 2. ValidationMiddleware.transformAfterFetch
// 3. AuditMiddleware.transformAfterFetch
```

## Observers

### DatumObserver<T>

Observers monitor data operations without modifying them. All hooks are synchronous `void` callbacks with empty default implementations — override only the ones you need.

**Lifecycle Hooks:**
- `onCreateStart(T item)` / `onCreateEnd(T item)`: Around a `create` operation
- `onUpdateStart(T item)` / `onUpdateEnd(T item)`: Around an `update` operation
- `onDeleteStart(String id)` / `onDeleteEnd(String id, {required bool success})`: Around a `delete` operation
- `onSyncStart()` / `onSyncEnd(DatumSyncResult result)`: Around a synchronization cycle
- `onConflictDetected(T local, T remote, DatumConflictContext context)`: When a conflict is detected
- `onConflictResolved(DatumConflictResolution<T> resolution)`: After a conflict has been resolved
- `onUserSwitchStart(String? oldUserId, String newUserId, UserSwitchStrategy strategy)` / `onUserSwitchEnd(DatumUserSwitchResult result)`: Around a user switch

### Creating Observers

```dart
class LoggingObserver extends DatumObserver<Task> {
  final DatumLogger log = DatumLogger();

  @override
  void onCreateEnd(Task item) {
    log.info('Created task: ${item.title}');
  }

  @override
  void onUpdateEnd(Task item) {
    log.info('Updated task ${item.id} (v${item.version})');
  }

  @override
  void onDeleteEnd(String id, {required bool success}) {
    if (success) log.warn('Deleted task: $id');
  }

  @override
  void onSyncEnd(DatumSyncResult result) {
    log.info('Sync finished: ${result.syncedCount} synced, ${result.failedCount} failed');
  }
}

class NotificationObserver extends DatumObserver<Task> {
  @override
  void onUpdateEnd(Task item) {
    if (item.isCompleted) {
      sendNotification('Task completed: ${item.title}');
    }
  }

  void sendNotification(String message) {
    // Integrate your push/notification service here
  }
}

class CacheInvalidationObserver extends DatumObserver<Task> {
  final Map<String, Task> cache = {};

  @override
  void onUpdateEnd(Task item) {
    cache.remove(item.id);
  }

  @override
  void onDeleteEnd(String id, {required bool success}) {
    if (success) cache.remove(id);
  }
}
```

### Registering Observers

```dart continue
final registrations = [
  DatumRegistration<Task>(
    localAdapter: localAdapter,
    remoteAdapter: remoteAdapter,
    observers: [
      LoggingObserver(),
      NotificationObserver(),
      CacheInvalidationObserver(),
    ],
  ),
];
```

## Global Observers

### GlobalDatumObserver

Global observers extend `DatumObserver<DatumEntityInterface>` and monitor **every** registered entity type. They receive the same lifecycle hooks (`onCreateStart`/`End`, `onUpdateStart`/`End`, `onDeleteStart`/`End`, `onSyncStart`/`onSyncEnd`, conflict and user-switch hooks) with `DatumEntityInterface` in place of the concrete entity type.

### Creating Global Observers

```dart
class GlobalAnalyticsObserver extends GlobalDatumObserver {
  @override
  void onSyncStart() {
    print('sync_started at ${DateTime.now().toIso8601String()}');
  }

  @override
  void onSyncEnd(DatumSyncResult result) {
    print('sync_completed in ${result.duration.inMilliseconds}ms: '
        '${result.syncedCount} synced, ${result.failedCount} failed, '
        '${result.conflictsResolved} conflicts resolved');
  }
}

class GlobalHealthObserver extends GlobalDatumObserver {
  @override
  void onCreateEnd(DatumEntityInterface item) {
    print('Entity created: ${item.runtimeType} ${item.id}');
  }

  @override
  void onSyncEnd(DatumSyncResult result) {
    // Alert on sync failures
    if (result.failedCount > 0) {
      print('ALERT: sync completed with ${result.failedCount} failures');
    }
  }
}

// Your app's connectivity checker (see the Utils module)
class AppConnectivity implements DatumConnectivityChecker {
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}
```

### Registering Global Observers

```dart continue
await Datum.initialize(
  config: const DatumConfig(),
  connectivityChecker: AppConnectivity(),
  registrations: [
    DatumRegistration<Task>(
      localAdapter: localAdapter,
      remoteAdapter: remoteAdapter,
    ),
  ],
  observers: [
    GlobalAnalyticsObserver(),
    GlobalHealthObserver(),
  ],
);
```

## Advanced Patterns

### Conditional Middleware

```dart
class ConditionalEncryptionMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> transformBeforeSave(Task item) async {
    // Only encrypt high-priority tasks
    if (item.priority > 3) {
      return item.copyWith(description: await encrypt(item.description ?? ''));
    }
    return item;
  }

  @override
  Future<Task> transformAfterFetch(Task item) async {
    if (item.priority > 3) {
      return item.copyWith(description: await decrypt(item.description ?? ''));
    }
    return item;
  }
}

Future<String> encrypt(String value) async => value; // your cipher here
Future<String> decrypt(String value) async => value; // your cipher here
```

### Composite Observers

```dart
class CompositeObserver extends DatumObserver<Task> {
  final List<DatumObserver<Task>> _observers;

  CompositeObserver(this._observers);

  @override
  void onCreateEnd(Task item) {
    for (final observer in _observers) {
      observer.onCreateEnd(item);
    }
  }

  @override
  void onUpdateEnd(Task item) {
    for (final observer in _observers) {
      observer.onUpdateEnd(item);
    }
  }

  @override
  void onDeleteEnd(String id, {required bool success}) {
    for (final observer in _observers) {
      observer.onDeleteEnd(id, success: success);
    }
  }
}
```

### Async Middleware

```dart
class AsyncValidationMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> transformBeforeSave(Task item) async {
    // Perform async validation (e.g. check uniqueness against a service)
    final duplicate = await findByTitle(item.title);
    if (duplicate != null && duplicate.id != item.id) {
      throw const DatumException(
        code: DatumExceptionCode.validationError,
        message: 'A task with this title already exists',
      );
    }
    return item;
  }

  Future<Task?> findByTitle(String title) async {
    // Query your backend or local store here
    return null;
  }
}
```

### Error Handling in Middleware/Observers

```dart
class ResilientObserver extends DatumObserver<Task> {
  final DatumLogger log = DatumLogger();

  @override
  void onCreateEnd(Task item) {
    try {
      sendWelcomeNotification(item);
    } catch (e) {
      // Log the error but never fail the operation
      log.error('Failed to send welcome notification: $e');
    }
  }

  void sendWelcomeNotification(Task item) {
    // Notification integration here
  }
}

class SafeMiddleware extends DatumMiddleware<Task> {
  final DatumLogger log = DatumLogger();

  @override
  Future<Task> transformBeforeSave(Task item) async {
    try {
      return await performTransformation(item);
    } catch (e) {
      log.error('Middleware transformation failed: $e');
      // Return the original entity to allow the operation to continue
      return item;
    }
  }

  Future<Task> performTransformation(Task item) async {
    // Actual transformation logic here
    return item;
  }
}
```

Observer callbacks are additionally wrapped in an internal error boundary by the manager, so a throwing observer is isolated and cannot break the data operation it observes.

## Performance Considerations

### Middleware Performance

1. **Keep transformations fast**: Avoid heavy computations in middleware
2. **Use async carefully**: Async operations can impact performance
3. **Cache results**: Cache expensive operations when possible
4. **Batch operations**: Process multiple entities together when possible

### Observer Performance

1. **Make observers lightweight**: Hooks are synchronous and run inline with operations
2. **Offload heavy work**: Kick off futures from a hook rather than blocking in it
3. **Batch notifications**: Send batched notifications when possible
4. **Conditional execution**: Only execute when necessary

### Memory Management

1. **Clean up resources**: Dispose of resources in observers/middleware
2. **Avoid memory leaks**: Be careful with stream subscriptions
3. **Limit concurrent operations**: Control concurrency in middleware

## Testing

### Testing Middleware

```dart
import 'package:test/test.dart';

void main() {
  test('EncryptionMiddleware transforms the description', () async {
    final middleware = EncryptionMiddleware();
    final task = Task(
      id: 't1',
      userId: 'u1',
      title: 'Test',
      description: 'secret data',
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      version: 1,
    );

    final transformed = await middleware.transformBeforeSave(task);

    expect(await decrypt(transformed.description!), equals('secret data'));
  });

  test('ValidationMiddleware rejects an empty title', () async {
    final middleware = ValidationMiddleware();
    final invalid = Task(
      id: 't2',
      userId: 'u1',
      title: '',
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      version: 1,
    );

    expect(
      () => middleware.transformBeforeSave(invalid),
      throwsA(isA<DatumException>()),
    );
  });
}
```

### Testing Observers

```dart
import 'package:test/test.dart';

void main() {
  test('CacheInvalidationObserver evicts updated entries', () {
    final observer = CacheInvalidationObserver();
    final task = Task(
      id: 't1',
      userId: 'u1',
      title: 'Cached',
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      version: 1,
    );

    observer.cache['t1'] = task;
    observer.onUpdateEnd(task);

    expect(observer.cache.containsKey('t1'), isFalse);
  });
}
```

## Best Practices

### Middleware Best Practices

1. **Keep it focused**: Each middleware should have a single responsibility
2. **Make it idempotent**: Running multiple times should be safe
3. **Handle errors gracefully**: Don't break operations due to middleware failures
4. **Document transformations**: Clearly document what each middleware does
5. **Test thoroughly**: Test edge cases and error conditions

### Observer Best Practices

1. **Don't modify data**: Observers should only observe, not modify
2. **Handle failures**: Don't let observer failures break operations
3. **Be efficient**: Keep observers lightweight and fast
4. **Use appropriate scope**: Choose between entity-specific and global observers

### General Best Practices

1. **Order matters**: Middleware runs in registration order for both hooks
2. **Avoid dependencies**: Minimize dependencies between middleware/observers
3. **Monitor performance**: Track the impact of middleware on performance
4. **Version carefully**: Consider versioning when changing middleware behavior
5. **Document behavior**: Clearly document what each component does

## Common Use Cases

### Authentication & Authorization

```dart
class AuthorizationMiddleware extends DatumMiddleware<Task> {
  final String currentUserId;

  AuthorizationMiddleware(this.currentUserId);

  @override
  Future<Task> transformBeforeSave(Task item) async {
    if (item.userId != currentUserId) {
      throw const DatumException(
        code: DatumExceptionCode.authorizationError,
        message: 'Not authorized to edit this task',
      );
    }
    return item;
  }
}
```

### Data Enrichment

```dart
class EnrichmentMiddleware extends DatumMiddleware<Task> {
  @override
  Future<Task> transformAfterFetch(Task item) async {
    // Attach computed data after fetching
    final subtaskCount = await countSubtasks(item.id);
    return item.copyWith(
      description: '${item.description ?? ''} ($subtaskCount subtasks)',
    );
  }

  Future<int> countSubtasks(String taskId) async {
    // Query your data source here
    return 0;
  }
}
```

### Audit Trail

```dart
class AuditObserver extends DatumObserver<Task> {
  @override
  void onUpdateEnd(Task item) {
    recordAudit(
      entityType: 'Task',
      entityId: item.id,
      userId: item.userId,
      version: item.version,
      timestamp: DateTime.now(),
    );
  }

  void recordAudit({
    required String entityType,
    required String entityId,
    required String userId,
    required int version,
    required DateTime timestamp,
  }) {
    // Persist to your audit log
  }
}
```

### Caching

```dart
class CacheObserver extends DatumObserver<Task> {
  final Map<String, Task> cache = {};

  @override
  void onUpdateEnd(Task item) {
    // Refresh the cache with the new data
    cache[item.id] = item;
  }

  @override
  void onDeleteEnd(String id, {required bool success}) {
    if (success) cache.remove(id);
  }
}
```
