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

/// Generated member families a field can opt out of via `@DatumIgnore`.
enum IgnoreScope { toMap, fromMap, equality, copyWith }

/// Everything the emitters need to know about one entity field, read from
/// the analyzer element exactly once.
final class FieldInfo {
  const FieldInfo({
    required this.name,
    required this.type,
    required this.mapKey,
    required this.isEnum,
    required this.isRelation,
    this.toGenerator,
    this.fromGenerator,
    this.relationInfo,
    this.ignored = const {},
    this.diff,
    this.deviceOnly = false,
  });

  factory FieldInfo.of(dynamic field) {
    final typeElement = field.type.element;
    final isRelation = _hasRelationAnnotation(field);
    return FieldInfo(
      name: readElementName(field),
      type: field.type.getDisplayString() as String,
      mapKey: _mapKeyOf(field),
      isEnum: typeElement != null && typeElement.kind.name == 'ENUM',
      isRelation: isRelation,
      toGenerator: _readFieldString(field, 'toGenerator'),
      fromGenerator: _readFieldString(field, 'fromGenerator'),
      relationInfo: isRelation ? _relationInfoOf(field) : null,
      diff: _readFieldBool(field, 'diff'),
      deviceOnly: _readFieldBool(field, 'deviceOnly') ?? false,
      ignored: {
        for (final scope in IgnoreScope.values)
          if (_isIgnored(field, scope)) scope,
      },
    );
  }

  /// `@DatumField(deviceOnly: true)`: in the local map only.
  final bool deviceOnly;

  final String name;

  /// Display string of the declared type, e.g. `DateTime?`.
  final String type;
  final String mapKey;
  final bool isEnum;
  final bool isRelation;
  final String? toGenerator;
  final String? fromGenerator;

  /// Constructor expression for the relation object (relation fields only).
  final String? relationInfo;
  final Set<IgnoreScope> ignored;

  /// `@DatumField(diff:)` override; null = the generator's default rule.
  final bool? diff;

  bool get isNullable => type.endsWith('?');

  /// [type] without a trailing `?`.
  String get baseType => isNullable ? type.substring(0, type.length - 1) : type;

  bool get isCollection =>
      type.startsWith('List') ||
      type.startsWith('Map') ||
      type.startsWith('Set');
}

String readElementName(dynamic e) {
  try {
    final name = e.name;
    if (name != null) return name as String;
  } catch (_) {}
  // Cross-analyzer-version fallbacks (supported range >=7.0.0 <9.0.0): on
  // 8.x every element handed to this method has a working non-null `name`.
  // coverage:ignore-start
  try {
    final name = e.displayName;
    if (name != null) return name as String;
  } catch (_) {}
  return e.toString();
  // coverage:ignore-end
}

/// Instance fields of the annotated class, across analyzer versions.
List<dynamic> readClassFields(dynamic element) {
  try {
    return (element.fields as List).toList();
  } catch (_) {
    try {
      return (element.fields2 as List).toList();
    } catch (_) {
      throw InvalidGenerationSourceError(
        'DatumSerializable can only be applied to classes (failed to access fields).',
      );
    }
  }
}

String camelToSnake(String name) {
  if (name.isEmpty) return name;
  final result = StringBuffer();
  for (var i = 0; i < name.length; i++) {
    final char = name[i];
    if (char.toUpperCase() == char && char.toLowerCase() != char && i > 0) {
      result.write('_');
    }
    result.write(char.toLowerCase());
  }
  return result.toString();
}

String lowerCamel(String name) =>
    name.isEmpty ? name : name[0].toLowerCase() + name.substring(1);

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Whether a field may be passed to the primary constructor. An empty
/// [ctorParams] means "unknown", so every field is accepted (#26).
bool acceptsCtorArg(Set<String> ctorParams, String name) =>
    ctorParams.isEmpty || ctorParams.contains(name);

bool isRelationalEntity(dynamic element) {
  var current = element;
  while (current.supertype != null) {
    final superElement = current.supertype!.element;
    if (readElementName(superElement) == 'RelationalDatumEntity') return true;
    current = superElement;
  }
  return false;
}

/// Best-effort set of the primary constructor's parameter names.
///
/// Used so generated constructor calls (`copyWithAll`, `fromMap`) never pass
/// arguments for fields that are NOT constructor parameters — e.g. a `userId`
/// assigned via `: userId = id` — which would produce invalid code (#26).
/// Returns an empty set when it cannot be determined (analyzer version
/// differences), in which case callers fall back to passing all fields.
Set<String> constructorParamNames(dynamic element) {
  final ctors = _constructorsOf(element);
  if (ctors == null || ctors.isEmpty) return {};
  final params = _parametersOf(_primaryConstructor(ctors));
  return {for (final p in params ?? const []) ?_paramName(p)};
}

List<dynamic>? _constructorsOf(dynamic element) {
  try {
    return (element.constructors as List?)?.toList();
  } catch (_) {
    try {
      return (element.constructors2 as List?)?.toList();
    } catch (_) {
      return null;
    }
  }
}

dynamic _primaryConstructor(List<dynamic> ctors) {
  if (ctors.length == 1) return ctors.first;
  for (final c in ctors) {
    final name = _constructorName(c);
    if (name.isEmpty || name == 'new') return c;
  }
  return ctors.first;
}

String _constructorName(dynamic ctor) {
  try {
    return (ctor.name ?? '') as String;
  } catch (_) {
    return '';
  }
}

List<dynamic>? _parametersOf(dynamic ctor) {
  try {
    return (ctor.parameters as List?)?.toList();
  } catch (_) {
    try {
      return (ctor.formalParameters as List?)?.toList();
    } catch (_) {
      return null;
    }
  }
}

String? _paramName(dynamic param) {
  try {
    final n = param.name;
    return n is String && n.isNotEmpty ? n : null;
  } catch (_) {
    return null;
  }
}

bool _isIgnored(dynamic field, IgnoreScope scope) {
  // Older annotation versions lack per-scope flags: a bare @DatumIgnore then
  // means "skip serialization" (backward compatibility).
  final legacyDefault =
      scope == IgnoreScope.fromMap || scope == IgnoreScope.toMap;
  try {
    final annotation = _ignoreChecker.firstAnnotationOf(field);
    if (annotation == null) return false;
    try {
      final reader = ConstantReader(annotation).read(scope.name);
      return reader.isNull ? legacyDefault : reader.boolValue;
    } catch (_) {
      return legacyDefault;
    }
  } catch (_) {
    return false;
  }
}

String? _readFieldString(dynamic field, String property) {
  try {
    final annotation = _fieldChecker.firstAnnotationOf(field);
    if (annotation == null) return null;
    final value = ConstantReader(annotation).read(property);
    if (!value.isNull) return value.stringValue;
  } catch (_) {}
  return null;
}

bool? _readFieldBool(dynamic field, String property) {
  try {
    final annotation = _fieldChecker.firstAnnotationOf(field);
    if (annotation == null) return null;
    final value = ConstantReader(annotation).read(property);
    if (!value.isNull) return value.boolValue;
  } catch (_) {}
  return null;
}

String _mapKeyOf(dynamic field) =>
    _readFieldString(field, 'name') ?? camelToSnake(readElementName(field));

bool _hasRelationAnnotation(dynamic field) {
  try {
    return _belongsToChecker.hasAnnotationOf(field) ||
        _hasManyChecker.hasAnnotationOf(field) ||
        _hasOneChecker.hasAnnotationOf(field) ||
        _manyToManyChecker.hasAnnotationOf(field);
  } catch (_) {
    return false;
  }
}

const _singleRelations = [
  (_belongsToChecker, 'BelongsTo'),
  (_hasManyChecker, 'HasMany'),
  (_hasOneChecker, 'HasOne'),
];

String? _relationInfoOf(dynamic field) {
  try {
    for (final (checker, relation) in _singleRelations) {
      final annotation = checker.firstAnnotationOf(field);
      if (annotation != null) return _singleRelationInfo(annotation, relation);
    }
    final manyToMany = _manyToManyChecker.firstAnnotationOf(field);
    if (manyToMany != null) return _manyToManyInfo(manyToMany);
  } catch (_) {}
  return null;
}

String _singleRelationInfo(dynamic annotation, String relation) {
  final reader = ConstantReader(annotation);
  // Get types from the annotation instance itself
  final typeMatch = RegExp(
    r'<(.+?)>',
  ).firstMatch(annotation.type!.getDisplayString());
  final relatedType = typeMatch?.group(1) ?? 'dynamic';
  final foreignKey = camelToSnake(reader.read('foreignKey').stringValue);
  final localKey = camelToSnake(reader.read('localKey').stringValue);
  final cascadeDelete = reader.read('cascadeDelete').stringValue;
  return "$relation<$relatedType>(this, '$foreignKey', localKey: '$localKey', cascadeDeleteBehavior: CascadeDeleteBehavior.$cascadeDelete)";
}

String _manyToManyInfo(dynamic annotation) {
  final reader = ConstantReader(annotation);
  final typeMatch = RegExp(
    r'<(.+?),\s*(.+?)>',
  ).firstMatch(annotation.type!.getDisplayString());
  final relatedType = typeMatch?.group(1) ?? 'dynamic';
  final pivotType = typeMatch?.group(2) ?? 'dynamic';
  String key(String name) => camelToSnake(reader.read(name).stringValue);
  final cascadeDelete = reader.read('cascadeDelete').stringValue;

  return "ManyToMany<$relatedType>("
      "this, "
      "$pivotType, "
      "'${key('thisForeignKey')}', "
      "'${key('otherForeignKey')}', "
      "thisLocalKey: '${key('thisLocalKey')}', "
      "otherLocalKey: '${key('otherLocalKey')}', "
      "cascadeDeleteBehavior: CascadeDeleteBehavior.$cascadeDelete)";
}
