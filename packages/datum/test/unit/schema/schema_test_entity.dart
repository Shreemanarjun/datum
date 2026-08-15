import 'package:datum/datum.dart';

enum SchemaPriority { low, high }

class SchemaTask extends DatumEntity {
  const SchemaTask({
    required this.id,
    required this.userId,
    required this.title,
    this.priority = 0,
    this.due,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String title;
  final int priority;
  final DateTime? due;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => schema.toMap(this, target: target);

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) => toDatumMap();

  @override
  List<Object?> get props => [...super.props, title, priority, due];

  static final core = datumCoreFieldSpecs<SchemaTask>();
  static final titleField = DatumFieldSpec<SchemaTask, String>('title', getter: (t) => t.title);
  static final priorityField = DatumFieldSpec<SchemaTask, int>('priority', getter: (t) => t.priority, defaultValue: 0);
  static final dueField = DatumFieldSpec<SchemaTask, DateTime?>('due', getter: (t) => t.due, codec: DatumFieldCodec.dateTimeIso.nullable);

  static final schema = DatumSchema<SchemaTask>(
    name: 'schema_tasks',
    fields: [...core.all, titleField, priorityField, dueField],
    construct: (r) => SchemaTask(
      id: r(core.id),
      userId: r(core.userId),
      title: r(titleField),
      priority: r.getOr(priorityField, 0),
      due: r(dueField),
      createdAt: r(core.createdAt),
      modifiedAt: r(core.modifiedAt),
      version: r(core.version),
      isDeleted: r.getOr(core.isDeleted, false),
    ),
  );
}

SchemaTask makeSchemaTask({String id = 't1', String title = 'task', int priority = 0, DateTime? due}) {
  final now = DateTime.utc(2026, 1, 1);
  return SchemaTask(
    id: id,
    userId: 'u1',
    title: title,
    priority: priority,
    due: due,
    createdAt: now,
    modifiedAt: now,
    version: 1,
  );
}
