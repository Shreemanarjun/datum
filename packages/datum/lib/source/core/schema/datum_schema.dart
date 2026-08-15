/// The runtime schema declaration — one object per entity type powering
/// typed map reads, SQLite column derivation, and auto-migration, without
/// code generation.
library;

import 'package:collection/collection.dart';
import 'package:datum/source/core/errors/datum_exception.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/query/datum_query_sql_converter.dart';
import 'package:datum/source/core/schema/datum_field_spec.dart';
import 'package:datum/source/core/schema/datum_schema_reader.dart';

/// One problem found by [DatumSchema.validate] for a raw map.
typedef SchemaViolation = ({String field, String message});

/// A declarative, runtime description of entity [E]'s serialized shape.
///
/// [fields] must list **every** `toDatumMap` key, including the six core
/// sync fields — start from [datumCoreFieldSpecs] and append your payload:
///
/// ```dart
/// final taskSchema = DatumSchema<Task>(
///   name: 'tasks',
///   fields: [...datumCoreFieldSpecs<Task>(), TaskFields.title, TaskFields.priority],
///   construct: (r) => Task(title: r(TaskFields.title), ...),
/// );
/// ```
///
/// What it feeds:
/// - **Typed reads**: [reader] / [decode] (no `as` casts in `fromMap`).
/// - **Typed writes**: [toMap] when every field has a getter.
/// - **SQLite columns**: [sqlColumns] for `SqliteLocalAdapter`.
/// - **Auto-migration**: [fingerprint] + the field metadata
///   (`defaultValue`, `renamedFrom`) drive the schema differ.
class DatumSchema<E extends DatumEntityInterface> {
  DatumSchema({
    required this.name,
    required List<DatumFieldSpec<E, dynamic>> fields,
    this.construct,
  }) : fields = List.unmodifiable(fields) {
    _validateDeclaration();
  }

  /// The logical entity / table name.
  final String name;

  /// All serialized fields, core sync fields included.
  final List<DatumFieldSpec<E, dynamic>> fields;

  /// Builds an entity from a typed reader; enables [decode] (usable as an
  /// adapter `fromMap` tear-off).
  final E Function(DatumSchemaReader<E> r)? construct;

  late final Map<String, DatumFieldSpec<E, dynamic>> _byName = {for (final f in fields) f.name: f};

  /// The declared field with serialized [name], or null.
  DatumFieldSpec<E, dynamic>? fieldByName(String name) => _byName[name];

  /// A typed reader over a raw persisted [map].
  DatumSchemaReader<E> reader(Map<String, dynamic> map) => DatumSchemaReader<E>(name, map);

  /// Decodes a raw [map] into an entity via [construct].
  E decode(Map<String, dynamic> map) {
    final build = construct;
    if (build == null) {
      throw StateError('DatumSchema("$name").decode requires a construct: callback — '
          'pass one, or keep using your own fromMap with schema.reader(map).');
    }
    return build(reader(map));
  }

  /// Encodes an [entity] into its persisted map via each field's getter.
  ///
  /// Every field must declare a `getter:`. Schema codecs are
  /// target-independent (one wire format for local and remote); [target] is
  /// accepted for signature parity with `toDatumMap`.
  Map<String, dynamic> toMap(E entity, {MapTarget target = MapTarget.local}) {
    return {
      for (final field in fields) field.name: (field as DatumFieldSpec<E, Object?>).encode(_valueOf(field, entity)),
    };
  }

  Object? _valueOf(DatumFieldSpec<E, dynamic> field, E entity) {
    final getter = field.getter;
    if (getter == null) {
      throw StateError('DatumSchema("$name").toMap requires a getter on every field — '
          '"${field.name}" has none.');
    }
    return getter(entity);
  }

  /// A payload-only delta between two entity versions — the schema-driven
  /// implementation of `DatumEntity.diff`, mirroring `datum_generator`'s
  /// `datumDiff`: core sync fields are excluded from the comparison, and
  /// when anything changed the new `modifiedAt`/`version` are stamped in.
  /// Returns null when nothing changed. Requires getters on every field.
  ///
  /// ```dart
  /// @override
  /// Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
  ///     taskSchema.diffOf(oldVersion as Task, this);
  /// ```
  Map<String, dynamic>? diffOf(E oldVersion, E newVersion) {
    const deepEquals = DeepCollectionEquality();
    final delta = <String, dynamic>{};
    for (final field in fields) {
      if (field.coreRole != null) continue;
      final encoded = field as DatumFieldSpec<E, Object?>;
      final before = encoded.encode(_valueOf(field, oldVersion));
      final after = encoded.encode(_valueOf(field, newVersion));
      if (!deepEquals.equals(before, after)) delta[field.name] = after;
    }
    if (delta.isEmpty) return null;
    for (final field in fields) {
      if (field.coreRole == DatumCoreRole.modifiedAt || field.coreRole == DatumCoreRole.version) {
        delta[field.name] = (field as DatumFieldSpec<E, Object?>).encode(_valueOf(field, newVersion));
      }
    }
    return delta;
  }

  /// The payload field values of [entity], for `Equatable.props` overrides
  /// without restating field names (core fields come from `super.props`):
  ///
  /// ```dart
  /// @override
  /// List<Object?> get props => [...super.props, ...taskSchema.propsOf(this)];
  /// ```
  List<Object?> propsOf(E entity) => [
        for (final field in fields)
          if (field.coreRole == null) _valueOf(field, entity),
      ];

  /// Checks a raw [map] against the declaration: missing non-nullable keys
  /// and undecodable values. For tests and debug tooling.
  List<SchemaViolation> validate(Map<String, dynamic> map) {
    final violations = <SchemaViolation>[];
    for (final field in fields) {
      final present = map.containsKey(field.name);
      if (!present || map[field.name] == null) {
        if (!field.isNullable) {
          violations.add((field: field.name, message: present ? 'null for non-nullable ${field.valueType}' : 'missing key'));
        }
        continue;
      }
      try {
        field.decode(map[field.name]);
      } on Object catch (error) {
        violations.add((field: field.name, message: error.toString()));
      }
    }
    return violations;
  }

  /// Column name → SQL type for every declared field.
  Map<String, String> sqlColumns({SqlDialect dialect = SqlDialect.sqlite}) => {for (final field in fields) field.name: field.resolveSqlType(dialect: dialect)};

  /// A stable, field-order-independent hash of the declaration
  /// (name / value type / nullability / sqlType / renamedFrom / has-default
  /// per field). Auto-migration stamps it after successful reconciliation to
  /// skip introspection while the declaration is unchanged.
  late final String fingerprint = _computeFingerprint();

  String _computeFingerprint() {
    final canonical = fields.map((f) => '${f.name}|${f.valueType}|${f.isNullable}|${f.sqlType ?? ''}|${f.renamedFrom ?? ''}|${f.defaultValue != null}').toList()..sort();
    // FNV-1a 64-bit — deterministic across runs and platforms (String.hashCode is not).
    var hash = 0xcbf29ce484222325;
    for (final code in canonical.join('\n').codeUnits) {
      hash = ((hash ^ code) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  void _validateDeclaration() {
    final problems = <String>[];
    final seen = <String>{};
    for (final field in fields) {
      if (!seen.add(field.name)) {
        problems.add('Field "${field.name}" is declared more than once.');
      }
    }
    for (final field in fields) {
      final from = field.renamedFrom;
      if (from == null) continue;
      if (from == field.name) {
        problems.add('Field "${field.name}" declares renamedFrom pointing at itself.');
      } else if (seen.contains(from)) {
        problems.add('Field "${field.name}" declares renamedFrom: "$from", '
            'but "$from" is still a declared field — remove one.');
      }
    }
    if (problems.isNotEmpty) {
      throw MigrationException(
        code: DatumExceptionCode.schemaMismatch,
        message: 'Invalid DatumSchema("$name"):\n${problems.join('\n')}',
      );
    }
  }
}
