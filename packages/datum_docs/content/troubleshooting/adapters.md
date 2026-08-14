---




title: 🔌 Adapter Troubleshooting
description: Debug and resolve adapter-specific issues in Datum.
---


Debug and resolve issues specific to Datum adapters (local and remote).

## Local Adapter Issues

### Issue: Hive adapter initialization failure

**Symptoms:** `Hive.initFlutter()` or box opening fails

**Common Causes:**
- Hive not initialized before `Datum.initialize()`
- Permission issues on device storage
- Concurrent access conflicts / corrupted box files

**Resolution Steps:**

`datum_hive`'s `HiveLocalAdapter` opens its own boxes inside `initialize()` —
you only need to initialize Hive itself first:

```dart
import 'package:flutter/widgets.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive BEFORE Datum — the adapter opens its boxes
  // ('<entityBoxName>', '<entityBoxName>_pending_ops',
  //  '<entityBoxName>_metadata') during Datum initialization.
  await Hive.initFlutter();

  await Datum.initialize(
    config: const DatumConfig(),
    connectivityChecker: const SnippetConnectivity(),
    registrations: [
      DatumRegistration<Task>(
        localAdapter: HiveLocalAdapter<Task>(
          entityBoxName: 'tasks',
          fromMap: Task.fromMap,
        ),
        remoteAdapter: MyTaskRemoteAdapter(),
      ),
    ],
  );
}
```

Entities are stored as plain maps, so no Hive `TypeAdapter` registration or
code generation is required.

If a box file is corrupted, delete it and let the next full sync rebuild it:

```dart
import 'package:hive_ce_flutter/hive_flutter.dart';

Future<void> recoverCorruptedBox(String boxName) async {
  try {
    await Hive.openBox<Map<dynamic, dynamic>>(boxName);
  } catch (e) {
    // Clear the corrupted box, then re-open a fresh one
    await Hive.deleteBoxFromDisk(boxName);
    await Hive.openBox<Map<dynamic, dynamic>>(boxName);
  }
}
```

### Issue: Isar database corruption

**Symptoms:** Isar queries fail with corruption errors

**Recovery Strategies:**
```dart
import 'dart:io';
import 'package:isar/isar.dart';

class IsarRecoveryManager {
  static Future<void> recoverCorruptedDatabase(
    String databasePath,
  ) async {
    try {
      // Close existing instance
      await Isar.getInstance()?.close();

      // Delete corrupted files
      final dir = Directory(databasePath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      // Reinitialize
      final isar = await Isar.open(
        schemas: [TaskSchema],
        directory: databasePath,
      );

      print('Database recovered successfully');
    } catch (e) {
      print('Recovery failed: $e');
      rethrow;
    }
  }
}
```

### Issue: SQLite database locked

**Symptoms:** "Database locked" errors during concurrent operations

**Transaction Management:**

`datum_sqlite`'s `SqliteLocalAdapter` shares one `sqlite3` `Database` between
adapters (one per entity type) and supports real transactions via the
`TransactionalAdapter` capability:

```dart
final adapter = SqliteLocalAdapter<Task>(
  database: db, // the shared sqlite3 Database
  table: 'tasks',
  fromMap: Task.fromMap,
);
await adapter.initialize();

// Group writes into a single transaction so they don't
// contend for the database lock.
await adapter.transaction(() async {
  await adapter.createAll([task]);
  await adapter.update(task.copyWith(isCompleted: true));
});
```

Note that `LocalAdapter.transaction` takes a zero-argument callback — you keep
using the adapter itself inside the transaction, not a separate `txn` handle.

## Remote Adapter Issues

### Issue: Supabase connection and authentication failures

**Symptoms:** Supabase operations fail with connection or auth errors

**Common Issues & Solutions:**

**Connection Setup:**
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

// 1. Verify Supabase configuration
void main() async {
  await Supabase.initialize(
    url: 'https://your-project.supabase.co',
    publishableKey: 'your-publishable-key',
  );
}

// 2. Check connection status
class SupabaseHealthCheck {
  static Future<bool> isConnected() async {
    try {
      // Test connection with a simple query
      final response = await Supabase.instance.client
          .from('health_check')
          .select('status')
          .limit(1)
          .single();

      return response.isNotEmpty;
    } catch (e) {
      print('Supabase connection failed: $e');
      return false;
    }
  }
}
```

**Authentication Issues:**
```dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

// Handle auth state changes
class SupabaseAuthManager {
  StreamSubscription<AuthState>? _authSubscription;

  void initializeAuthListener() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (event) {
        switch (event.event) {
          case AuthChangeEvent.signedIn:
            print('User signed in: ${event.session?.user.id}');
            // Start Datum sync for the signed-in user
            break;
          case AuthChangeEvent.signedOut:
            print('User signed out');
            // Pause sync while nobody is signed in
            Datum.instance.pauseSync();
            break;
          case AuthChangeEvent.tokenRefreshed:
            print('Token refreshed');
            // The Supabase client picks the new token up automatically
            break;
          default:
            break;
        }
      },
      onError: (error) {
        print('Auth error: $error');
        // Handle auth errors (network issues, expired tokens, etc.)
      },
    );
  }

  void dispose() {
    _authSubscription?.cancel();
  }
}
```

**RLS (Row Level Security) Issues:**
```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// Debug RLS policies
class SupabaseRLSDebugger {
  static Future<void> testRLSPolicies(String userId) async {
    try {
      // Test read access
      final readTest = await Supabase.instance.client
          .from('tasks')
          .select('*')
          .eq('user_id', userId)
          .limit(1);

      print('Read access: ✅');

      // Test write access
      await Supabase.instance.client.from('tasks').insert({
        'id': const Uuid().v4(),
        'user_id': userId,
        'title': 'RLS Test',
        'created_at': DateTime.now().toIso8601String(),
      });

      print('Write access: ✅');
    } catch (e) {
      print('RLS Error: $e');
      print('Check your RLS policies in Supabase dashboard');
      print('Example policy:');
      print('CREATE POLICY "Users can access their own tasks"');
      print('ON tasks FOR ALL USING (auth.uid()::text = user_id);');
    }
  }
}
```

**Real-time Subscription Issues:**
```dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseRealtimeManager {
  StreamSubscription? _subscription;

  void setupRealtimeSubscription(String userId) {
    // Clean up existing subscription
    _subscription?.cancel();

    // Subscribe to changes for this user's rows
    _subscription = Supabase.instance.client
        .from('tasks')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen(
          (rows) {
            print('Realtime update: ${rows.length} rows');
            // Feed the change into your RemoteAdapter's changeStream
          },
          onError: (error) {
            print('Realtime subscription failed: $error');
            // Retry with a delay
            Future.delayed(const Duration(seconds: 5), () {
              setupRealtimeSubscription(userId);
            });
          },
        );
  }

  void dispose() {
    _subscription?.cancel();
  }
}
```

**Storage and File Upload Issues:**
```dart
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseStorageManager {
  static Future<String?> uploadFile(
    String bucket,
    String fileName,
    Uint8List fileData,
  ) async {
    try {
      final fileExt = fileName.split('.').last;
      final filePath = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await Supabase.instance.client.storage
          .from(bucket)
          .uploadBinary(filePath, fileData);

      // Get public URL
      final publicUrl =
          Supabase.instance.client.storage.from(bucket).getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      print('File upload failed: $e');

      // Check storage permissions
      if (e.toString().contains('permission')) {
        print('Check storage bucket policies in Supabase dashboard');
      }
    }
    return null;
  }
}
```

### Issue: REST API authentication failures

**Symptoms:** 401/403 errors from API endpoints

**Authentication Handling:**
```dart
import 'package:dio/dio.dart';

class AuthenticatedRestAdapter extends RemoteAdapter<Task> {
  final Dio _dio;
  String? _authToken;

  AuthenticatedRestAdapter(this._dio) {
    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_authToken != null) {
            options.headers['Authorization'] = 'Bearer $_authToken';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            // Token expired, try refresh
            try {
              _authToken = await refreshAuthToken();
              // Retry the request
              final response = await _dio.request(
                error.requestOptions.path,
                options: Options(
                  method: error.requestOptions.method,
                  headers: {
                    ...error.requestOptions.headers,
                    'Authorization': 'Bearer $_authToken',
                  },
                ),
                data: error.requestOptions.data,
              );
              return handler.resolve(response);
            } catch (e) {
              // Refresh failed, logout user
              await logoutUser();
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<String?> refreshAuthToken() async {
    try {
      final response = await _dio.post('/auth/refresh');
      return response.data['token'];
    } catch (e) {
      return null;
    }
  }
}
```

Inside a Datum adapter, prefer throwing the typed exceptions so the sync
engine can classify failures — e.g. `NetworkException(message: ..., isRetryable: true)`
for transient transport errors, or a `DatumException` with
`DatumExceptionCode.authenticationError` when credentials are rejected.

### Issue: GraphQL adapter query failures

**Symptoms:** GraphQL queries return errors or null data

**Query Debugging:**
```dart
import 'package:graphql/client.dart';

class GraphQLAdapter extends RemoteAdapter<Task> {
  final GraphQLClient _client;

  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) async {
    const query = r'''
      query GetTasks($userId: ID!, $limit: Int) {
        tasks(userId: $userId, limit: $limit) {
          id
          title
          description
          isCompleted
          createdAt
          modifiedAt
        }
      }
    ''';

    final options = QueryOptions(
      document: gql(query),
      variables: {
        'userId': userId,
        // scope.query carries the filters/limit for a scoped pull
        'limit': scope?.query.limit ?? 100,
      },
    );

    final result = await _client.query(options);

    if (result.hasException) {
      print('GraphQL Error: ${result.exception}');
      // Log detailed error information
      for (final error in result.exception!.graphqlErrors) {
        print('GraphQL Error: ${error.message}');
        print('Path: ${error.path}');
        print('Extensions: ${error.extensions}');
      }
      throw result.exception!;
    }

    final tasks = result.data?['tasks'] as List? ?? [];
    return tasks.map((json) => Task.fromMap(json)).toList();
  }
}
```

### Issue: Supabase real-time subscription failures

**Symptoms:** Real-time updates not working

**Subscription Management:**
```dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAdapter extends RemoteAdapter<Task> {
  final SupabaseClient _client;
  StreamSubscription? _subscription;

  void setupRealtimeSync(String userId) {
    _subscription?.cancel();

    _subscription = _client
        .from('tasks')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((rows) {
          // Emit the change through the adapter's changeStream so the
          // manager can merge it (do NOT write to the local adapter
          // directly — that bypasses conflict resolution).
          for (final row in rows) {
            final task = Task.fromMap(row);
            emitChange(task);
          }
        });
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await super.dispose();
  }
}
```

## Firebase Adapter Issues

### Issue: Firestore permission errors

**Symptoms:** Firestore operations fail with permission-denied

**Security Rules Debugging:**
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Debug security rules locally
class FirestoreDebugAdapter extends RemoteAdapter<Task> {
  final FirebaseFirestore _firestore;

  @override
  Future<void> create(Task item) async {
    try {
      await _firestore
          .collection('tasks')
          .doc(item.id)
          .set(item.toDatumMap(target: MapTarget.remote));
    } catch (e) {
      print('Firestore create error: $e');
      // Check if it's a permission error
      if (e is FirebaseException && e.code == 'permission-denied') {
        print('Check Firestore security rules for tasks collection');
        print('Current user: ${FirebaseAuth.instance.currentUser?.uid}');
      }
      rethrow;
    }
  }
}

// Firestore Security Rules Example
/*
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /tasks/{taskId} {
      allow read, write: if request.auth != null &&
        request.auth.uid == resource.data.userId;
    }
  }
}
*/
```

### Issue: Firebase offline persistence conflicts

**Symptoms:** Local changes conflict with server state

Datum is already your offline layer — disable Firestore's own persistence so
the two don't fight over who owns offline state:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseAdapter extends RemoteAdapter<Task> {
  final FirebaseFirestore _firestore;

  FirebaseAdapter() : _firestore = FirebaseFirestore.instance {
    // Let Datum's local adapter be the single source of offline truth
    _firestore.settings = const Settings(
      persistenceEnabled: false,
    );
  }

  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) async {
    // Always read server state — Datum handles caching locally
    final snapshot = await _firestore
        .collection('tasks')
        .where('userId', isEqualTo: userId)
        .get(const GetOptions(source: Source.server));

    return snapshot.docs.map((doc) => Task.fromMap(doc.data())).toList();
  }
}
```

## Adapter Testing

### Conformance Suites

`package:datum_test` ships behavioral conformance suites — run them against
every adapter you build instead of hand-writing CRUD assertions:

```dart
Future<void> main() async {
  // Local adapter contract: CRUD round-trips, queries, watch streams,
  // pending operations, schema versioning, user isolation, ...
  runLocalAdapterConformanceTests(
    name: 'sqlite',
    create: () async {
      final adapter = SqliteLocalAdapter<ConformanceEntity>(
        database: sqlite3.openInMemory(),
        table: 'conformance_entities',
        fromMap: ConformanceEntity.fromMap,
      );
      await adapter.initialize();
      return adapter;
    },
  );

  // Remote adapter contract, over real sockets against a LocalSyncServer
  final server = LocalSyncServer();
  await server.start();

  runRemoteAdapterConformanceTests(
    name: 'http',
    create: () async => HttpRemoteAdapter<ConformanceEntity>(
      baseUri: server.baseUri,
      fromMap: ConformanceEntity.fromMap,
    ),
  );
}
```

The `LocalSyncServer` test double also lets you inject latency, failures,
corrupted responses, and offline periods to exercise your error handling.

## Performance Optimization

### Connection Pooling

```dart
import 'package:dio/dio.dart';

class PooledHttpAdapter extends RemoteAdapter<Task> {
  final List<Dio> _clients;
  int _currentClient = 0;

  PooledHttpAdapter(int poolSize)
      : _clients = List.generate(
          poolSize,
          (i) => Dio(BaseOptions(
            baseUrl: 'https://api.example.com',
            connectTimeout: Duration(seconds: 5),
            receiveTimeout: Duration(seconds: 10),
          )),
        );

  Dio get _client {
    final client = _clients[_currentClient];
    _currentClient = (_currentClient + 1) % _clients.length;
    return client;
  }

  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) async {
    final response = await _client.get('/tasks', queryParameters: {
      'userId': userId,
    });
    return (response.data as List).map((json) => Task.fromMap(json)).toList();
  }
}
```

### Caching Strategies

```dart
class CachedItem<T> {
  CachedItem(this.data, Duration ttl) : expiry = DateTime.now().add(ttl);

  final T data;
  final DateTime expiry;

  bool get isExpired => DateTime.now().isAfter(expiry);
}

/// Wraps a real adapter with a short-lived read cache.
/// (Shown partially — forward the remaining members to [inner].)
abstract class CachedAdapter extends RemoteAdapter<Task> {
  CachedAdapter(this.inner);

  final RemoteAdapter<Task> inner;
  final Map<String, CachedItem<List<Task>>> _cache = {};

  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) async {
    final cacheKey = 'tasks_$userId';

    // Check cache first
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data;
    }

    // Fetch from remote
    final data = await inner.readAll(userId: userId, scope: scope);

    // Cache the result
    _cache[cacheKey] = CachedItem(data, const Duration(minutes: 5));

    return data;
  }
}
```

## Best Practices

### 1. Error Handling

The sync engine already retries via `DatumConfig.errorRecoveryStrategy` — an
adapter-level retry wrapper is only needed for reads outside the sync cycle:

```dart
/// (Shown partially — forward the remaining members to [inner].)
abstract class ResilientAdapter extends RemoteAdapter<Task> {
  ResilientAdapter(this.inner);

  final RemoteAdapter<Task> inner;

  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) async {
    const maxRetries = 3;
    var attempt = 0;

    while (true) {
      try {
        return await inner.readAll(userId: userId, scope: scope);
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) rethrow;

        // Exponential backoff
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }
}
```

### 2. Logging and Monitoring

```dart
/// (Shown partially — forward the remaining members to [inner].)
abstract class MonitoredAdapter extends RemoteAdapter<Task> {
  MonitoredAdapter(this.inner);

  final RemoteAdapter<Task> inner;

  @override
  Future<void> create(Task entity) async {
    final stopwatch = Stopwatch()..start();
    try {
      await inner.create(entity);
      stopwatch.stop();
      await logOperation('create', stopwatch.elapsed, success: true);
    } catch (e) {
      stopwatch.stop();
      await logOperation('create', stopwatch.elapsed, success: false, error: e);
      rethrow;
    }
  }

  Future<void> logOperation(
    String operation,
    Duration duration, {
    required bool success,
    Object? error,
  }) async {
    // Send to your monitoring service
    print({
      'adapter': runtimeType.toString(),
      'operation': operation,
      'duration_ms': duration.inMilliseconds,
      'success': success,
      'error': error?.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
```

### 3. Resource Cleanup

```dart
import 'dart:async';

/// Adapters own their subscriptions and timers — release them in dispose().
abstract class DisposableAdapter extends RemoteAdapter<Task> {
  StreamSubscription<void>? _subscription;
  Timer? _healthCheckTimer;

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _healthCheckTimer?.cancel();
    // Close connections, clean up resources
  }
}
```

---


*For adapter implementation details, check the [Adapter Module](../../modules/adapter) documentation.*
