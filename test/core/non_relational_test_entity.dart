import 'package:datum/datum.dart';

/// A simple entity that does NOT extend RelationalDatumEntity.
/// Used to test behavior for non-relational parents.
class NonRelationalTestEntity extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String name;

  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const NonRelationalTestEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  factory NonRelationalTestEntity.create(String id, String userId, String name) => NonRelationalTestEntity(
        id: id,
        userId: userId,
        name: name,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
      );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'name': name};

  @override
  DatumEntity copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;
}
