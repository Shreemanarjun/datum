import 'field_info.dart';

const _numericTypes = {'int', 'double', 'num', 'Duration', 'Color', 'DateTime'};
const _stringTypes = {'String', 'Uri', 'BigInt'};
const _rangeOps = [
  'isGreaterThan',
  'isGreaterThanOrEqualTo',
  'isLessThan',
  'isLessThanOrEqualTo',
  'between',
];
const _listOps = {'between', 'isIn', 'isNotIn'};
const _textOps = [
  'contains',
  'containsIgnoreCase',
  'startsWith',
  'endsWith',
  'matches',
];

/// Type-safe `DatumQueryBuilder<Entity>` extension. Relation fields never
/// reach here: callers pass serializable fields only.
String queryBuilderCode(String className, List<FieldInfo> fields) {
  final methods = fields.map((f) => _queryMethods(className, f)).join();
  return '\n// Type-safe query builder extension\n'
      'extension ${className}Query on DatumQueryBuilder<$className> {\n'
      '$methods}\n';
}

/// Filter operators supported for [baseType], or null when the type is not
/// queryable.
List<String>? _operatorsFor(String baseType, bool isEnum) {
  final numeric = _numericTypes.contains(baseType);
  final string = _stringTypes.contains(baseType) || isEnum;
  if (!numeric && !string && baseType != 'bool') return null;
  return [
    'isEqualTo',
    'isNotEqualTo',
    if (numeric) ..._rangeOps,
    if (numeric || string) ...['isIn', 'isNotIn'],
    if (string && !isEnum) ..._textOps,
  ];
}

/// Accessor that turns a query value into its stored form, or null when the
/// value is stored as-is.
String? _storedFormAccessor(String baseType, bool isEnum) => switch (baseType) {
  'DateTime' => 'millisecondsSinceEpoch',
  'Duration' => 'inMicroseconds',
  'Uri' || 'BigInt' => 'toString()',
  'Color' => 'toARGB32()',
  _ when isEnum => 'name',
  _ => null,
};

String _paramType(String op, String baseType) => switch (op) {
  _ when _listOps.contains(op) => 'List<$baseType>?',
  _ when _textOps.contains(op) => 'String?',
  _ => '$baseType?',
};

String _whereArg(String op, String? accessor) => switch (accessor) {
  null => op,
  _ when _listOps.contains(op) => '$op.map((e) => e.$accessor).toList()',
  _ => '$op.$accessor',
};

String _queryMethods(String className, FieldInfo f) {
  final baseType = f.baseType;
  final ops = _operatorsFor(baseType, f.isEnum);
  if (ops == null) return '';
  final accessor = _storedFormAccessor(baseType, f.isEnum);

  final b = StringBuffer()
    ..writeln('  DatumQueryBuilder<$className> where${capitalize(f.name)}({');
  for (final op in ops) {
    b.writeln('    ${_paramType(op, baseType)} $op,');
  }
  b.writeln('  }) {');
  for (final op in ops) {
    b.writeln(
      "    if ($op != null) {\n      where('${f.mapKey}', $op: ${_whereArg(op, accessor)});\n    }",
    );
  }
  b
    ..writeln('    return this;')
    ..writeln('  }');
  if (baseType != 'bool') {
    b
      ..writeln(
        '  DatumQueryBuilder<$className> orderBy${capitalize(f.name)}({bool descending = false}) {',
      )
      ..writeln("    orderBy('${f.mapKey}', descending: descending);")
      ..writeln('    return this;')
      ..writeln('  }');
  }
  return b.toString();
}
