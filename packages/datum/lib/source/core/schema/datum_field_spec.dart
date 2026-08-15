/// Runtime field descriptors — the no-codegen alternative to
/// `datum_generator`'s per-field output.
///
/// A [DatumFieldSpec] IS-A [DatumQueryField], so it works everywhere the
/// typed query surface already accepts one (`whereField`, `orderByField`,
/// `equalTo`, …) while additionally carrying the metadata that powers typed
/// map reads, SQLite column derivation, and auto-migration diffing.
library;

import 'package:datum/source/core/errors/datum_exception.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/query/datum_query_builder.dart';
import 'package:datum/source/core/query/datum_query_sql_converter.dart';
import 'package:datum/source/core/schema/datum_field_codec.dart';

/// Reads the value of this field from an entity (for `DatumSchema.toMap`).
typedef DatumFieldGetter<E, V> = V Function(E entity);

/// Which of the six standard sync fields a spec represents, when built by
/// [datumCoreFieldSpecs]. Payload fields have no role.
enum DatumCoreRole { id, userId, modifiedAt, createdAt, version, isDeleted }

/// A full runtime descriptor for one serialized field of entity [E] with
/// Dart value type [V].
///
/// Declared once per field as `static final` (the codec/getter closures rule
/// out `const`), the same declare-once pattern as `MemoizedRelations`:
///
/// ```dart
/// abstract final class TaskFields {
///   static final title = DatumFieldSpec<Task, String>('title', getter: (t) => t.title);
///   static final priority = DatumFieldSpec<Task, int>('priority',
///       getter: (t) => t.priority, defaultValue: 0, renamedFrom: 'prio');
/// }
///
/// // Everything DatumQueryField offers still works:
/// final query = DatumQueryBuilder<Task>().whereField(TaskFields.priority, isGreaterThan: 2).build();
/// ```
class DatumFieldSpec<E, V> extends DatumQueryField<E, V> {
  DatumFieldSpec(
    super.name, {
    this.getter,
    DatumFieldCodec<V>? codec,
    this.sqlType,
    this.defaultValue,
    this.renamedFrom,
    this.coreRole,
  }) : codec = codec ?? DatumFieldCodec.infer<V>();

  /// Marks one of the six standard sync fields (set by
  /// [datumCoreFieldSpecs]); null for payload fields. `DatumSchema.diffOf` /
  /// `propsOf` use it to separate payload from sync metadata.
  final DatumCoreRole? coreRole;

  /// Extracts this field's value from an entity; required for
  /// `DatumSchema.toMap` delegation, optional otherwise.
  final DatumFieldGetter<E, V>? getter;

  /// Converts between [V] and the persisted representation.
  final DatumFieldCodec<V> codec;

  /// Explicit SQL column type (e.g. `'TEXT'`); wins over [resolveSqlType]'s
  /// derivation.
  final String? sqlType;

  /// Backfill value auto-migration uses when adding this column to existing
  /// rows. Required (or [isNullable]) for a field to be auto-addable.
  final V? defaultValue;

  /// The previous serialized name of this field. Auto-migration treats a
  /// store that has [renamedFrom] but not [name] as a rename instead of a
  /// drop + add (which would lose data).
  final String? renamedFrom;

  /// The Dart value type of this field.
  Type get valueType => V;

  /// Whether [V] admits null.
  bool get isNullable => null is V;

  /// Encodes [value] with [codec].
  Object? encode(V value) => codec.encode(value);

  /// Decodes [raw] with [codec], wrapping any failure in a
  /// [SchemaReadException] that names this field.
  V decode(Object? raw) {
    try {
      return codec.decode(raw);
    } on SchemaReadException {
      rethrow;
    } catch (error) {
      throw SchemaReadException(fieldName: name, expectedType: V, actualValue: raw, cause: error);
    }
  }

  /// The SQL column type for this field: [sqlType] when given, else derived
  /// from [V] (int→INTEGER, double→REAL / DOUBLE PRECISION, num→NUMERIC,
  /// bool→BOOLEAN, String/DateTime/Uri/BigInt→TEXT, Duration→INTEGER).
  ///
  /// Throws [ArgumentError] for other types — declare `sqlType:` explicitly.
  String resolveSqlType({SqlDialect dialect = SqlDialect.sqlite}) {
    if (sqlType != null) return sqlType!;
    bool isType<T>() => V == T || V == _typeOf<T?>();
    if (isType<int>() || isType<Duration>()) return 'INTEGER';
    if (isType<double>()) return dialect == SqlDialect.postgresql ? 'DOUBLE PRECISION' : 'REAL';
    if (isType<num>()) return 'NUMERIC';
    if (isType<bool>()) return 'BOOLEAN';
    if (isType<String>() || isType<DateTime>() || isType<Uri>() || isType<BigInt>()) return 'TEXT';
    throw ArgumentError('Cannot derive a SQL type for $V (field "$name") — pass sqlType: explicitly.');
  }
}

Type _typeOf<T>() => T;

/// The six standard sync fields every [DatumEntityInterface] carries, as
/// individually-typed specs plus an [all] list to spread into a schema:
///
/// ```dart
/// static final core = datumCoreFieldSpecs<Task>();
/// static final schema = DatumSchema<Task>(
///   name: 'tasks',
///   fields: [...core.all, TaskFields.title],
///   construct: (r) => Task(id: r(core.id), version: r(core.version), ...),
/// );
/// ```
final class DatumCoreFields<E extends DatumEntityInterface> {
  DatumCoreFields._({
    required this.id,
    required this.userId,
    required this.modifiedAt,
    required this.createdAt,
    required this.version,
    required this.isDeleted,
  });

  final DatumFieldSpec<E, String> id;
  final DatumFieldSpec<E, String> userId;
  final DatumFieldSpec<E, DateTime> modifiedAt;
  final DatumFieldSpec<E, DateTime> createdAt;
  final DatumFieldSpec<E, int> version;
  final DatumFieldSpec<E, bool> isDeleted;

  /// All six specs, for spreading into `DatumSchema.fields`.
  List<DatumFieldSpec<E, dynamic>> get all => [id, userId, modifiedAt, createdAt, version, isDeleted];
}

/// Builds the six standard sync-field specs with camelCase keys by default
/// (matching `SqliteLocalAdapter`'s core columns). Every key is overridable
/// for snake_case stores, and [dateCodec] controls how the two timestamps
/// are persisted (ISO-8601 by default, with lenient decode that also
/// accepts epoch milliseconds).
DatumCoreFields<E> datumCoreFieldSpecs<E extends DatumEntityInterface>({
  String id = 'id',
  String userId = 'userId',
  String modifiedAt = 'modifiedAt',
  String createdAt = 'createdAt',
  String version = 'version',
  String isDeleted = 'isDeleted',
  DatumFieldCodec<DateTime> dateCodec = DatumFieldCodec.dateTimeIso,
}) =>
    DatumCoreFields._(
      id: DatumFieldSpec<E, String>(id, getter: (e) => e.id, coreRole: DatumCoreRole.id),
      userId: DatumFieldSpec<E, String>(userId, getter: (e) => e.userId, coreRole: DatumCoreRole.userId),
      modifiedAt: DatumFieldSpec<E, DateTime>(modifiedAt, getter: (e) => e.modifiedAt, codec: dateCodec, coreRole: DatumCoreRole.modifiedAt),
      createdAt: DatumFieldSpec<E, DateTime>(createdAt, getter: (e) => e.createdAt, codec: dateCodec, coreRole: DatumCoreRole.createdAt),
      version: DatumFieldSpec<E, int>(version, getter: (e) => e.version, coreRole: DatumCoreRole.version),
      isDeleted: DatumFieldSpec<E, bool>(isDeleted, getter: (e) => e.isDeleted, coreRole: DatumCoreRole.isDeleted),
    );
