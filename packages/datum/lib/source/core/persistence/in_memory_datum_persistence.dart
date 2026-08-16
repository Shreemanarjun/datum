import 'dart:async';

import 'package:datum/datum.dart';

/// In-memory implementation of [DatumPersistence] for testing and development.
///
/// This implementation stores all data in memory and provides streaming capabilities
/// through [StreamController]. It's useful for testing, development, and as a
/// reference implementation.
///
/// **Note:** All data is lost when the application restarts. For production use,
/// implement a persistent storage backend like Hive, SharedPreferences, or SQLite.
///
/// ## Usage
///
/// ```dart
/// final persistence = InMemoryDatumPersistence();
/// await persistence.initialize();
///
/// await Datum.initialize(
///   config: DatumConfig(...),
///   connectivityChecker: MyConnectivityChecker(),
///   persistence: persistence, // Inject the persistence layer
///   registrations: [...],
/// );
/// ```
class InMemoryDatumPersistence implements DatumPersistence {
  final Map<String, DatumSyncMetadata> _syncMetadata = {};
  final Map<String, dynamic> _config = {};
  final Map<String, dynamic> _data = {};

  final Map<String, StreamController<DatumSyncMetadata?>> _metadataControllers = {};
  final Map<String, StreamController<dynamic>> _configControllers = {};
  final Map<String, StreamController<dynamic>> _dataControllers = {};

  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;

    // Close all stream controllers
    for (final controller in _metadataControllers.values) {
      await controller.close();
    }
    for (final controller in _configControllers.values) {
      await controller.close();
    }
    for (final controller in _dataControllers.values) {
      await controller.close();
    }

    // Clear all data
    _syncMetadata.clear();
    _config.clear();
    _data.clear();
  }

  @override
  Future<void> saveSyncMetadata(String userId, DatumSyncMetadata metadata) async {
    _checkInitialized();
    _syncMetadata[userId] = metadata;

    // Notify listeners
    final controller = _metadataControllers[userId];
    if (controller != null && !controller.isClosed) {
      controller.add(metadata);
    }
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    _checkInitialized();
    return _syncMetadata[userId];
  }

  @override
  Future<void> deleteSyncMetadata(String userId) async {
    _checkInitialized();
    _syncMetadata.remove(userId);

    // Notify listeners
    final controller = _metadataControllers[userId];
    if (controller != null && !controller.isClosed) {
      controller.add(null);
    }
  }

  @override
  Stream<DatumSyncMetadata?> watchSyncMetadata(String userId) {
    final controller = _metadataControllers[userId] ??= StreamController<DatumSyncMetadata?>.broadcast();

    // Emit current value immediately
    getSyncMetadata(userId).then((metadata) {
      if (!controller.isClosed) {
        controller.add(metadata);
      }
    });

    return controller.stream;
  }

  @override
  Future<void> saveConfig(String key, dynamic value) async {
    _checkInitialized();
    _config[key] = value;

    // Notify listeners
    final controller = _configControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(value);
    }
  }

  @override
  Future<dynamic> getConfig(String key) async {
    _checkInitialized();
    return _config[key];
  }

  @override
  Future<void> deleteConfig(String key) async {
    _checkInitialized();
    _config.remove(key);

    // Notify listeners
    final controller = _configControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(null);
    }
  }

  @override
  Stream<dynamic> watchConfig(String key) {
    final controller = _configControllers[key] ??= StreamController<dynamic>.broadcast();

    // Emit current value immediately
    getConfig(key).then((value) {
      if (!controller.isClosed) {
        controller.add(value);
      }
    });

    return controller.stream;
  }

  @override
  Future<void> saveData(String key, dynamic value) async {
    _checkInitialized();
    _data[key] = value;

    // Notify listeners
    final controller = _dataControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(value);
    }
  }

  @override
  Future<dynamic> getData(String key) async {
    _checkInitialized();
    return _data[key];
  }

  @override
  Future<void> deleteData(String key) async {
    _checkInitialized();
    _data.remove(key);

    // Notify listeners
    final controller = _dataControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(null);
    }
  }

  @override
  Stream<dynamic> watchData(String key) {
    final controller = _dataControllers[key] ??= StreamController<dynamic>.broadcast();

    // Emit current value immediately
    getData(key).then((value) {
      if (!controller.isClosed) {
        controller.add(value);
      }
    });

    return controller.stream;
  }

  @override
  Future<void> clearUserData(String userId) async {
    _checkInitialized();

    // Remove sync metadata for this user
    _syncMetadata.remove(userId);

    // Notify listeners
    final metadataController = _metadataControllers[userId];
    if (metadataController != null && !metadataController.isClosed) {
      metadataController.add(null);
    }

    // Remove user-specific config and data
    final configKeysToRemove = _config.keys.where((key) => key.contains(userId)).toList();
    final dataKeysToRemove = _data.keys.where((key) => key.contains(userId)).toList();

    for (final key in configKeysToRemove) {
      _config.remove(key);
      final controller = _configControllers[key];
      if (controller != null && !controller.isClosed) {
        controller.add(null);
      }
    }

    for (final key in dataKeysToRemove) {
      _data.remove(key);
      final controller = _dataControllers[key];
      if (controller != null && !controller.isClosed) {
        controller.add(null);
      }
    }
  }

  @override
  Future<void> clearAllData() async {
    _checkInitialized();

    _syncMetadata.clear();
    _config.clear();
    _data.clear();

    // Notify all listeners
    for (final controller in _metadataControllers.values) {
      if (!controller.isClosed) {
        controller.add(null);
      }
    }
    for (final controller in _configControllers.values) {
      if (!controller.isClosed) {
        controller.add(null);
      }
    }
    for (final controller in _dataControllers.values) {
      if (!controller.isClosed) {
        controller.add(null);
      }
    }
  }

  @override
  Future<Set<String>> getAllUserIds() async {
    _checkInitialized();
    return _syncMetadata.keys.toSet();
  }

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<Map<String, dynamic>?> getStorageStats() async {
    if (!isInitialized) return null;

    final userIds = await getAllUserIds();
    final totalEntries = _syncMetadata.length + _config.length + _data.length;

    // Rough estimate of memory usage
    final storageSizeBytes = totalEntries * 50; // Rough estimate

    return {
      'totalUsers': userIds.length,
      'totalEntries': totalEntries,
      'storageSizeBytes': storageSizeBytes,
      'lastModified': DateTime.now().toIso8601String(),
    };
  }

  void _checkInitialized() {
    if (!isInitialized) {
      throw StateError('Persistence not initialized. Call initialize() first.');
    }
  }
}
