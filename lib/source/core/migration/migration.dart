/// Represents a single migration step from one schema version to another.
///
/// You will create concrete implementations of this class for each schema
/// change in your application.
abstract class Migration {
  /// The schema version this migration starts from.
  int get fromVersion;

  /// The schema version this migration migrates to.
  int get toVersion;

  /// Executes the migration logic on a single raw data object.
  /// The map represents a single entity serialized to a map.
  Map<String, dynamic> migrate(Map<String, dynamic> oldData);
}
