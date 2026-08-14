import 'dart:async';

import 'package:datum/source/core/models/cold_start_strategy.dart';
import 'package:datum/source/core/models/datum_sync_options.dart';
import 'package:datum/source/core/models/datum_sync_result.dart';
import 'package:datum/source/utils/datum_logger.dart';

/// Interface for cold start state persistence
abstract class ColdStartPersistence {
  Future<void> saveState(String userId, Map<String, dynamic> state);
  Future<Map<String, dynamic>?> loadState(String userId);
  Future<void> clearState(String userId);
}

/// In-memory implementation for cold start persistence
class InMemoryColdStartPersistence implements ColdStartPersistence {
  final Map<String, Map<String, dynamic>> _storage = {};

  @override
  Future<void> saveState(String userId, Map<String, dynamic> state) async {
    _storage[userId] = Map.from(state);
  }

  @override
  Future<Map<String, dynamic>?> loadState(String userId) async {
    return _storage[userId];
  }

  @override
  Future<void> clearState(String userId) async {
    _storage.remove(userId);
  }
}

/// Manages cold start synchronization behavior.
/// Handles detection of cold starts and orchestrates appropriate sync strategies.
class ColdStartManager {
  // Per-user state instead of global static state
  final Map<String, bool> _isColdStart = {};
  final Map<String, DateTime?> _lastColdStartTime = {};
  final Map<String, bool> _isColdStartInProgress = {}; // Track ongoing cold start syncs
  final ColdStartConfig _config;
  final DatumLogger _logger;

  // Retry configuration
  final int _maxRetries;
  final Duration _initialRetryDelay;
  final double _retryBackoffMultiplier;

  ColdStartManager(
    this._config, {
    DatumLogger? logger,
    ColdStartPersistence? persistence,
    int maxRetries = 3,
    Duration initialRetryDelay = const Duration(seconds: 5),
    double retryBackoffMultiplier = 2.0,
  })  : _logger = logger ?? DatumLogger(),
        _maxRetries = maxRetries,
        _initialRetryDelay = initialRetryDelay,
        _retryBackoffMultiplier = retryBackoffMultiplier;

  /// Checks if this is a cold start and performs appropriate sync if needed.
  /// Now runs sync in background to prevent blocking app initialization.
  Future<bool> handleColdStartIfNeeded(
    String? userId,
    Future<DatumSyncResult> Function(DatumSyncOptions) syncFunction, {
    String? entityType,
    bool synchronous = false,
  }) async {
    final entityInfo = entityType != null ? ' for $entityType' : '';

    // Guard against null userId - skip cold start sync if user is not authenticated
    if (userId == null || userId.isEmpty) {
      _logger.debug('Skipping cold start sync: user not authenticated$entityInfo');
      return false;
    }

    _logger.debug('Checking for cold start sync for user: $userId$entityInfo');

    // Initialize user state if not exists
    _isColdStart.putIfAbsent(userId, () => true);

    final isColdStart = _isColdStart[userId] ?? true;

    if (!isColdStart || _config.strategy == ColdStartStrategy.disabled) {
      if (_config.strategy == ColdStartStrategy.disabled) {
        _logger.debug('Cold start sync disabled by configuration$entityInfo');
      } else if (!isColdStart) {
        _logger.debug('Not a cold start, skipping cold start sync$entityInfo');
      }
      return false;
    }

    // Check if a cold start sync is already in progress for this user.
    if (_isColdStartInProgress[userId] == true) {
      _logger.debug('Cold start sync already in progress for user: $userId$entityInfo');
      return false;
    }

    // Claim the in-progress slot BEFORE the awaited strategy evaluation.
    // Previously the flag was set only after `await _shouldPerformColdStartSync`,
    // so two callers racing through that suspension point both passed the guard
    // and launched two concurrent cold-start syncs for the same user (TOCTOU).
    _isColdStartInProgress[userId] = true;

    final bool shouldSync;
    try {
      shouldSync = await _shouldPerformColdStartSync(userId);
    } catch (_) {
      _isColdStartInProgress[userId] = false;
      rethrow;
    }
    if (!shouldSync) {
      _isColdStartInProgress[userId] = false;
      _logger.debug('Cold start sync not needed based on strategy evaluation$entityInfo');
      _isColdStart[userId] = false;
      return false;
    }

    if (synchronous) {
      // For testing: execute synchronously
      _logger.info('🚀 Starting synchronous cold start sync for user: $userId using strategy: ${_config.strategy}$entityInfo');
      try {
        await _performColdStartSync(userId, syncFunction, entityType: entityType);
        _isColdStart[userId] = false;
        _lastColdStartTime[userId] = DateTime.now();
        _logger.info('✅ Synchronous cold start sync completed successfully for user: $userId$entityInfo');
      } catch (e, stack) {
        _logger.error('❌ Synchronous cold start sync failed for user: $userId$entityInfo', stack);
        // On cold start sync failure, don't mark as completed
        // Allow retry on next app launch
        rethrow;
      } finally {
        // Always clear the in-progress flag when done
        _isColdStartInProgress[userId] = false;
      }
    } else {
      // Start cold start sync in background to prevent blocking app initialization
      // Use Future.delayed with zero duration to make it work with fakeAsync in tests
      _logger.info('🚀 Starting background cold start sync for user: $userId using strategy: ${_config.strategy}$entityInfo');
      unawaited(Future.delayed(Duration.zero, () async {
        try {
          await _performColdStartSync(userId, syncFunction, entityType: entityType);
          _isColdStart[userId] = false;
          _lastColdStartTime[userId] = DateTime.now();
          _logger.info('✅ Background cold start sync completed successfully for user: $userId$entityInfo');
        } catch (e, stack) {
          _logger.error('❌ Background cold start sync failed for user: $userId$entityInfo', stack);
          // On cold start sync failure, don't mark as completed
          // Allow retry on next app launch
        } finally {
          // Always clear the in-progress flag when done
          _isColdStartInProgress[userId] = false;
        }
      }));
    }

    // Return immediately without waiting for sync to complete (for async mode)
    // or after sync completion (for sync mode)
    return true;
  }

  /// Determines if cold start sync should be performed based on strategy and conditions.
  Future<bool> _shouldPerformColdStartSync(String userId) async {
    switch (_config.strategy) {
      case ColdStartStrategy.disabled:
        return false;

      case ColdStartStrategy.fullSync:
        return true;

      case ColdStartStrategy.adaptive:
        return await _evaluateAdaptiveStrategy(userId);

      case ColdStartStrategy.incremental:
        return await _shouldPerformIncrementalSync(userId);

      case ColdStartStrategy.priorityBased:
        return true; // Always attempt priority-based sync
    }
  }

  /// Evaluates adaptive strategy based on time since last sync and other factors.
  Future<bool> _evaluateAdaptiveStrategy(String userId) async {
    _logger.debug('Evaluating adaptive cold start strategy for user: $userId');

    // Check time since last sync
    final lastTime = _lastColdStartTime[userId];
    if (lastTime != null) {
      final timeSinceLastColdStart = DateTime.now().difference(lastTime);
      _logger.debug('Time since last cold start: $timeSinceLastColdStart, threshold: ${_config.syncThreshold}');

      if (timeSinceLastColdStart < _config.syncThreshold) {
        _logger.debug('Skipping cold start sync - too soon since last cold start');
        return false; // Too soon for another cold start sync
      }
    } else {
      _logger.debug('No previous cold start recorded, allowing sync');
    }

    // Could add more adaptive logic here:
    // - Check battery level
    // - Check network conditions
    // - Check if there are pending local changes
    // - Check app usage patterns

    _logger.debug('Adaptive strategy evaluation: allowing cold start sync');
    return true;
  }

  /// Determines if incremental sync should be performed.
  Future<bool> _shouldPerformIncrementalSync(String userId) async {
    _logger.debug('Evaluating incremental cold start strategy for user: $userId');
    // Incremental sync logic would go here
    // Check if remote has changes since last local sync
    _logger.debug('Incremental strategy: allowing cold start sync');
    return true; // For now, always attempt
  }

  /// Performs the appropriate cold start sync based on strategy.
  Future<void> _performColdStartSync(
    String userId,
    Future<DatumSyncResult> Function(DatumSyncOptions) syncFunction, {
    String? entityType,
  }) async {
    final entityInfo = entityType != null ? ' for $entityType' : '';
    _logger.info('🔄 [Cold Start] Starting sync execution for user: $userId$entityInfo');
    _logger.debug('Cold start config: strategy=${_config.strategy}, threshold=${_config.syncThreshold}, maxDuration=${_config.maxDuration}, initialDelay=${_config.initialDelay}');

    // Add initial delay to allow UI to load
    if (_config.initialDelay > Duration.zero) {
      _logger.info('⏳ [Cold Start] Applying initial delay of ${_config.initialDelay} before sync');
      await Future.delayed(_config.initialDelay);
      _logger.debug('✅ [Cold Start] Initial delay completed');
    }

    final forceFullSync = _shouldForceFullSync();
    final options = DatumSyncOptions(
      forceFullSync: forceFullSync,
      timeout: _config.maxDuration,
    );

    _logger.info('🚀 [Cold Start] Executing sync with forceFullSync: $forceFullSync, timeout: ${_config.maxDuration}');
    _logger.debug('Sync options created: $options');

    try {
      // Implement retry logic with exponential backoff
      _logger.debug('🔄 [Cold Start] Calling sync function with retry logic');
      final result = await _executeWithRetry(
        () => syncFunction(options),
        userId: userId,
        operationName: 'cold start sync',
        entityType: entityType,
      );
      _logger.info('✅ [Cold Start] Sync execution completed successfully: $result');
    } catch (e, stack) {
      _logger.error('❌ [Cold Start] Sync execution failed: $e', stack);
      rethrow;
    }

    _logger.debug('🏁 [Cold Start] Sync execution completed');
  }

  /// Executes an operation with retry logic and exponential backoff.
  Future<T> _executeWithRetry<T>(
    Future<T> Function() operation, {
    required String userId,
    required String operationName,
    String? entityType,
  }) async {
    final entityInfo = entityType != null ? ' for $entityType' : '';
    int attempt = 0;
    Duration currentDelay = _initialRetryDelay;

    while (attempt <= _maxRetries) {
      try {
        if (attempt > 0) {
          _logger.info('🔄 [Cold Start] Retrying $operationName for user $userId$entityInfo (attempt ${attempt + 1}/${_maxRetries + 1}) after ${currentDelay.inSeconds}s delay');
          await Future.delayed(currentDelay);
          currentDelay = Duration(milliseconds: (currentDelay.inMilliseconds * _retryBackoffMultiplier).round());
        }

        _logger.debug('🔄 [Cold Start] Executing $operationName for user $userId$entityInfo (attempt ${attempt + 1})');
        final result = await operation();
        _logger.debug('✅ [Cold Start] $operationName succeeded for user $userId$entityInfo');
        return result;
      } catch (e, stack) {
        attempt++;

        if (attempt > _maxRetries) {
          _logger.error('❌ [Cold Start] $operationName failed after ${_maxRetries + 1} attempts for user $userId$entityInfo', stack);
          rethrow;
        }

        _logger.warn('⚠️ [Cold Start] $operationName failed on attempt $attempt for user $userId$entityInfo: $e');

        // Don't retry certain types of errors
        if (e is ArgumentError || e is StateError || e is UnsupportedError) {
          _logger.warn('🚫 [Cold Start] Not retrying $operationName for user $userId$entityInfo due to non-retryable error: $e');
          rethrow;
        }
      }
    }

    // This should never be reached, but just in case
    throw StateError('Unexpected retry logic error');
  }

  /// Determines if full sync should be forced based on strategy.
  bool _shouldForceFullSync() => switch (_config.strategy) {
        // `disabled` never reaches this switch (handleColdStartIfNeeded
        // returns early), but exhaustiveness requires it; it shares the arm.
        ColdStartStrategy.fullSync || ColdStartStrategy.adaptive => true,
        ColdStartStrategy.incremental || ColdStartStrategy.priorityBased || ColdStartStrategy.disabled => false,
      };

  /// Resets cold start state for a specific user (useful for testing).
  void resetForUser(String userId) {
    _isColdStart[userId] = true;
    _lastColdStartTime[userId] = null;
    _isColdStartInProgress[userId] = false;
  }

  /// Resets cold start state for all users (useful for testing).
  void resetAll() {
    _isColdStart.clear();
    _lastColdStartTime.clear();
    _isColdStartInProgress.clear();
  }

  /// Sets the last cold start time for a specific user (useful for testing).
  void setLastColdStartTimeForUser(String userId, DateTime? time) {
    _lastColdStartTime[userId] = time;
  }

  /// Gets current cold start status for a specific user.
  bool isColdStartForUser(String userId) {
    return _isColdStart[userId] ?? true;
  }

  /// Gets the last cold start time for a specific user.
  DateTime? getLastColdStartTimeForUser(String userId) {
    return _lastColdStartTime[userId];
  }

  /// Gets all users with cold start state.
  Set<String> getActiveUsers() {
    return _isColdStart.keys.toSet();
  }

  ColdStartConfig get config => _config;
}
