import 'package:datum/source/core/models/datum_entity.dart';

/// Defines the strategy to use when switching between users.
enum UserSwitchStrategy {
  /// Before switching to the new user, fully synchronize any pending
  /// local changes for the old user. This is the safest default.
  syncThenSwitch,

  /// When switching to the new user, clear all of their existing local data
  /// and then perform a full sync to fetch fresh data from the remote.
  /// Useful for ensuring a clean state.
  clearAndFetch,

  /// If the old user has any unsynced local changes, the switch operation
  /// will fail and return an error. This forces the user or application
  /// to resolve pending data before proceeding.
  promptIfUnsyncedData,

  /// Switch to the new user without modifying any local data for either
  /// the old or new user. Local data is kept as-is.
  keepLocal,
}

/// Result of a user switching operation.
class DatumUserSwitchResult {
  /// Whether the switch was successful.
  final bool success;

  /// Previous user ID.
  final String? previousUserId;

  /// New user ID.
  final String newUserId;

  /// Number of unsynced operations handled during switch.
  final int unsyncedOperationsHandled;

  /// Conflicts encountered during the switch.
  final List<DatumEntity>? conflicts;

  /// Error message if the switch failed.
  final String? errorMessage;

  /// Creates a user switch result.
  const DatumUserSwitchResult({
    required this.success,
    required this.newUserId,
    this.previousUserId,
    this.unsyncedOperationsHandled = 0,
    this.conflicts,
    this.errorMessage,
  });

  /// Creates a successful user switch result.
  factory DatumUserSwitchResult.success({
    required String newUserId,
    String? previousUserId,
    int unsyncedOperationsHandled = 0,
    List<DatumEntity>? conflicts,
  }) {
    return DatumUserSwitchResult(
      success: true,
      previousUserId: previousUserId,
      newUserId: newUserId,
      unsyncedOperationsHandled: unsyncedOperationsHandled,
      conflicts: conflicts,
    );
  }

  /// Creates a failed user switch result.
  factory DatumUserSwitchResult.failure({
    required String newUserId,
    required String errorMessage,
    String? previousUserId,
  }) {
    return DatumUserSwitchResult(
      success: false,
      previousUserId: previousUserId,
      newUserId: newUserId,
      errorMessage: errorMessage,
    );
  }

  /// Aggregates multiple user switch results into a single summary.
  factory DatumUserSwitchResult.aggregate(
    List<DatumUserSwitchResult> results, {
    required String? previousUserId,
    required String newUserId,
  }) {
    if (results.isEmpty) {
      return DatumUserSwitchResult.success(
        previousUserId: previousUserId,
        newUserId: newUserId,
      );
    }

    final overallSuccess = results.every((r) => r.success);
    final totalUnsyncedHandled = results.map((r) => r.unsyncedOperationsHandled).fold(0, (a, b) => a + b);
    final combinedErrors = results.where((r) => !r.success).map((r) => r.errorMessage).join('; ');

    return DatumUserSwitchResult(
      success: overallSuccess,
      previousUserId: previousUserId,
      newUserId: newUserId,
      unsyncedOperationsHandled: totalUnsyncedHandled,
      errorMessage: combinedErrors.isNotEmpty ? combinedErrors : null,
    );
  }
}
