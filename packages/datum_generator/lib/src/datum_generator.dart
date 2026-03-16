import 'package:build/build.dart';
import 'core/annotations.dart';
import 'package:source_gen/source_gen.dart';

const _ignoreChecker = TypeChecker.fromUrl(
  'package:datum_generator/src/core/annotations.dart#DatumIgnore',
);
const _fieldChecker = TypeChecker.fromUrl(
  'package:datum_generator/src/core/annotations.dart#DatumField',
);
const _belongsToChecker = TypeChecker.fromUrl(
  'package:datum_generator/src/core/annotations.dart#BelongsToRelation',
);
const _hasManyChecker = TypeChecker.fromUrl(
  'package:datum_generator/src/core/annotations.dart#HasManyRelation',
);
const _hasOneChecker = TypeChecker.fromUrl(
  'package:datum_generator/src/core/annotations.dart#HasOneRelation',
);
const _manyToManyChecker = TypeChecker.fromUrl(
  'package:datum_generator/src/core/annotations.dart#ManyToManyRelation',
);

class DatumGenerator extends GeneratorForAnnotation<DatumSerializable> {
  @override
  dynamic generateForAnnotatedElement(
    dynamic element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    // Note: strict type check (element is ClassElement) sometimes fails due to
    // analyzer version mismatches in build environment. We trust source_gen here.

    final dynamicElement = element as dynamic;
    String? name;
    try {
      name = dynamicElement.name;
    } catch (_) {
      try {
        name = dynamicElement.displayName;
      } catch (_) {
        name = dynamicElement.toString();
      }
    }
    final className = name!;

    List<dynamic>? fields;
    try {
      fields = dynamicElement.fields;
    } catch (_) {
      try {
        fields = dynamicElement.fields2;
      } catch (_) {
        throw InvalidGenerationSourceError(
          'DatumSerializable can only be applied to classes (failed to access fields).',
        );
      }
    }

    final tableName = annotation.read('tableName').isNull
        ? _camelToSnake(className)
        : annotation.read('tableName').stringValue;
    final generateMixin = annotation.read('generateMixin').isNull
        ? false
        : annotation.read('generateMixin').boolValue;

    final List<dynamic> allFields = (fields as List)
        .where((f) => !f.isStatic && !f.isSynthetic)
        .toList();

    final serializableFields = allFields
        .where(
          (f) =>
              !_isIgnored(f, property: 'toMap') &&
              !_hasRelationAnnotationOnField(f),
        )
        .toList();

    final buffer = StringBuffer();

    // Generate extension
    buffer.writeln('extension \$${className}Datum on $className {');
    buffer.writeln("  static const String tableName = '$tableName';");

    // toDatumMap
    _generateToDatumMap(buffer, serializableFields);

    // diff
    _generateDiff(buffer, className, serializableFields);

    // copyWith
    _generateCopyWith(buffer, className, allFields);

    // copyWithAll
    _generateCopyWithAll(buffer, className, allFields);

    // operator == and hashCode
    final equatableFields = allFields
        .where(
          (f) =>
              !_hasRelationAnnotationOnField(f) &&
              !_isIgnored(f, property: 'equality'),
        )
        .toList();
    _generateEquality(buffer, className, equatableFields);

    // Check if this is a RelationalDatumEntity and generate relations
    final isRelational = _isRelationalEntity(element);
    if (isRelational) {
      _generateRelations(buffer, allFields, className);
    }

    buffer.writeln('}');

    // Check if we need the list equals helper (only if entity has List fields in equatable fields)
    final hasListFields = equatableFields.any(
      (f) => f.type.getDisplayString().startsWith('List'),
    );
    _generateFromMap(buffer, className, allFields, hasListFields);

    // Generate mixin only if requested
    if (generateMixin) {
      _generateDatumMixin(buffer, className, allFields, isRelational);
      log.info(
        'Generated mixin for $className. Use it with: class $className extends ${isRelational ? 'RelationalDatumEntity' : 'DatumEntity'} with _\$${className}Mixin',
      );
    } else {
      log.fine(
        'Skipped mixin generation for $className. To enable, use: @DatumSerializable(generateMixin: true)',
      );
    }

    // Generate type-safe query builder
    _generateQueryBuilder(buffer, className, serializableFields);

    return buffer.toString();
  }

  void _generateDatumMixin(
    StringBuffer buffer,
    String className,
    List<dynamic> allFields,
    bool isRelational,
  ) {
    final baseClass = isRelational ? 'RelationalDatumEntity' : 'DatumEntity';

    buffer.writeln('\n// Mixin to provide all required method implementations');
    buffer.writeln('mixin _\$${className}Mixin on $baseClass {');

    // toDatumMap override
    buffer.writeln('  @override');
    buffer.writeln(
      '  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {',
    );
    buffer.writeln(
      '    return (this as $className).datumToMap(target: target);',
    );
    buffer.writeln('  }');

    // diff override
    buffer.writeln('\n  @override');
    buffer.writeln(
      '  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {',
    );
    buffer.writeln('    return (this as $className).datumDiff(oldVersion);');
    buffer.writeln('  }');

    // copyWith override
    if (isRelational) {
      buffer.writeln('\n  @override');
    } else {
      buffer.writeln('\n');
    }
    buffer.writeln('  $baseClass copyWith({');
    buffer.writeln('    DateTime? modifiedAt,');
    buffer.writeln('    int? version,');
    buffer.writeln('    bool? isDeleted,');
    buffer.writeln('  }) {');
    buffer.writeln('    return (this as $className).copyWithAll(');
    buffer.writeln('      modifiedAt: modifiedAt,');
    buffer.writeln('      version: version,');
    buffer.writeln('      isDeleted: isDeleted,');
    buffer.writeln('    );');
    buffer.writeln('  }');

    // operator == override
    buffer.writeln('\n  @override');
    buffer.writeln('  bool operator ==(Object other) {');
    buffer.writeln(
      '    return other is $className && (this as $className).datumEquals(other);',
    );
    buffer.writeln('  }');

    // hashCode override
    buffer.writeln('\n  @override');
    buffer.writeln('  int get hashCode => (this as $className).datumHashCode;');

    // toString override
    buffer.writeln('\n  @override');
    buffer.writeln('  String toString() {');
    buffer.writeln(
      '    final map = toDatumMap();',
    ); // Use map for simpler string representation
    buffer.writeln("    return '$className(\${map.toString()})';");
    buffer.writeln('  }');

    // props override (for Equatable)
    buffer.writeln('\n  @override');
    buffer.writeln('  List<Object?> get props => [');

    for (final field in allFields) {
      if (!_isIgnored(field, property: 'equality') &&
          !_hasRelationAnnotationOnField(field)) {
        buffer.writeln('    (this as $className).${_getElementName(field)},');
      }
    }
    // Also include metadata fields if not in allFields (they are in DatumEntity interface)
    // Actually, DatumEntityBase includes them in props.
    // We should include ALL fields that matter for equality.
    // Since we override ==, props is mainly for backup.
    // But let's just stick to the fields visible in the class.

    buffer.writeln('  ];');

    // Add getters and setters for relationship fields to ensure they are "used"
    // and provide a clean API when using the mixin.
    for (final field in allFields) {
      if (_hasRelationAnnotationOnField(field)) {
        final fieldName = _getElementName(field);
        if (fieldName.startsWith('_')) {
          final publicName = fieldName.substring(1);
          final type = field.type.getDisplayString();
          final isList = type.startsWith('List');

          buffer.writeln(
            '\n  /// Get the related ${isList ? 'entities' : 'entity'}',
          );
          buffer.writeln(
            '  $type get $publicName => (this as $className).$fieldName;',
          );

          buffer.writeln(
            '\n  /// Set the related ${isList ? 'entities' : 'entity'}',
          );
          buffer.writeln('  set $publicName($type value) {');
          buffer.writeln('    if (this is $className) {');
          buffer.writeln(
            '      (this as $className).datumRelations[\'$publicName\']?.setRaw(value);',
          );
          buffer.writeln('    }');
          buffer.writeln('  }');
        }
      }
    }

    // relations override for RelationalDatumEntity
    if (isRelational) {
      buffer.writeln('\n  @override');
      buffer.writeln(
        '  Map<String, Relation> get relations => (this as $className).datumRelations;',
      );
    }

    // toMap helper
    buffer.writeln('\n  Map<String, dynamic> toMap() => toDatumMap();');

    // toJson helper
    buffer.writeln(
      '\n  String toJson() => DatumJsonUtils.encode(toDatumMap());',
    );

    buffer.writeln('}');

    // Generate factory extension for fromMap and fromJson
    buffer.writeln('\n// Extension to provide fromMap and fromJson factories');
    buffer.writeln('extension ${className}Factory on $className {');
    buffer.writeln('  static $className fromMap(Map<String, dynamic> map) {');
    buffer.writeln('    return _\$${className}FromMap(map);');
    buffer.writeln('  }');
    buffer.writeln('\n  static $className fromJson(String source) {');
    buffer.writeln(
      '    return fromMap(DatumJsonUtils.decode(source) as Map<String, dynamic>);',
    );
    buffer.writeln('  }');
    buffer.writeln('}');
  }

  String _getElementName(dynamic e) {
    try {
      final name = e.name;
      if (name != null) return name as String;
    } catch (_) {}
    try {
      final name = e.displayName;
      if (name != null) return name as String;
    } catch (_) {}
    return e.toString();
  }

  bool _isIgnored(dynamic field, {String? property}) {
    try {
      final annotation = _ignoreChecker.firstAnnotationOf(field);
      if (annotation == null) return false;

      // If no specific property requested, any DatumIgnore annotation means it's ignored for serialization (backward compatibility)
      if (property == null) return true;

      final reader = ConstantReader(annotation);
      try {
        final fieldReader = reader.read(property);
        if (fieldReader.isNull) {
          // Fallback for backward compatibility if the field doesn't exist on the annotation yet
          if (property == 'fromMap' || property == 'toMap') return true;
          return false;
        }
        return fieldReader.boolValue;
      } catch (_) {
        // Fallback for backward compatibility
        if (property == 'fromMap' || property == 'toMap') return true;
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  String _camelToSnake(String name) {
    final result = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final char = name[i];
      if (char.toUpperCase() == char && i > 0) {
        result.write('_');
      }
      result.write(char.toLowerCase());
    }
    return result.toString();
  }

  String _toLowerCamelCase(String name) {
    if (name.isEmpty) return name;
    return name[0].toLowerCase() + name.substring(1);
  }

  void _generateToDatumMap(StringBuffer buffer, List<dynamic> fields) {
    buffer.writeln(
      '  Map<String, dynamic> datumToMap({MapTarget target = MapTarget.local}) {',
    );
    buffer.writeln('    final map = <String, dynamic>{');
    for (final field in fields) {
      final fieldName = _getElementName(field);
      final mapKey = _getMapKey(field);

      if (fieldName == 'createdAt' || fieldName == 'modifiedAt') {
        // Handled specially below
        continue;
      }

      final type = field.type.getDisplayString();
      final typeElement = field.type.element;
      final toGenerator = _getToGenerator(field);

      if (toGenerator != null) {
        final code = toGenerator.replaceAll('%DATA_PROPERTY%', fieldName);
        buffer.writeln("      '$mapKey': $code,");
        continue;
      }

      // Check if it's an enum by checking the element kind
      final isEnum = typeElement != null && typeElement.kind.name == 'ENUM';

      if (type == 'Color') {
        buffer.writeln("      '$mapKey': $fieldName.toARGB32(),");
      } else if (type == 'List<Offset>') {
        buffer.writeln(
          "      '$mapKey': $fieldName.map((p) => {'x': p.dx, 'y': p.dy}).toList(),",
        );
      } else if (isEnum) {
        // Serialize enum as string (name)
        if (type.endsWith('?')) {
          buffer.writeln("      '$mapKey': $fieldName?.name,");
        } else {
          buffer.writeln("      '$mapKey': $fieldName.name,");
        }
      } else if (type == 'Duration' || type.startsWith('Duration?')) {
        // Serialize Duration as microseconds
        buffer.writeln(
          "      '$mapKey': $fieldName${type.endsWith('?') ? '?' : ''}.inMicroseconds,",
        );
      } else if (type == 'Uri' || type.startsWith('Uri?')) {
        // Serialize Uri as string
        buffer.writeln(
          "      '$mapKey': $fieldName${type.endsWith('?') ? '?' : ''}.toString(),",
        );
      } else if (type == 'BigInt' || type.startsWith('BigInt?')) {
        // Serialize BigInt as string
        buffer.writeln(
          "      '$mapKey': $fieldName${type.endsWith('?') ? '?' : ''}.toString(),",
        );
      } else {
        buffer.writeln("      '$mapKey': $fieldName,");
      }
    }
    buffer.writeln('    };');

    buffer.writeln('    if (target == MapTarget.remote) {');
    buffer.writeln("      map['createdAt'] = createdAt.toIso8601String();");
    buffer.writeln("      map['modifiedAt'] = modifiedAt.toIso8601String();");
    buffer.writeln('    } else {');
    buffer.writeln(
      "      map['createdAt'] = createdAt.millisecondsSinceEpoch;",
    );
    buffer.writeln(
      "      map['modifiedAt'] = modifiedAt.millisecondsSinceEpoch;",
    );
    buffer.writeln('    }');

    buffer.writeln('    return map;');
    buffer.writeln('  }');
  }

  void _generateDiff(
    StringBuffer buffer,
    String className,
    List<dynamic> fields,
  ) {
    buffer.writeln(
      '\n  Map<String, dynamic>? datumDiff(DatumEntityInterface oldVersion) {',
    );
    final diffableFields = fields.where((f) {
      final fieldName = _getElementName(f);
      return ![
        'id',
        'userId',
        'createdAt',
        'modifiedAt',
        'version',
        'isDeleted',
      ].contains(fieldName);
    }).toList();

    if (diffableFields.isNotEmpty) {
      buffer.writeln('    final old = oldVersion as $className;');
    }
    buffer.writeln('    final changes = <String, dynamic>{};');

    for (final field in fields) {
      final fieldName = _getElementName(field);
      if ([
        'id',
        'userId',
        'createdAt',
        'modifiedAt',
        'version',
        'isDeleted',
      ].contains(fieldName)) {
        continue;
      }

      final mapKey = _getMapKey(field);
      final type = field.type.getDisplayString();
      final typeElement = field.type.element;
      final isEnum = typeElement != null && typeElement.kind.name == 'ENUM';

      buffer.writeln("    if ($fieldName != old.$fieldName) {");

      if (type == 'Color') {
        buffer.writeln("      changes['$mapKey'] = $fieldName.toARGB32();");
      } else if (type == 'List<Offset>') {
        buffer.writeln(
          "      changes['$mapKey'] = $fieldName.map((p) => {'x': p.dx, 'y': p.dy}).toList();",
        );
      } else if (isEnum) {
        if (type.endsWith('?')) {
          buffer.writeln("      changes['$mapKey'] = $fieldName?.name;");
        } else {
          buffer.writeln("      changes['$mapKey'] = $fieldName.name;");
        }
      } else if (type == 'Duration' || type.startsWith('Duration?')) {
        buffer.writeln(
          "      changes['$mapKey'] = $fieldName${type.endsWith('?') ? '?' : ''}.inMicroseconds;",
        );
      } else if (type == 'Uri' || type.startsWith('Uri?')) {
        buffer.writeln(
          "      changes['$mapKey'] = $fieldName${type.endsWith('?') ? '?' : ''}.toString();",
        );
      } else if (type == 'BigInt' || type.startsWith('BigInt?')) {
        buffer.writeln(
          "      changes['$mapKey'] = $fieldName${type.endsWith('?') ? '?' : ''}.toString();",
        );
      } else {
        buffer.writeln("      changes['$mapKey'] = $fieldName;");
      }

      buffer.writeln('    }');
    }

    if (fields.any((f) => _getElementName(f) == 'modifiedAt')) {
      buffer.writeln('    if (changes.isNotEmpty) {');
      buffer.writeln(
        "      changes['modifiedAt'] = modifiedAt.toIso8601String();",
      );
      buffer.writeln("      changes['version'] = version;");
      buffer.writeln('    }');
    }

    buffer.writeln('    return changes.isEmpty ? null : changes;');
    buffer.writeln('  }');
  }

  void _generateCopyWith(
    StringBuffer buffer,
    String className,
    List<dynamic> fields,
  ) {
    buffer.writeln('  $className copyWith({');
    buffer.writeln('    DateTime? modifiedAt,');
    buffer.writeln('    int? version,');
    buffer.writeln('    bool? isDeleted,');
    buffer.writeln('  }) {');
    buffer.writeln('    return copyWithAll(');
    buffer.writeln('      modifiedAt: modifiedAt,');
    buffer.writeln('      version: version,');
    buffer.writeln('      isDeleted: isDeleted,');
    buffer.writeln('    );');
    buffer.writeln('  }');
  }

  void _generateCopyWithAll(
    StringBuffer buffer,
    String className,
    List<dynamic> allFields,
  ) {
    // Only fields that are NOT ignored and NOT relations are parameters
    final copyableFields = allFields
        .where(
          (f) =>
              !_hasRelationAnnotationOnField(f) &&
              !_isIgnored(f, property: 'copyWith'),
        )
        .toList();

    buffer.writeln('  $className copyWithAll({');
    for (final field in copyableFields) {
      final type = field.type.getDisplayString();
      final fieldName = _getElementName(field);
      // Make them all optional for copyWith
      final optionalType = type.endsWith('?') ? type : '$type?';
      buffer.writeln('    $optionalType $fieldName,');
    }
    buffer.writeln('  }) {');

    // Check for changes to increment version automatically
    buffer.writeln('    final hasChanges = ');
    final changeFields = copyableFields
        .where((f) => !['modifiedAt', 'version'].contains(_getElementName(f)))
        .toList();
    if (changeFields.isEmpty) {
      buffer.write('false');
    } else {
      for (var i = 0; i < changeFields.length; i++) {
        buffer.write('${_getElementName(changeFields[i])} != null');
        if (i < changeFields.length - 1) buffer.write(' || ');
      }
    }
    buffer.writeln(';');

    buffer.writeln('    return $className(');
    for (final field in allFields) {
      if (_hasRelationAnnotationOnField(field)) continue;

      final fieldName = _getElementName(field);
      final isParam = copyableFields.any(
        (f) => _getElementName(f) == fieldName,
      );

      if (fieldName == 'version') {
        buffer.writeln(
          '      version: version ?? (hasChanges ? this.version + 1 : this.version),',
        );
      } else if (isParam) {
        buffer.writeln('      $fieldName: $fieldName ?? this.$fieldName,');
      } else {
        // Ignored from copyWith, but must still be passed to constructor if it's there
        buffer.writeln('      $fieldName: $fieldName,');
      }
    }
    buffer.writeln('    );');
    buffer.writeln('  }');
  }

  void _generateEquality(
    StringBuffer buffer,
    String className,
    List<dynamic> fields,
  ) {
    buffer.writeln('\n  bool datumEquals($className other) {');
    buffer.writeln('    if (identical(this, other)) return true;');
    buffer.write('    return ');
    for (var i = 0; i < fields.length; i++) {
      final name = _getElementName(fields[i]);
      final type = fields[i].type.getDisplayString();
      if (type.startsWith('List')) {
        buffer.write(
          '_${_toLowerCamelCase(className)}ListEquals(other.$name, $name)',
        );
      } else {
        buffer.write('other.$name == $name');
      }
      if (i < fields.length - 1) buffer.write(' &&\n        ');
    }
    buffer.writeln(';');
    buffer.writeln('  }');

    buffer.writeln('\n  int get datumHashCode {');
    buffer.write('    return ');
    for (var i = 0; i < fields.length; i++) {
      buffer.write('${_getElementName(fields[i])}.hashCode');
      if (i < fields.length - 1) buffer.write(' ^\n        ');
    }
    buffer.writeln(';');
    buffer.writeln('  }');
  }

  void _generateFromMap(
    StringBuffer buffer,
    String className,
    List<dynamic> allFields,
    bool hasListFields,
  ) {
    // Only generate the list equals helper if needed
    if (hasListFields) {
      buffer.writeln('''
bool _${_toLowerCamelCase(className)}ListEquals<T>(List<T>? a, List<T>? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
''');
    }

    final deserializableFields = allFields
        .where(
          (f) =>
              !_hasRelationAnnotationOnField(f) &&
              !_isIgnored(f, property: 'fromMap'),
        )
        .toList();

    buffer.writeln(
      '\n$className _\$${className}FromMap(Map<String, dynamic> map) {',
    );
    buffer.writeln('  return $className(');
    for (final field in allFields) {
      // Relations are handled by the RelationalDatumEntity logic, not constructor
      if (_hasRelationAnnotationOnField(field)) continue;

      final fieldName = _getElementName(field);
      final isDeserializable = deserializableFields.any(
        (f) => _getElementName(f) == fieldName,
      );

      if (!isDeserializable) {
        // If the field is ignored from map, we don't pass it to the constructor.
        // This assumes the field is either optional or has a default value.
        // If it's required and has no default, Dart will correctly flag a compilation error
        // in the generated file, which is the expected behavior for invalid model definitions.
        continue;
      }

      final mapKey = _getMapKey(field); // Default to snake_case
      final type = field.type.getDisplayString();
      final fromGenerator = _getFromGenerator(field);

      if (fromGenerator != null) {
        final access = "map['$mapKey'] ?? map['$fieldName']";
        final code = fromGenerator.replaceAll('%DATA_PROPERTY%', access);
        buffer.writeln("    $fieldName: $code,");
        continue;
      }

      if (fieldName == 'createdAt' || fieldName == 'modifiedAt') {
        buffer.writeln(
          "    $fieldName: _${_toLowerCamelCase(className)}ParseDate(map['$mapKey'] ?? map['$fieldName']),",
        );
      } else if (type == 'int') {
        buffer.writeln(
          "    $fieldName: (map['$mapKey'] ?? map['$fieldName'] ?? 0) as int,",
        );
      } else if (type == 'int?') {
        buffer.writeln(
          "    $fieldName: (map['$mapKey'] ?? map['$fieldName']) as int?,",
        );
      } else if (type == 'String') {
        buffer.writeln(
          "    $fieldName: (map['$mapKey'] ?? map['$fieldName'] ?? '') as String,",
        );
      } else if (type == 'String?') {
        buffer.writeln(
          "    $fieldName: (map['$mapKey'] ?? map['$fieldName']) as String?,",
        );
      } else if (type == 'bool') {
        buffer.writeln(
          "    $fieldName: (map['$mapKey'] ?? map['$fieldName'] ?? false) as bool,",
        );
      } else if (type == 'bool?') {
        buffer.writeln(
          "    $fieldName: (map['$mapKey'] ?? map['$fieldName']) as bool?,",
        );
      } else if (type == 'Color') {
        buffer.writeln(
          "    $fieldName: Color((map['$mapKey'] ?? map['$fieldName'] ?? 0xFF000000) as int),",
        );
      } else if (type == 'List<Offset>') {
        buffer.writeln(
          "    $fieldName: ((map['$mapKey'] ?? map['$fieldName'] ?? []) as List<dynamic>).map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList(),",
        );
      } else if (type == 'double') {
        buffer.writeln(
          "    $fieldName: (map['$mapKey'] ?? map['$fieldName'] ?? 0.0) is int ? (map['$mapKey'] ?? map['$fieldName'] ?? 0.0).toDouble() : (map['$mapKey'] ?? map['$fieldName'] ?? 0.0) as double,",
        );
      } else if (type == 'double?') {
        buffer.writeln(
          "    $fieldName: (map['$mapKey'] ?? map['$fieldName']) is int ? (map['$mapKey'] ?? map['$fieldName']).toDouble() : (map['$mapKey'] ?? map['$fieldName']) as double?,",
        );
      } else if (type == 'Duration') {
        // Deserialize Duration from microseconds
        buffer.writeln(
          "    $fieldName: Duration(microseconds: (map['$mapKey'] ?? map['$fieldName'] ?? 0) as int),",
        );
      } else if (type == 'Duration?') {
        // Deserialize nullable Duration
        buffer.writeln(
          "    $fieldName: map['$mapKey'] != null || map['$fieldName'] != null ? Duration(microseconds: (map['$mapKey'] ?? map['$fieldName']) as int) : null,",
        );
      } else if (type == 'Uri') {
        // Deserialize Uri from string
        buffer.writeln(
          "    $fieldName: Uri.parse((map['$mapKey'] ?? map['$fieldName'] ?? '') as String),",
        );
      } else if (type == 'Uri?') {
        // Deserialize nullable Uri
        buffer.writeln(
          "    $fieldName: map['$mapKey'] != null || map['$fieldName'] != null ? Uri.parse((map['$mapKey'] ?? map['$fieldName']) as String) : null,",
        );
      } else if (type == 'BigInt') {
        // Deserialize BigInt from string
        buffer.writeln(
          "    $fieldName: BigInt.parse((map['$mapKey'] ?? map['$fieldName'] ?? '0') as String),",
        );
      } else if (type == 'BigInt?') {
        // Deserialize nullable BigInt
        buffer.writeln(
          "    $fieldName: map['$mapKey'] != null || map['$fieldName'] != null ? BigInt.parse((map['$mapKey'] ?? map['$fieldName']) as String) : null,",
        );
      } else {
        // Check if it's an enum
        final typeElement = field.type.element;
        final isEnum = typeElement != null && typeElement.kind.name == 'ENUM';

        if (isEnum) {
          // Deserialize enum from string (name)
          final enumTypeName = type.replaceAll('?', '');
          if (type.endsWith('?')) {
            buffer.writeln(
              "    $fieldName: map['$mapKey'] != null || map['$fieldName'] != null ? $enumTypeName.values.byName((map['$mapKey'] ?? map['$fieldName']) as String) : null,",
            );
          } else {
            buffer.writeln(
              "    $fieldName: $enumTypeName.values.byName((map['$mapKey'] ?? map['$fieldName']) as String),",
            );
          }
        } else {
          buffer.writeln(
            "    $fieldName: map['$mapKey'] ?? map['$fieldName'],",
          );
        }
      }
    }
    buffer.writeln('  );');
    buffer.writeln('}');

    // Helper for date parsing if not already present
    buffer.writeln('''
DateTime _${_toLowerCamelCase(className)}ParseDate(dynamic value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}
''');
  }

  String _getMapKey(dynamic field) {
    try {
      final annotation = _fieldChecker.firstAnnotationOf(field);
      if (annotation != null) {
        final reader = ConstantReader(annotation);
        final name = reader.read('name');
        if (!name.isNull) return name.stringValue;
      }
    } catch (_) {}
    return _camelToSnake(_getElementName(field));
  }

  String? _getFromGenerator(dynamic field) {
    try {
      final annotation = _fieldChecker.firstAnnotationOf(field);
      if (annotation != null) {
        final reader = ConstantReader(annotation);
        final fromGenerator = reader.read('fromGenerator');
        if (!fromGenerator.isNull) return fromGenerator.stringValue;
      }
    } catch (_) {}
    return null;
  }

  String? _getToGenerator(dynamic field) {
    try {
      final annotation = _fieldChecker.firstAnnotationOf(field);
      if (annotation != null) {
        final reader = ConstantReader(annotation);
        final toGenerator = reader.read('toGenerator');
        if (!toGenerator.isNull) return toGenerator.stringValue;
      }
    } catch (_) {}
    return null;
  }

  bool _isRelationalEntity(dynamic element) {
    // Check if the class extends RelationalDatumEntity
    var currentElement = element;
    while (currentElement.supertype != null) {
      if (_getElementName(currentElement.supertype!.element) ==
          'RelationalDatumEntity') {
        return true;
      }
      final superElement = currentElement.supertype!.element;
      // if (superElement is! ClassElement) break; // Bypass type check
      currentElement = superElement;
    }
    return false;
  }

  void _generateRelations(
    StringBuffer buffer,
    List<dynamic> allFields,
    String className,
  ) {
    // Find all fields with relationship annotations
    final relationFields = allFields
        .where((field) => _hasRelationAnnotationOnField(field))
        .toList();

    // Always generate datumRelations for RelationalDatumEntity, even if empty

    buffer.writeln('\n  Map<String, Relation> get datumRelations => {');

    for (final field in relationFields) {
      final fieldName = _getElementName(field);
      final relationName = fieldName.startsWith('_')
          ? fieldName.substring(1)
          : fieldName;
      final relationInfo = _getRelationInfoFromField(field);

      if (relationInfo != null) {
        buffer.writeln(
          "    '$relationName': $relationInfo..setRaw($fieldName),",
        );
      }
    }

    buffer.writeln('  };');
  }

  bool _hasRelationAnnotationOnField(dynamic field) {
    try {
      return _belongsToChecker.hasAnnotationOf(field) ||
          _hasManyChecker.hasAnnotationOf(field) ||
          _hasOneChecker.hasAnnotationOf(field) ||
          _manyToManyChecker.hasAnnotationOf(field);
    } catch (_) {
      return false;
    }
  }

  String? _getRelationInfoFromField(dynamic field) {
    try {
      final belongsTo = _belongsToChecker.firstAnnotationOf(field);
      if (belongsTo != null) {
        final reader = ConstantReader(belongsTo);
        // Get types from the annotation instance itself
        final typeMatch = RegExp(
          r'<(.+?)>',
        ).firstMatch(belongsTo.type!.getDisplayString());
        final relatedType = typeMatch?.group(1) ?? 'dynamic';
        final foreignKey = reader.read('foreignKey').stringValue;
        final localKey = reader.read('localKey').stringValue;
        final cascadeDelete = reader.read('cascadeDelete').stringValue;
        return "BelongsTo<$relatedType>(this, '$foreignKey', localKey: '$localKey', cascadeDeleteBehavior: CascadeDeleteBehavior.$cascadeDelete)";
      }

      final hasMany = _hasManyChecker.firstAnnotationOf(field);
      if (hasMany != null) {
        final reader = ConstantReader(hasMany);
        final typeMatch = RegExp(
          r'<(.+?)>',
        ).firstMatch(hasMany.type!.getDisplayString());
        final relatedType = typeMatch?.group(1) ?? 'dynamic';
        final foreignKey = reader.read('foreignKey').stringValue;
        final localKey = reader.read('localKey').stringValue;
        final cascadeDelete = reader.read('cascadeDelete').stringValue;
        return "HasMany<$relatedType>(this, '$foreignKey', localKey: '$localKey', cascadeDeleteBehavior: CascadeDeleteBehavior.$cascadeDelete)";
      }

      final hasOne = _hasOneChecker.firstAnnotationOf(field);
      if (hasOne != null) {
        final reader = ConstantReader(hasOne);
        final typeMatch = RegExp(
          r'<(.+?)>',
        ).firstMatch(hasOne.type!.getDisplayString());
        final relatedType = typeMatch?.group(1) ?? 'dynamic';
        final foreignKey = reader.read('foreignKey').stringValue;
        final localKey = reader.read('localKey').stringValue;
        final cascadeDelete = reader.read('cascadeDelete').stringValue;
        return "HasOne<$relatedType>(this, '$foreignKey', localKey: '$localKey', cascadeDeleteBehavior: CascadeDeleteBehavior.$cascadeDelete)";
      }

      final manyToMany = _manyToManyChecker.firstAnnotationOf(field);
      if (manyToMany != null) {
        final reader = ConstantReader(manyToMany);
        final typeMatch = RegExp(
          r'<(.+?),\s*(.+?)>',
        ).firstMatch(manyToMany.type!.getDisplayString());
        final relatedType = typeMatch?.group(1) ?? 'dynamic';
        final pivotType = typeMatch?.group(2) ?? 'dynamic';
        final thisForeignKey = reader.read('thisForeignKey').stringValue;
        final otherForeignKey = reader.read('otherForeignKey').stringValue;
        final thisLocalKey = reader.read('thisLocalKey').stringValue;
        final otherLocalKey = reader.read('otherLocalKey').stringValue;
        final cascadeDelete = reader.read('cascadeDelete').stringValue;

        return "ManyToMany<$relatedType>("
            "this, "
            "$pivotType, "
            "'$thisForeignKey', "
            "'$otherForeignKey', "
            "thisLocalKey: '$thisLocalKey', "
            "otherLocalKey: '$otherLocalKey', "
            "cascadeDeleteBehavior: CascadeDeleteBehavior.$cascadeDelete)";
      }
    } catch (_) {}

    return null;
  }

  void _generateQueryBuilder(
    StringBuffer buffer,
    String className,
    List<dynamic> fields,
  ) {
    buffer.writeln('\n// Type-safe query builder extension');
    buffer.writeln(
      'extension ${className}Query on DatumQueryBuilder<$className> {',
    );

    for (final field in fields) {
      final fieldName = _getElementName(field);

      if (_hasRelationAnnotationOnField(field)) {
        final relationName = fieldName.startsWith('_')
            ? fieldName.substring(1)
            : fieldName;
        final methodName = 'with${_capitalize(relationName)}';
        buffer.writeln('  DatumQueryBuilder<$className> $methodName() {');
        buffer.writeln("    withRelated(['$relationName']);");
        buffer.writeln('    return this;');
        buffer.writeln('  }');
        continue;
      }

      final mapKey = _getMapKey(field);
      final type = field.type.getDisplayString();
      final typeElement = field.type.element;
      final isEnum = typeElement != null && typeElement.kind.name == 'ENUM';

      // clean type
      var baseType = type.endsWith('?')
          ? type.substring(0, type.length - 1)
          : type;

      // Determine parameter type
      String paramType = baseType;

      bool needsConversion =
          [
            'DateTime',
            'Duration',
            'Uri',
            'BigInt',
            'Color',
          ].contains(baseType) ||
          isEnum;

      String convert(String v) {
        if (baseType == 'DateTime') return '$v.millisecondsSinceEpoch';
        if (baseType == 'Duration') return '$v.inMicroseconds';
        if (baseType == 'Uri' || baseType == 'BigInt') return '$v.toString()';
        if (baseType == 'Color') return '$v.toARGB32()';
        if (isEnum) return '$v.name';
        return v;
      }

      final isNumeric = [
        'int',
        'double',
        'num',
        'Duration',
        'Color',
        'DateTime',
      ].contains(baseType);
      final isString = ['String', 'Uri', 'BigInt'].contains(baseType) || isEnum;
      final isBool = baseType == 'bool';

      final methodName = 'where${_capitalize(fieldName)}';

      if (isNumeric || isString || isBool) {
        buffer.writeln('  DatumQueryBuilder<$className> $methodName({');

        // Define parameters
        final pType = '$paramType?';
        buffer.writeln('    $pType isEqualTo,');
        buffer.writeln('    $pType isNotEqualTo,');

        if (isNumeric) {
          buffer.writeln('    $pType isGreaterThan,');
          buffer.writeln('    $pType isGreaterThanOrEqualTo,');
          buffer.writeln('    $pType isLessThan,');
          buffer.writeln('    $pType isLessThanOrEqualTo,');
          if (!isBool) buffer.writeln('    List<$paramType>? between,');
        }

        if ([isNumeric, isString].contains(true) && !isBool) {
          buffer.writeln('    List<$paramType>? isIn,');
          buffer.writeln('    List<$paramType>? isNotIn,');
        }

        if (isString && !isEnum) {
          final sType = 'String?';
          buffer.writeln('    $sType contains,');
          buffer.writeln('    $sType containsIgnoreCase,');
          buffer.writeln('    $sType startsWith,');
          buffer.writeln('    $sType endsWith,');
          buffer.writeln('    $sType matches,');
        }

        buffer.writeln('  }) {');

        // Helper to generate call (v is the param name)
        String genCall(String paramName, String opArg) {
          String val = paramName;
          if (['isIn', 'isNotIn', 'between'].contains(opArg)) {
            if (needsConversion) {
              // Map items
              val = '$paramName.map((e) => ${convert('e')}).toList()';
            }
          } else {
            if (needsConversion) {
              val = convert(paramName);
            }
          }

          return "    if ($paramName != null) {\n      where('$mapKey', $opArg: $val);\n    }";
        }

        buffer.writeln(genCall('isEqualTo', 'isEqualTo'));
        buffer.writeln(genCall('isNotEqualTo', 'isNotEqualTo'));

        if (isNumeric) {
          buffer.writeln(genCall('isGreaterThan', 'isGreaterThan'));
          buffer.writeln(
            genCall('isGreaterThanOrEqualTo', 'isGreaterThanOrEqualTo'),
          );
          buffer.writeln(genCall('isLessThan', 'isLessThan'));
          buffer.writeln(genCall('isLessThanOrEqualTo', 'isLessThanOrEqualTo'));
          if (!isBool) buffer.writeln(genCall('between', 'between'));
        }

        if ([isNumeric, isString].contains(true) && !isBool) {
          buffer.writeln(genCall('isIn', 'isIn'));
          buffer.writeln(genCall('isNotIn', 'isNotIn'));
        }

        if (isString && !isEnum) {
          buffer.writeln(genCall('contains', 'contains'));
          buffer.writeln(genCall('containsIgnoreCase', 'containsIgnoreCase'));
          buffer.writeln(genCall('startsWith', 'startsWith'));
          buffer.writeln(genCall('endsWith', 'endsWith'));
          buffer.writeln(genCall('matches', 'matches'));
        }

        buffer.writeln('    return this;');
        buffer.writeln('  }');

        // OrderBy
        if (!isBool) {
          final sortMethodName = 'orderBy${_capitalize(fieldName)}';
          buffer.writeln(
            '  DatumQueryBuilder<$className> $sortMethodName({bool descending = false}) {',
          );
          buffer.writeln("    orderBy('$mapKey', descending: descending);");
          buffer.writeln('    return this;');
          buffer.writeln('  }');
        }
      }
    }
    buffer.writeln('}');
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
