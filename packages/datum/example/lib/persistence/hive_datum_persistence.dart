import 'dart:async';

import 'package:datum/datum.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// Hive-based implementation of [DatumPersistence] for the example app.
///
/// This implementation uses Hive boxes to store sync metadata, configuration,
/// and other persistent data. It provides streaming capabilities through
/// [ValueListenable] and [StreamController].
///
/// ## Setup
///
/// ```dart
/// // Initialize Hive first
/// await Hive.initFlutter();
///
/// // Create and initialize the persistence layer
/// final persistence = HiveDatumPersistence();
/// await persistence.initialize();
///
/// // Use with Datum
/// await Datum.initialize(
///   config: DatumConfig(...),
///   connectivityChecker: MyConnectivityChecker(),
///   persistence: persistence,
///   registrations: [...],
/// );
/// ```
class HiveDatumPersistence extends DatumPersistence {
  static const String _syncMetadataBoxName = 'datum_sync_metadata';
  static const String _configBoxName = 'datum_config';
  static const String _dataBoxName = 'datum_data';

  IsolatedBox<Map>? _syncMetadataBox;
  IsolatedBox<dynamic>? _configBox;
  IsolatedBox<dynamic>? _dataBox;

  final Map<String, StreamController<DatumSyncMetadata?>> _metadataControllers =
      {};
  final Map<String, StreamController<dynamic>> _configControllers = {};
  final Map<String, StreamController<dynamic>> _dataControllers = {};

  @override
  Future<void> initialize() async {
    _syncMetadataBox = await IsolatedHive.openBox<Map>(_syncMetadataBoxName);
    _configBox = await IsolatedHive.openBox<dynamic>(_configBoxName);
    _dataBox = await IsolatedHive.openBox<dynamic>(_dataBoxName);
  }

  @override
  Future<void> dispose() async {
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

    // Close boxes
    await _syncMetadataBox?.close();
    await _configBox?.close();
    await _dataBox?.close();
  }

  @override
  Future<void> saveSyncMetadata(
      String userId, DatumSyncMetadata metadata) async {
    _checkInitialized();
    final box = _syncMetadataBox!;

    await box.put(userId, metadata.toMap());

    // Notify listeners
    final controller = _metadataControllers[userId];
    if (controller != null && !controller.isClosed) {
      controller.add(metadata);
    }
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    _checkInitialized();
    final box = _syncMetadataBox!;

    final data = await box.get(userId);
    if (data == null) return null;

    try {
      return DatumSyncMetadata.fromMap(data.cast<String, dynamic>());
    } catch (e) {
      // Handle migration or corrupted data
      return null;
    }
  }

  @override
  Future<void> deleteSyncMetadata(String userId) async {
    _checkInitialized();
    final box = _syncMetadataBox!;

    await box.delete(userId);

    // Notify listeners
    final controller = _metadataControllers[userId];
    if (controller != null && !controller.isClosed) {
      controller.add(null);
    }
  }

  @override
  Stream<DatumSyncMetadata?> watchSyncMetadata(String userId) {
    final controller = _metadataControllers[userId] ??=
        StreamController<DatumSyncMetadata?>.broadcast();

    // Emit current value immediately
    getSyncMetadata(userId).then((metadata) {
      if (!controller.isClosed) {
        controller.add(metadata);
      }
    });

    // Listen to box changes
    if (_syncMetadataBox != null) {
      _syncMetadataBox!.watch(key: userId).listen((event) {
        if (!controller.isClosed) {
          if (event.value == null) {
            controller.add(null);
          } else {
            try {
              final metadata = DatumSyncMetadata.fromMap(
                  event.value.cast<String, dynamic>());
              controller.add(metadata);
            } catch (e) {
              controller.add(null);
            }
          }
        }
      });
    }

    return controller.stream;
  }

  @override
  Future<void> saveConfig(String key, dynamic value) async {
    _checkInitialized();
    final box = _configBox!;

    await box.put(key, value);

    // Notify listeners
    final controller = _configControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(value);
    }
  }

  @override
  Future<dynamic> getConfig(String key) async {
    _checkInitialized();
    final box = _configBox!;

    return box.get(key);
  }

  @override
  Future<void> deleteConfig(String key) async {
    _checkInitialized();
    final box = _configBox!;

    await box.delete(key);

    // Notify listeners
    final controller = _configControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(null);
    }
  }

  @override
  Stream<dynamic> watchConfig(String key) {
    final controller =
        _configControllers[key] ??= StreamController<dynamic>.broadcast();

    // Emit current value immediately
    getConfig(key).then((value) {
      if (!controller.isClosed) {
        controller.add(value);
      }
    });

    // Listen to box changes
    if (_configBox != null) {
      _configBox!.watch(key: key).listen((event) {
        if (!controller.isClosed) {
          controller.add(event.value);
        }
      });
    }

    return controller.stream;
  }

  @override
  Future<void> saveData(String key, dynamic value) async {
    _checkInitialized();
    final box = _dataBox!;

    await box.put(key, value);

    // Notify listeners
    final controller = _dataControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(value);
    }
  }

  @override
  Future<dynamic> getData(String key) async {
    _checkInitialized();
    final box = _dataBox!;

    return box.get(key);
  }

  @override
  Future<void> deleteData(String key) async {
    _checkInitialized();
    final box = _dataBox!;

    await box.delete(key);

    // Notify listeners
    final controller = _dataControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(null);
    }
  }

  @override
  Stream<dynamic> watchData(String key) {
    final controller =
        _dataControllers[key] ??= StreamController<dynamic>.broadcast();

    // Emit current value immediately
    getData(key).then((value) {
      if (!controller.isClosed) {
        controller.add(value);
      }
    });

    // Listen to box changes
    if (_dataBox != null) {
      _dataBox!.watch(key: key).listen((event) {
        if (!controller.isClosed) {
          controller.add(event.value);
        }
      });
    }

    return controller.stream;
  }

  @override
  Future<void> clearUserData(String userId) async {
    _checkInitialized();

    // Delete sync metadata for this user
    await _syncMetadataBox!.delete(userId);

    // Notify listeners
    final metadataController = _metadataControllers[userId];
    if (metadataController != null && !metadataController.isClosed) {
      metadataController.add(null);
    }

    // Also clear any user-specific config/data keys
    final configKeys = await _configBox!.keys;
    final dataKeys = await _dataBox!.keys;

    final configKeysToDelete =
        configKeys.where((key) => key.toString().contains(userId));
    final dataKeysToDelete =
        dataKeys.where((key) => key.toString().contains(userId));

    await Future.wait([
      ...configKeysToDelete.map((key) => deleteConfig(key.toString())),
      ...dataKeysToDelete.map((key) => deleteData(key.toString())),
    ]);
  }

  @override
  Future<void> clearAllData() async {
    _checkInitialized();

    await Future.wait([
      _syncMetadataBox!.clear(),
      _configBox!.clear(),
      _dataBox!.clear(),
    ]);

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
    final keys = await _syncMetadataBox!.keys;
    return keys.cast<String>().toSet();
  }

  @override
  bool get isInitialized => _configBox != null;

  @override
  Future<Map<String, dynamic>?> getStorageStats() async {
    if (!isInitialized) return null;

    final userIds = await getAllUserIds();
    final syncKeys = await _syncMetadataBox!.keys;
    final configKeys = await _configBox!.keys;
    final dataKeys = await _dataBox!.keys;
    final totalEntries = syncKeys.length + configKeys.length + dataKeys.length;

    // Estimate storage size (rough approximation)
    final storageSizeBytes = totalEntries * 100; // Rough estimate

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
