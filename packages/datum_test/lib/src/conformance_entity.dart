import 'package:datum/datum.dart';

/// The standard entity every conformance suite runs against.
///
/// Wire the adapter under test for this type (e.g.
/// `HiveLocalAdapter<ConformanceEntity>(fromMap: ConformanceEntity.fromMap)`)
/// and hand its factory to `runLocalAdapterConformanceTests`. The shape is
/// deliberately flat (strings, ints, bools, ISO-8601 timestamps) so both
/// schemaless and SQL adapters can store it.
class ConformanceEntity extends DatumEntity {
  const ConformanceEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.value,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    this.isDeleted = false,
  });

  factory ConformanceEntity.fromMap(
    Map<String, dynamic> map,
  ) => ConformanceEntity(
    id: map['id'] as String? ?? '',
    userId: map['userId'] as String? ?? '',
    name: map['name'] as String? ?? '',
    value: (map['value'] as num?)?.toInt() ?? 0,
    modifiedAt:
        DateTime.tryParse(map['modifiedAt'] as String? ?? '') ?? DateTime(2000),
    createdAt:
        DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime(2000),
    version: (map['version'] as num?)?.toInt() ?? 1,
    isDeleted: map['isDeleted'] as bool? ?? false,
  );

  /// A fresh entity with sensible defaults.
  factory ConformanceEntity.make(
    String id, {
    String userId = 'conformance-user',
    String name = 'entity',
    int value = 0,
    int version = 1,
    bool isDeleted = false,
    DateTime? modifiedAt,
  }) => ConformanceEntity(
    id: id,
    userId: userId,
    name: name,
    value: value,
    modifiedAt: modifiedAt ?? DateTime.now(),
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    version: version,
    isDeleted: isDeleted,
  );

  @override
  final String id;
  @override
  final String userId;

  /// Free-text payload used by query/sort assertions.
  final String name;

  /// Numeric payload used by filter/aggregation assertions.
  final int value;

  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
    'id': id,
    'userId': userId,
    'name': name,
    'value': value,
    'modifiedAt': modifiedAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'version': version,
    'isDeleted': isDeleted,
  };

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    if (oldVersion is! ConformanceEntity) {
      return toDatumMap(target: MapTarget.remote);
    }
    final delta = <String, dynamic>{};
    if (name != oldVersion.name) delta['name'] = name;
    if (value != oldVersion.value) delta['value'] = value;
    if (isDeleted != oldVersion.isDeleted) delta['isDeleted'] = isDeleted;
    if (delta.isEmpty) return null;
    delta['modifiedAt'] = modifiedAt.toIso8601String();
    delta['version'] = version;
    return delta;
  }

  /// Returns a copy with updated payload fields and a bumped version.
  ConformanceEntity copyWith({
    String? name,
    int? value,
    bool? isDeleted,
    DateTime? modifiedAt,
  }) => ConformanceEntity(
    id: id,
    userId: userId,
    name: name ?? this.name,
    value: value ?? this.value,
    modifiedAt: modifiedAt ?? DateTime.now(),
    createdAt: createdAt,
    version: version + 1,
    isDeleted: isDeleted ?? this.isDeleted,
  );

  @override
  List<Object?> get props => [...super.props, name, value];
}
