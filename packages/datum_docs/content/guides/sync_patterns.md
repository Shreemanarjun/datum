# Sync Patterns Guide




This guide covers common synchronization patterns and best practices for handling data sync in different scenarios like app startup, user login, and relogin.

## Table of Contents

- [Initial App Sync](#initial-app-sync)
- [Login/Relogin Sync](#loginrelogin-sync)
- [Force Fresh Data](#force-fresh-data)
- [Sync Status Monitoring](#sync-status-monitoring)
- [Common Patterns](#common-patterns)

## Initial App Sync

When your app starts, you want to ensure at least one remote data fetch happens to populate the app with current server data.

### Implementation

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

// In your app initializer (e.g., future_initializer_pod)
final datum = await Datum.initialize(
  config: config,
  connectivityChecker: connectivityChecker,
  registrations: registrations,
);

// Ensure at least one remote data fetch on app start
final datumInstance = datum.fold(
  (l, s) => throw l,
  (r) => r,
);

// If there's a current user, perform an initial sync
final currentUserId = Supabase.instance.client.auth.currentUser?.id;
if (currentUserId != null) {
  try {
    talker.info('Performing initial remote data fetch on app start');
    await datumInstance.synchronize(
      currentUserId,
      options: const DatumSyncOptions(
        direction: SyncDirection.pullThenPush,
        forceFullSync: true,
      ),
    );
    talker.info('Initial remote data fetch completed');
  } catch (e) {
    talker.warning('Initial sync failed, but app continues: $e');
    // Don't crash the app if initial sync fails
  }
}
```

### Key Points

- ✅ **Guaranteed remote call**: Ensures fresh data on app start
- ✅ **Non-blocking**: App continues if sync fails
- ✅ **User-aware**: Only syncs if user is authenticated
- ✅ **Proper logging**: Track success/failure

## Login/Relogin Sync

Handle sync when users login or relogin after logout, ensuring they always see fresh data.

### Implementation

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

// In your auth state listener
_authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
  (authState) async {
    if (authState.event == AuthChangeEvent.signedOut) {
      Datum.instance.pauseSync();
      // Navigate to login
    } else if (authState.event == AuthChangeEvent.signedIn) {
      final userId = authState.session?.user.id;
      if (userId != null) {
        // Show loading state
        setState(() => _waitingForInitialSync = true);

        // Setup sync status monitoring
        _updateSyncStatusListener(userId);

        // Resume sync (in case it was paused during logout)
        Datum.instance.resumeSync();

        // Clear sync metadata for fresh data
        final remoteAdapter = Datum.manager<Task>().remoteAdapter;
        if (remoteAdapter is SupabaseRemoteAdapter<Task>) {
          await remoteAdapter.clearSyncMetadata(userId);
        }

        // Perform eager sync
        await Datum.instance.synchronize(
          userId,
          options: const DatumSyncOptions(
            direction: SyncDirection.pullThenPush,
            forceFullSync: true,
          ),
        );
      }
    }
  },
);
```

### UI Loading State

```dart
import 'package:flutter/material.dart';

Widget _buildAuthenticatedBody(String userId) {
  if (_waitingForInitialSync) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Syncing latest data...'),
        ],
      ),
    );
  }

  // Show actual data
  final tasksAsync = ref.watch(tasksStreamProvider(userId));
  return TaskList(tasksAsync: tasksAsync);
}
```

### Sync Status Monitoring

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

void _updateSyncStatusListener(String userId) {
  _syncStatusSubscription.close();
  _syncStatusSubscription = ref.listenManual(
    syncStatusProvider(userId),
    (previous, next) {
      if (_waitingForInitialSync &&
          next != null &&
          next.hasValue &&
          next.value != null &&
          (next.value!.status == DatumSyncStatus.completed ||
           next.value!.status == DatumSyncStatus.idle ||
           next.value!.status == DatumSyncStatus.failed)) {
        setState(() => _waitingForInitialSync = false);
      }
    },
  );
}
```

## Fetch Initial Sync Metadata

You can fetch sync metadata from the server to understand a user's sync state before performing operations.

### Get Remote Sync Metadata

```dart
// Fetch sync metadata from the remote server
final remoteAdapter = Datum.manager<Task>().remoteAdapter;
final remoteMetadata = await remoteAdapter.getSyncMetadata(userId);

if (remoteMetadata != null) {
  print('User last synced: ${remoteMetadata.lastSuccessfulSyncTime}');
  print('Sync status: ${remoteMetadata.syncStatus}');
  print('Total conflicts: ${remoteMetadata.conflictCount}');
  print('Devices synced: ${remoteMetadata.deviceCount}');

  // Check if user has never synced
  if (remoteMetadata.isNeverSynced) {
    print('First time user - will do full sync');
  }

  // Check for conflicts
  if (remoteMetadata.hasConflicts) {
    print('User has ${remoteMetadata.conflictCount} conflicts to resolve');
  }
} else {
  print('No remote sync metadata found - first time sync');
}
```

### Sync Metadata Contents

The `DatumSyncMetadata` object contains:

```dart no-verify
// Abridged field reference of the real class:
class DatumSyncMetadata {
  final String userId;
  final DateTime? lastSyncTime;           // Last sync attempt
  final DateTime? lastSuccessfulSyncTime; // Last successful sync
  final String? dataHash;                 // Global data integrity hash
  final String? deviceId;                 // Current device ID
  final Map<String, DateTime>? devices;   // All synced devices
  final Map<String, dynamic>? customMetadata; // Custom fields
  final Map<String, DatumEntitySyncDetails>? entityCounts; // Per-entity stats
  final SyncStatus syncStatus;            // Current sync state
  final int syncVersion;                  // Metadata schema version
  final DateTime? serverTimestamp;        // Server clock at last sync
  final int conflictCount;                // Number of conflicts
  final String? errorMessage;             // Last error message
  final int retryCount;                   // Failed sync retries
  final int? syncDuration;                // Last sync duration (ms)
}
```

### Use Cases

- ✅ **Welcome screens**: Show "Welcome back!" vs "First time setup"
- ✅ **Sync progress**: Display last sync time and status
- ✅ **Conflict alerts**: Notify users of pending conflicts
- ✅ **Device management**: Show which devices have synced
- ✅ **Debugging**: Inspect sync state for troubleshooting
- ✅ **Conditional sync**: Skip sync if recently synced

### Compare Local vs Remote Metadata

```dart
// Get both local and remote metadata
final localAdapter = Datum.manager<Task>().localAdapter;
final remoteAdapter = Datum.manager<Task>().remoteAdapter;

final localMetadata = await localAdapter.getSyncMetadata(userId);
final remoteMetadata = await remoteAdapter.getSyncMetadata(userId);

// Compare last sync times
if (localMetadata?.lastSuccessfulSyncTime != null &&
    remoteMetadata?.lastSuccessfulSyncTime != null) {

  final localTime = localMetadata!.lastSuccessfulSyncTime!;
  final remoteTime = remoteMetadata!.lastSuccessfulSyncTime!;

  if (localTime.isBefore(remoteTime)) {
    print('Remote has newer data - sync needed');
  } else if (localTime.isAfter(remoteTime)) {
    print('Local has newer data - push needed');
  } else {
    print('Data is in sync');
  }
}
```

### Convenience APIs

For easier access, you can also use these convenience methods:

```dart
// On DatumManager (recommended for single entity)
final metadata = await Datum.manager<Task>().getRemoteSyncMetadata(userId);

// On the Datum instance (for any entity type)
final metadataViaDatum = await Datum.instance.getRemoteSyncMetadata<Task>(userId);
```

## Force Fresh Data

Sometimes you need to completely ignore cached sync state and force fresh data from the server.

### Clear Sync Metadata

```dart
import 'supabase_remote_adapter.dart'; // your adapter with a clearSyncMetadata helper

// Cast to specific adapter type to access clearSyncMetadata
final remoteAdapter = Datum.manager<Task>().remoteAdapter;
if (remoteAdapter is SupabaseRemoteAdapter<Task>) {
  await remoteAdapter.clearSyncMetadata(userId);
}
```

### Force Full Sync Options

```dart
const options = DatumSyncOptions(
  direction: SyncDirection.pullThenPush,  // Pull first, then push
  forceFullSync: true,                    // Ignore cached timestamps
);
```

### When to Use

- ✅ **Login/Relogin**: Ensure users see latest server data
- ✅ **Manual refresh**: When user explicitly requests fresh data
- ✅ **Data inconsistency**: When you suspect local data is stale
- ✅ **Testing**: To verify server data is loading correctly

## Sync Status Monitoring

Monitor sync progress and handle different sync states in your UI.

### Provider Setup

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final syncStatusProvider =
    StreamProvider.autoDispose.family<DatumSyncStatusSnapshot?, String>(
  (ref, userId) async* {
    final datum = ref.watch(simpleDatumProvider);
    yield* datum.statusForUser(userId);
  },
);
```

### Status Values

```dart
enum DatumSyncStatus {
  idle,       // No sync currently running
  syncing,    // Sync is actively running
  paused,     // Sync was paused by the user
  cancelled,  // Sync was cancelled by the user
  failed,     // Sync failed with errors
  completed,  // Sync completed successfully
}
```

### UI Integration

```dart
import 'package:flutter/material.dart';

ref.watch(syncStatusProvider(userId)).easyWhen(
  data: (status) {
    if (status?.status == DatumSyncStatus.syncing) {
      return CircularProgressIndicator(
        value: status!.progress > 0 ? status.progress : null,
      );
    }
    return IconButton(icon: Icon(Icons.sync), onPressed: _sync);
  },
  loadingWidget: () => CircularProgressIndicator(),
);
```

## Common Patterns

### 1. Loading State Management

```dart
import 'package:flutter/material.dart';

class _MyWidgetState extends State<MyWidget> {
  bool _isLoading = false;

  void _startSync() async {
    setState(() => _isLoading = true);
    try {
      await Datum.instance.synchronize(userId);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
```

### 2. Error Handling

```dart
try {
  final result = await Datum.instance.synchronize(userId);
  if (result.isSuccess) {
    print('Sync completed: ${result.syncedCount} items');
  } else {
    print('Sync failed: ${result.failedCount} errors');
  }
} catch (e) {
  print('Sync error: $e');
}
```

### 3. Background Sync

```dart
// In DatumConfig
final config = DatumConfig(
  autoStartSync: true,
  autoSyncInterval: Duration(minutes: 15),
);
```

### 4. Manual Sync with Options

```dart
// Pull only
await Datum.instance.synchronize(
  userId,
  options: const DatumSyncOptions(direction: SyncDirection.pullOnly),
);

// Push only
await Datum.instance.synchronize(
  userId,
  options: const DatumSyncOptions(direction: SyncDirection.pushOnly),
);

// Custom batch size
await Datum.instance.synchronize(
  userId,
  options: const DatumSyncOptions(overrideBatchSize: 50),
);
```

## Best Practices

### ✅ Do's

- **Monitor sync status** for better UX
- **Handle errors gracefully** - don't crash on sync failures
- **Clear metadata** when you need guaranteed fresh data
- **Use appropriate directions** (pullThenPush for login scenarios)
- **Show loading states** during sync operations

### ❌ Don'ts

- **Don't block UI** indefinitely on sync failures
- **Don't ignore sync status** - keep users informed
- **Don't overuse forceFullSync** - it's expensive
- **Don't forget to resume sync** after pausing
- **Don't access AsyncValue directly** - use `.value` property

### 🔧 Debugging Tips

- **Check logs** for sync operations and metadata
- **Monitor sync status** in dev tools
- **Test relogin scenarios** thoroughly
- **Verify metadata clearing** is working
- **Use forceFullSync** temporarily for debugging

## Related Topics

- [Initialization Guide](initialization) - Setting up Datum
- [Entity Definition](entity_define) - Creating data models
- [Querying Guide](querying) - Working with data
- [Remote Adapters](remote_adapter_implement) - Server communication
