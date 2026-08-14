import 'package:datum/datum.dart';

class TestDatumEntity extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String value;

  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  TestDatumEntity({
    required this.id,
    required this.userId,
    required this.value,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    VectorClock? vectorClock,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now(),
        version = version ?? 1,
        isDeleted = isDeleted ?? false,
        _vectorClock = vectorClock;

  final VectorClock? _vectorClock;

  @override
  VectorClock? get vectorClock => _vectorClock;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return {
      'id': id,
      'userId': userId,
      'value': value,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'version': version,
      'isDeleted': isDeleted,
      'vectorClock': vectorClock?.toMap(),
    };
  }

  factory TestDatumEntity.fromMap(Map<String, dynamic> map) {
    return TestDatumEntity(
      id: map['id'] as String,
      userId: map['userId'] as String,
      value: map['value'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      modifiedAt: DateTime.parse(map['modifiedAt'] as String),
      version: map['version'] as int,
      isDeleted: map['isDeleted'] as bool,
      vectorClock: map['vectorClock'] != null ? VectorClock.fromMap(Map<String, int>.from(map['vectorClock'])) : null,
    );
  }

  TestDatumEntity copyWith({
    String? id,
    String? userId,
    String? value,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    VectorClock? vectorClock,
  }) {
    return TestDatumEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
      vectorClock: vectorClock ?? this.vectorClock,
    );
  }

  @override
  DatumEntityInterface incrementClock(String replicaId) {
    final currentClock = vectorClock ?? const VectorClock();
    return copyWith(vectorClock: currentClock.increment(replicaId));
  }

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    if (oldVersion is! TestDatumEntity) return null;
    final changes = <String, dynamic>{};
    if (value != oldVersion.value) {
      changes['value'] = value;
    }
    if (isDeleted != oldVersion.isDeleted) {
      changes['isDeleted'] = isDeleted;
    }
    return changes.isEmpty ? null : changes;
  }

  @override
  List<Object?> get props => [id, userId, value, createdAt, modifiedAt, version, isDeleted, vectorClock];
}
