import 'field_info.dart';

String copyWithCode(String className) =>
    '''
  $className copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return copyWithAll(
      modifiedAt: modifiedAt,
      version: version,
      isDeleted: isDeleted,
    );
  }
''';

String copyWithAllCode(
  String className,
  List<FieldInfo> fields,
  Set<String> ctorParams,
) {
  // Only fields that are NOT ignored, NOT relations, and ARE constructor params.
  final copyable = fields
      .where(
        (f) =>
            !f.isRelation &&
            !f.ignored.contains(IgnoreScope.copyWith) &&
            acceptsCtorArg(ctorParams, f.name),
      )
      .toList();
  final copyableNames = {for (final f in copyable) f.name};

  final b = StringBuffer()..writeln('  $className copyWithAll({');
  for (final f in copyable) {
    // Make them all optional for copyWith
    b.writeln('    ${f.isNullable ? f.type : '${f.type}?'} ${f.name},');
  }
  b.writeln('  }) {');

  // Any changed field bumps the version automatically.
  final changeNames = copyableNames.where(
    (n) => n != 'modifiedAt' && n != 'version',
  );
  b
    ..writeln('    final hasChanges = ')
    ..write(
      changeNames.isEmpty
          ? 'false'
          : changeNames.map((n) => '$n != null').join(' || '),
    )
    ..writeln(';')
    ..writeln('    return $className(');
  for (final f in fields) {
    // Non-constructor fields are derived in the constructor and cannot be passed.
    if (f.isRelation || !acceptsCtorArg(ctorParams, f.name)) continue;
    b.writeln(switch (f.name) {
      'version' =>
        '      version: version ?? (hasChanges ? this.version + 1 : this.version),',
      final n when copyableNames.contains(n) => '      $n: $n ?? this.$n,',
      // Ignored from copyWith: the bare name resolves to the current value.
      final n => '      $n: $n,',
    });
  }
  return (b
        ..writeln('    );')
        ..writeln('  }'))
      .toString();
}

String equalityCode(String className, List<FieldInfo> fields) {
  final listEquals = '_${lowerCamel(className)}ListEquals';
  final comparisons = fields.map(
    (f) => f.type.startsWith('List')
        ? '$listEquals(other.${f.name}, ${f.name})'
        : 'other.${f.name} == ${f.name}',
  );
  final hashes = fields.map((f) => '${f.name}.hashCode');
  return '''

  bool datumEquals($className other) {
    if (identical(this, other)) return true;
    return ${comparisons.join(' &&\n        ')};
  }

  int get datumHashCode {
    return ${hashes.join(' ^\n        ')};
  }
''';
}

String relationsCode(List<FieldInfo> fields) {
  // Always generated for RelationalDatumEntity, even if empty.
  final b = StringBuffer()
    ..writeln('\n  Map<String, Relation> get datumRelations => {');
  for (final f in fields) {
    if (f.relationInfo case final info?) {
      b.writeln(
        "    '${f.name.startsWith('_') ? f.name.substring(1) : f.name}': $info..setRaw(${f.name}),",
      );
    }
  }
  return (b..writeln('  };')).toString();
}

String mixinCode(String className, List<FieldInfo> fields, bool isRelational) {
  final baseClass = isRelational ? 'RelationalDatumEntity' : 'DatumEntity';
  final props = fields
      .where((f) => !f.ignored.contains(IgnoreScope.equality) && !f.isRelation)
      .map((f) => '    (this as $className).${f.name},\n')
      .join();
  // Private relation fields get a public getter/setter so they are "used".
  final accessors = fields
      .where((f) => f.isRelation && f.name.startsWith('_'))
      .map((f) => _relationAccessors(className, f))
      .join();
  final cachedRelations = isRelational
      ? '''

  late final Map<String, Relation> _cachedRelations =
      (this as $className).datumRelations;

  @override
  Map<String, Relation> get relations => _cachedRelations;
'''
      : '';

  return '''

// Mixin to provide all required method implementations
// ignore: unused_element
mixin _\$${className}Mixin on $baseClass {
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return (this as $className).datumToMap(target: target);
  }

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    return (this as $className).datumDiff(oldVersion);
  }
${isRelational ? '\n  @override' : '\n'}
  $baseClass copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return (this as $className).copyWithAll(
      modifiedAt: modifiedAt,
      version: version,
      isDeleted: isDeleted,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is $className && (this as $className).datumEquals(other);
  }

  @override
  int get hashCode => (this as $className).datumHashCode;

  @override
  String toString() {
    final map = toDatumMap();
    return '$className(\${map.toString()})';
  }

  @override
  List<Object?> get props => [
$props  ];
$accessors$cachedRelations
  Map<String, dynamic> toMap() => toDatumMap();

  String toJson() => DatumJsonUtils.encode(toDatumMap());
}

// Extension to provide fromMap and fromJson factories
extension ${className}Factory on $className {
  static $className fromMap(Map<String, dynamic> map) {
    return _\$${className}FromMap(map);
  }

  static $className fromJson(String source) {
    return fromMap(DatumJsonUtils.decode(source) as Map<String, dynamic>);
  }
}
''';
}

String _relationAccessors(String className, FieldInfo f) {
  final publicName = f.name.substring(1);
  final type = f.type;
  final noun = type.startsWith('List') ? 'entities' : 'entity';
  return '''

  /// Get the related $noun
  $type get $publicName {
    final value = relations['$publicName']?.value;
    if (value is $type) return value;
    return (this as $className).${f.name};
  }

  /// Set the related $noun
  set $publicName($type value) {
    if (this is $className) {
      relations['$publicName']?.setRaw(value);
    }
  }
''';
}
