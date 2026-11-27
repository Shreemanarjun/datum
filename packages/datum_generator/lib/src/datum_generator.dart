import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'core/annotations.dart';
import 'generator/field_info.dart';
import 'generator/members.dart';
import 'generator/query_builder.dart';
import 'generator/serialization.dart';

class DatumGenerator extends GeneratorForAnnotation<DatumSerializable> {
  @override
  String generateForAnnotatedElement(
    dynamic element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    // Note: strict type check (element is ClassElement) sometimes fails due to
    // analyzer version mismatches in build environment. We trust source_gen here.
    final className = readElementName(element);
    final rawFields = readClassFields(element);

    final tableNameReader = annotation.read('tableName');
    final tableName = tableNameReader.isNull
        ? camelToSnake(className)
        : tableNameReader.stringValue;
    final generateMixin = _readFlag(annotation, 'generateMixin');
    final strictNullChecks = _readFlag(annotation, 'strictNullChecks');

    final fields = [
      for (final f in rawFields)
        if (!f.isStatic && !f.isSynthetic) FieldInfo.of(f),
    ];
    final serializable = fields
        .where((f) => !f.ignored.contains(IgnoreScope.toMap) && !f.isRelation)
        .toList();
    final equatable = fields
        .where(
          (f) => !f.isRelation && !f.ignored.contains(IgnoreScope.equality),
        )
        .toList();
    // The primary constructor's parameter names, so generated constructor
    // calls never pass non-constructor fields (#26).
    final ctorParams = constructorParamNames(element);
    final isRelational = isRelationalEntity(element);

    final buffer = StringBuffer()
      ..writeln('extension \$${className}Datum on $className {')
      ..writeln("  static const String tableName = '$tableName';")
      ..write(toDatumMapCode(serializable))
      ..write(diffCode(className, serializable))
      ..write(deviceOnlyKeysCode(serializable))
      ..write(copyWithCode(className))
      ..write(copyWithAllCode(className, fields, ctorParams))
      ..write(equalityCode(className, equatable))
      ..write(isRelational ? relationsCode(fields) : '')
      ..writeln('}');
    if (equatable.any((f) => f.type.startsWith('List'))) {
      buffer.write(listEqualsHelper(className));
    }
    buffer.write(fromMapCode(className, fields, ctorParams, strictNullChecks));
    if (generateMixin) {
      buffer.write(mixinCode(className, fields, isRelational));
      log.info(
        'Generated mixin for $className. Use it with: class $className extends ${isRelational ? 'RelationalDatumEntity' : 'DatumEntity'} with _\$${className}Mixin',
      );
    } else {
      log.fine(
        'Skipped mixin generation for $className. To enable, use: @DatumSerializable(generateMixin: true)',
      );
    }
    buffer.write(queryBuilderCode(className, serializable));
    return buffer.toString();
  }
}

bool _readFlag(ConstantReader annotation, String name) {
  final reader = annotation.read(name);
  return !reader.isNull && reader.boolValue;
}
