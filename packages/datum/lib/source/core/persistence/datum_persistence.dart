import 'dart:async';

import 'package:datum/source/core/models/datum_sync_metadata.dart';

/// Abstract interface for persistent storage of Datum sync metadata and configuration.
///
/// This interface provides a unified way to store and retrieve sync-related data
/// across different storage backends (Hive, SharedPreferences, SQLite, etc.).
/// It supports both synchronous and asynchronous operations, as well as streaming
/// for real-time updates.
///
/// ## Usage
///
/// By default, Datum uses an in-memory persistence layer. To use persistent storage,
/// implement this interface and pass it to [Datum.initialize]:
///
/// ```dart
/// // Custom implementation (e.g., Hive, SharedPreferences, SQLite)
/// class MyPersistence implements DatumPersistence {
///   // Implement all required methods...
/// }
///
/// await Datum.initialize(
///   config: DatumConfig(...),
///   connectivityChecker: MyConnectivityChecker(),
///   persistence: MyPersistence(), // Use custom persistence
///   registrations: [...],
/// );
/// ```
///
/// ## Built-in Implementations
///
/// - **InMemoryDatumPersistence**: Default in-memory storage (data lost on restart)
/// - **HiveDatumPersistence**: Hive-based persistent storage (in example app)
///
/// Implementations should handle serialization/deserialization of complex objects
/// and provide thread-safe operations where necessary.
abstract class DatumPersistence {
  /// Initializes the persistence layer.
  ///
  /// This method should set up any necessary storage connections, create tables/collections,
  /// and perform any required migrations. It should be called once during app initialization.
  Future<void> initialize();

  /// Closes the persistence layer and releases any resources.
  Future<void> dispose();

  /// Stores sync metadata for a specific user.
  ///
  /// The metadata contains global sync information including timestamps, entity counts,
  /// device information, and conflict tracking.
  Future<void> saveSyncMetadata(String userId, DatumSyncMetadata metadata);

  /// Retrieves sync metadata for a specific user.
  ///
  /// Returns null if no metadata exists for the user.
  Future<DatumSyncMetadata?> getSyncMetadata(String userId);

  /// Deletes sync metadata for a specific user.
  Future<void> deleteSyncMetadata(String userId);

  /// Returns a stream of sync metadata changes for a specific user.
  ///
  /// The stream should emit the current metadata immediately upon subscription,
  /// and then emit updates whenever the metadata changes.
  Stream<DatumSyncMetadata?> watchSyncMetadata(String userId);

  /// Stores configuration data.
  ///
  /// Configuration can include app settings, user preferences, and other
  /// persistent state that needs to survive app restarts.
  Future<void> saveConfig(String key, dynamic value);

  /// Retrieves configuration data.
  Future<dynamic> getConfig(String key);

  /// Deletes configuration data.
  Future<void> deleteConfig(String key);

  /// Returns a stream of configuration changes for a specific key.
  Stream<dynamic> watchConfig(String key);

  /// Stores arbitrary data with a key.
  ///
  /// This can be used for caching, temporary state, or any other data
  /// that needs to be persisted.
  Future<void> saveData(String key, dynamic value);

  /// Retrieves arbitrary data by key.
  Future<dynamic> getData(String key);

  /// Deletes arbitrary data by key.
  Future<void> deleteData(String key);

  /// Returns a stream of data changes for a specific key.
  Stream<dynamic> watchData(String key);

  /// Clears all data for a specific user.
  ///
  /// This is typically called when a user logs out or switches accounts.
  Future<void> clearUserData(String userId);

  /// Clears all stored data.
  ///
  /// Use with caution - this will delete all persisted data.
  Future<void> clearAllData();

  /// Gets all user IDs that have stored data.
  Future<Set<String>> getAllUserIds();

  /// Checks if the persistence layer is ready for operations.
  bool get isInitialized;

  /// Gets storage statistics (optional implementation).
  Future<Map<String, dynamic>?> getStorageStats();
}
