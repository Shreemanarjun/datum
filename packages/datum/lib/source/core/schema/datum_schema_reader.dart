/// Typed access to a raw persisted map, driven by [DatumFieldSpec]s.
library;

import 'package:datum/source/core/errors/datum_exception.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/schema/datum_field_spec.dart';

/// Reads field values out of one raw map with precise, field-named errors —
/// the `as`-cast-free way to implement `fromMap`:
///
/// ```dart
/// factory Task.fromMap(Map<String, dynamic> map) {
///   final r = taskSchema.reader(map);
///   return Task(id: r(idField), title: r(TaskFields.title), due: r.maybe(TaskFields.due));
/// }
/// ```
final class DatumSchemaReader<E extends DatumEntityInterface> {
  DatumSchemaReader(this.schemaName, this.raw);

  /// The owning schema's name, used in error messages.
  final String schemaName;

  /// The raw map being read.
  final Map<String, dynamic> raw;

  /// Shorthand for [get]: `r(TaskFields.title)`.
  V call<V>(DatumFieldSpec<E, V> field) => get(field);

  /// The decoded value of [field]; throws [SchemaReadException] on a missing
  /// key (for non-nullable fields), a null value, or a decode failure.
  V get<V>(DatumFieldSpec<E, V> field) {
    final value = raw[field.name];
    if (value == null && !field.isNullable) {
      throw SchemaReadException(
        entity: schemaName,
        fieldName: field.name,
        expectedType: V,
        actualValue: null,
        cause: raw.containsKey(field.name) ? 'value is null' : 'key missing',
      );
    }
    try {
      return field.decode(value);
    } on SchemaReadException catch (error) {
      // Re-wrap to carry the entity name; the spec-level throw has none.
      throw SchemaReadException(
        entity: schemaName,
        fieldName: field.name,
        expectedType: V,
        actualValue: value,
        cause: error.cause,
      );
    }
  }

  /// Like [get], but returns [fallback] when the key is absent or null.
  V getOr<V>(DatumFieldSpec<E, V> field, V fallback) => raw[field.name] == null ? fallback : get(field);

  /// Like [get], but returns null when the key is absent or null.
  V? maybe<V>(DatumFieldSpec<E, V> field) => raw[field.name] == null ? null : get(field);
}
