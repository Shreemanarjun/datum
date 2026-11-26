import 'field_info.dart';

/// How a field's value is turned into a map value (toDatumMap / datumDiff).
enum _SerialKind {
  color,
  offsetList,
  enumName,
  duration,
  text,
  dateTime,
  plain,
}

_SerialKind _serialKindOf(FieldInfo f) {
  final type = f.type;
  bool isOf(String base) => type == base || type.startsWith('$base?');
  return switch (type) {
    'Color' => _SerialKind.color,
    'List<Offset>' => _SerialKind.offsetList,
    _ when f.isEnum => _SerialKind.enumName,
    _ when isOf('Duration') => _SerialKind.duration,
    _ when isOf('Uri') || isOf('BigInt') => _SerialKind.text,
    _ when isOf('DateTime') => _SerialKind.dateTime,
    _ => _SerialKind.plain,
  };
}

/// Map value expression for [f]. Diffs always encode dates as ISO strings;
/// toDatumMap picks the encoding from `target` at runtime.
String _serializedValue(FieldInfo f, {required bool forDiff}) {
  final n = f.name;
  final q = f.isNullable ? '?' : '';
  if (f.toGenerator case final generator?) {
    return generator.replaceAll('%DATA_PROPERTY%', n);
  }
  return switch (_serialKindOf(f)) {
    _SerialKind.color => '$n.toARGB32()',
    _SerialKind.offsetList => "$n.map((p) => {'x': p.dx, 'y': p.dy}).toList()",
    _SerialKind.enumName => '$n$q.name',
    _SerialKind.duration => '$n$q.inMicroseconds',
    _SerialKind.text => '$n$q.toString()',
    _SerialKind.dateTime when forDiff => '$n$q.toUtc().toIso8601String()',
    _SerialKind.dateTime =>
      'target == MapTarget.remote ? $n$q.toUtc().toIso8601String() : $n$q.millisecondsSinceEpoch',
    _SerialKind.plain => n,
  };
}

String toDatumMapCode(List<FieldInfo> fields) {
  final b = StringBuffer()
    ..writeln(
      '  Map<String, dynamic> datumToMap({MapTarget target = MapTarget.local}) {',
    )
    ..writeln('    final map = <String, dynamic>{');
  for (final f in fields) {
    // Timestamps are encoded per target below.
    if (f.name == 'createdAt' || f.name == 'modifiedAt') continue;
    b.writeln("      '${f.mapKey}': ${_serializedValue(f, forDiff: false)},");
  }
  return (b
        ..writeln('    };')
        ..writeln('    if (target == MapTarget.remote) {')
        ..writeln("      map['created_at'] = createdAt.toUtc().toIso8601String();")
        ..writeln("      map['modified_at'] = modifiedAt.toUtc().toIso8601String();")
        ..writeln('    } else {')
        ..writeln("      map['created_at'] = createdAt.millisecondsSinceEpoch;")
        ..writeln(
          "      map['modified_at'] = modifiedAt.millisecondsSinceEpoch;",
        )
        ..writeln('    }')
        ..writeln('    return map;')
        ..writeln('  }'))
      .toString();
}

// Fields the generated diff skips unless `@DatumField(diff: true)` says
// otherwise. `isDeleted` is NOT here: a soft delete or restore pushed as an
// update must register as a change, or the manager skips the save as a no-op.
const _diffExcluded = {
  'id',
  'userId',
  'createdAt',
  'modifiedAt',
  'version',
};

String diffCode(String className, List<FieldInfo> fields) {
  final b = StringBuffer()
    ..writeln(
      '\n  Map<String, dynamic>? datumDiff(DatumEntityInterface oldVersion, {MapTarget target = MapTarget.local}) {',
    );
  final diffable = fields.where((f) => f.diff ?? !_diffExcluded.contains(f.name));
  if (diffable.isNotEmpty) {
    b.writeln('    final old = oldVersion as $className;');
  }
  b.writeln('    final changes = <String, dynamic>{};');

  final needsDeepEqual = diffable.any((f) => f.isCollection);
  if (needsDeepEqual) b.writeln(_deepEqualHelper);

  for (final f in diffable) {
    final n = f.name;
    final compareExpr = needsDeepEqual && f.isCollection
        ? '!isEqual($n, old.$n)'
        : '$n != old.$n';
    b
      ..writeln('    if ($compareExpr) {')
      ..writeln(
        "      changes['${f.mapKey}'] = ${_serializedValue(f, forDiff: true)};",
      )
      ..writeln('    }');
  }

  if (fields.any((f) => f.name == 'modifiedAt')) {
    b
      ..writeln('    if (changes.isNotEmpty) {')
      ..writeln("      changes['modified_at'] = modifiedAt.toUtc().toIso8601String();")
      ..writeln("      changes['version'] = version;")
      ..writeln('    }');
  }
  return (b
        ..writeln('    return changes.isEmpty ? null : changes;')
        ..writeln('  }'))
      .toString();
}

/// Top-level `_<entity>ListEquals` helper used by `datumEquals`.
String listEqualsHelper(String className) =>
    '''
bool _${lowerCamel(className)}ListEquals<T>(List<T>? a, List<T>? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

''';

String fromMapCode(
  String className,
  List<FieldInfo> fields,
  Set<String> ctorParams,
  bool strictNullChecks,
) {
  final b = StringBuffer()
    ..writeln('\n$className _\$${className}FromMap(Map<String, dynamic> map) {')
    ..writeln('  return $className(');
  for (final f in fields) {
    // Relations are restored by RelationalDatumEntity, non-constructor fields
    // cannot be passed (#26), and ignored fields fall back to their default.
    if (f.isRelation ||
        !acceptsCtorArg(ctorParams, f.name) ||
        f.ignored.contains(IgnoreScope.fromMap)) {
      continue;
    }
    b.writeln(
      '    ${f.name}: ${_deserializedValue(f, className, strictNullChecks)},',
    );
  }
  return (b
        ..writeln('  );')
        ..writeln('}')
        ..writeln(_parseDateHelper(className)))
      .toString();
}

String _deserializedValue(FieldInfo f, String className, bool strict) {
  final raw = "map['${f.mapKey}'] ?? map['${f.name}']";
  final access = '($raw)';
  if (f.fromGenerator case final generator?) {
    return generator.replaceAll('%DATA_PROPERTY%', access);
  }
  String or(String fallback) => '($raw ?? $fallback)';
  final present = "map['${f.mapKey}'] != null || map['${f.name}'] != null";
  final parseDate = '_${lowerCamel(className)}ParseDate';
  if (f.name == 'createdAt' || f.name == 'modifiedAt') {
    return '$parseDate($raw)';
  }

  return switch (f.type) {
    'DateTime' => '$parseDate($raw)',
    'DateTime?' => '$access != null ? $parseDate($raw) : null',
    'int' => strict ? '$access as int' : '${or('0')} as int',
    'String' => strict ? '$access as String' : "${or("''")} as String",
    'bool' => strict ? '$access as bool' : '${or('false')} as bool',
    'int?' || 'String?' || 'bool?' => '$access as ${f.type}',
    'Color' => 'Color(${or('0xFF000000')} as int)',
    'List<Offset>' =>
      "(${or('[]')} as List<dynamic>).map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList()",
    'double' when strict => '($access as num).toDouble()',
    'double' =>
      '${or('0.0')} is int ? ${or('0.0')}.toDouble() : ${or('0.0')} as double',
    'double?' => '$access is int ? $access.toDouble() : $access as double?',
    'Duration' => 'Duration(microseconds: ${or('0')} as int)',
    'Duration?' => '$present ? Duration(microseconds: $access as int) : null',
    'Uri' => "Uri.parse(${or("''")} as String)",
    'Uri?' => '$present ? Uri.parse($access as String) : null',
    'BigInt' => "BigInt.parse(${or("'0'")} as String)",
    'BigInt?' => '$present ? BigInt.parse($access as String) : null',
    _ when f.isEnum && f.isNullable =>
      '$present ? ${f.baseType}.values.byName($access as String) : null',
    _ when f.isEnum => '${f.baseType}.values.byName($access as String)',
    _ => raw,
  };
}

String _parseDateHelper(String className) =>
    '''
DateTime _${lowerCamel(className)}ParseDate(dynamic value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}
''';

const _deepEqualHelper = '''
        bool isEqual(dynamic a, dynamic b) {
          if (a == b) return true;

          if (a is Map && b is Map) {
            if (a.length != b.length) return false;
            for (final key in a.keys) {
              if (!b.containsKey(key) || !isEqual(a[key], b[key])) {
                return false;
              }
            }
            return true;
          }

          if (a is List && b is List) {
            if (a.length != b.length) return false;
            for (int i = 0; i < a.length; i++) {
              if (!isEqual(a[i], b[i])) return false;
            }
            return true;
          }

          if (a is Set && b is Set) {
            if (a.length != b.length) return false;

            // Ensure each element is matched exactly once (prevents duplicate matching)
            final unmatched = b.toList();
            for (final item in a) {
              final matchIndex = unmatched.indexWhere(
                (other) => isEqual(item, other),
              );
              if (matchIndex == -1) return false;
              unmatched.removeAt(matchIndex);
            }

            return unmatched.isEmpty;
          }

          return a == b;
        }
      ''';
