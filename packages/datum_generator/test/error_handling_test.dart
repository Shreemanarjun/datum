import 'package:test/test.dart';

import 'helpers/build_helper.dart';

const String _annotatedFunction = '''
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable()
void notAClass() {}
''';

const String _unresolvedFieldAnnotation = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class Fuzzy extends DatumEntity {
  @bogusAnnotation
  final String name;

  const Fuzzy({required this.name});
}
''';

/// DatumIgnore variant whose flags are nullable and default to null: reading a
/// property succeeds but `isNull` is true, exercising the isNull fallback.
const String _nullablePropsAnnotations = '''
import 'package:meta/meta_meta.dart';

@Target({TargetKind.classType})
class DatumSerializable {
  final String? tableName;
  final bool generateMixin;
  final bool strictNullChecks;
  const DatumSerializable({
    this.tableName,
    this.generateMixin = true,
    this.strictNullChecks = false,
  });
}

@Target({TargetKind.field})
class DatumIgnore {
  final bool? copyWith;
  final bool? equality;
  final bool? fromMap;
  final bool? toMap;
  const DatumIgnore({this.copyWith, this.equality, this.fromMap, this.toMap});
}

@Target({TargetKind.field})
class DatumField {
  final String? name;
  final String? fromGenerator;
  final String? toGenerator;
  const DatumField({this.name, this.fromGenerator, this.toGenerator});
}
''';

/// DatumIgnore variant with NO flags at all: reading a property throws,
/// exercising the catch fallback.
const String _missingPropsAnnotations = '''
import 'package:meta/meta_meta.dart';

@Target({TargetKind.classType})
class DatumSerializable {
  final String? tableName;
  final bool generateMixin;
  final bool strictNullChecks;
  const DatumSerializable({
    this.tableName,
    this.generateMixin = true,
    this.strictNullChecks = false,
  });
}

@Target({TargetKind.field})
class DatumIgnore {
  const DatumIgnore();
}
''';

/// Relation annotation variants that are NOT generic (so the `<...>` regex
/// finds nothing and falls back to `dynamic`) but keep all required keys.
const String _nonGenericRelationAnnotations = '''
import 'package:meta/meta_meta.dart';

@Target({TargetKind.classType})
class DatumSerializable {
  final String? tableName;
  final bool generateMixin;
  final bool strictNullChecks;
  const DatumSerializable({
    this.tableName,
    this.generateMixin = true,
    this.strictNullChecks = false,
  });
}

@Target({TargetKind.field})
class BelongsToRelation {
  final String foreignKey;
  final String localKey;
  final String cascadeDelete;
  const BelongsToRelation(
    this.foreignKey, {
    this.localKey = 'id',
    this.cascadeDelete = 'none',
  });
}

@Target({TargetKind.field})
class HasManyRelation {
  final String foreignKey;
  final String localKey;
  final String cascadeDelete;
  const HasManyRelation(
    this.foreignKey, {
    this.localKey = 'id',
    this.cascadeDelete = 'none',
  });
}

@Target({TargetKind.field})
class HasOneRelation {
  final String foreignKey;
  final String localKey;
  final String cascadeDelete;
  const HasOneRelation(
    this.foreignKey, {
    this.localKey = 'id',
    this.cascadeDelete = 'none',
  });
}

@Target({TargetKind.field})
class ManyToManyRelation {
  final Type pivotEntity;
  final String thisForeignKey;
  final String otherForeignKey;
  final String thisLocalKey;
  final String otherLocalKey;
  final String cascadeDelete;
  const ManyToManyRelation({
    required this.pivotEntity,
    required this.thisForeignKey,
    required this.otherForeignKey,
    this.thisLocalKey = 'id',
    this.otherLocalKey = 'id',
    this.cascadeDelete = 'none',
  });
}
''';

/// Relation annotation variant missing its required keys entirely: relation
/// detection succeeds but reading `foreignKey` throws, so the relation info
/// resolves to null and the entry is skipped.
const String _keylessRelationAnnotations = '''
import 'package:meta/meta_meta.dart';

@Target({TargetKind.classType})
class DatumSerializable {
  final String? tableName;
  final bool generateMixin;
  final bool strictNullChecks;
  const DatumSerializable({
    this.tableName,
    this.generateMixin = true,
    this.strictNullChecks = false,
  });
}

@Target({TargetKind.field})
class BelongsToRelation {
  const BelongsToRelation();
}
''';

void main() {
  group('invalid targets', () {
    test(
      'annotating a function fails with InvalidGenerationSourceError',
      () async {
        final result = await generate(_annotatedFunction);
        expect(result.succeeded, isFalse);
        expect(
          result.errors.join('\n') + result.logMessages.join('\n'),
          contains('DatumSerializable can only be applied to classes'),
        );
        expect(result.output, isNull);
      },
    );
  });

  group('unresolved field annotations', () {
    test('are tolerated and the field is treated as a plain field', () async {
      final result = await generate(_unresolvedFieldAnnotation);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = result.output!;
      expect(output, containsCode("'name': name,"));
      expect(
        output,
        containsCode("name: (map['name'] ?? map['name'] ?? '') as String,"),
      );
      expect(output, containsCode('name: name ?? this.name,'));
      expect(output, containsCode('other.name == name'));
    });
  });

  group('annotation compatibility fallbacks', () {
    const overridePath = 'datum_generator|lib/src/core/annotations.dart';

    test('nullable DatumIgnore flags fall back per-property', () async {
      final result = await generate(
        '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class Legacy extends DatumEntity {
  final String id;

  @DatumIgnore()
  final String hidden;

  const Legacy({required this.id, this.hidden = ''});
}
''',
        overrideAssets: {overridePath: _nullablePropsAnnotations},
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = result.output!;
      // fromMap/toMap default to ignored (backward compatible)...
      expect(output, isNot(containsCode("'hidden': hidden,")));
      expect(output, isNot(containsCode("hidden: (map['hidden']")));
      // ...but copyWith/equality default to kept.
      expect(output, containsCode('hidden: hidden ?? this.hidden,'));
      expect(output, containsCode('other.hidden == hidden'));
    });

    test('flag-less DatumIgnore falls back via catch', () async {
      final result = await generate(
        '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class Legacy2 extends DatumEntity {
  final String id;

  @DatumIgnore()
  final String hidden;

  const Legacy2({required this.id, this.hidden = ''});
}
''',
        overrideAssets: {overridePath: _missingPropsAnnotations},
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = result.output!;
      expect(output, isNot(containsCode("'hidden': hidden,")));
      expect(output, isNot(containsCode("hidden: (map['hidden']")));
      expect(output, containsCode('hidden: hidden ?? this.hidden,'));
      expect(output, containsCode('other.hidden == hidden'));
    });

    test('non-generic relation annotations degrade to dynamic type args', () async {
      final result = await generate(
        '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

class Pivot {
  const Pivot();
}

@DatumSerializable(generateMixin: false)
class Untyped extends RelationalDatumEntity {
  final String id;

  @BelongsToRelation('ownerId')
  final Object? _owner = null;

  @HasManyRelation('untypedId')
  final List<Object>? _items = null;

  @HasOneRelation('untypedId')
  final Object? _detail = null;

  @ManyToManyRelation(
    pivotEntity: Pivot,
    thisForeignKey: 'untypedId',
    otherForeignKey: 'otherId',
  )
  final List<Object>? _others = null;

  const Untyped({required this.id});
}
''',
        overrideAssets: {overridePath: _nonGenericRelationAnnotations},
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = result.output!;
      expect(
        output,
        containsCode(
          "'owner': BelongsTo<dynamic>(this, 'owner_id', localKey: 'id', cascadeDeleteBehavior: CascadeDeleteBehavior.none)..setRaw(_owner),",
        ),
      );
      expect(
        output,
        containsCode(
          "'items': HasMany<dynamic>(this, 'untyped_id', localKey: 'id', cascadeDeleteBehavior: CascadeDeleteBehavior.none)..setRaw(_items),",
        ),
      );
      expect(
        output,
        containsCode(
          "'detail': HasOne<dynamic>(this, 'untyped_id', localKey: 'id', cascadeDeleteBehavior: CascadeDeleteBehavior.none)..setRaw(_detail),",
        ),
      );
      expect(
        output,
        containsCode(
          "'others': ManyToMany<dynamic>(this, dynamic, 'untyped_id', 'other_id', thisLocalKey: 'id', otherLocalKey: 'id', cascadeDeleteBehavior: CascadeDeleteBehavior.none)..setRaw(_others),",
        ),
      );
    });

    test(
      'relation annotation without keys is skipped in datumRelations',
      () async {
        final result = await generate(
          '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class Keyless extends RelationalDatumEntity {
  final String id;

  @BelongsToRelation()
  final Object? _owner = null;

  const Keyless({required this.id});
}
''',
          overrideAssets: {overridePath: _keylessRelationAnnotations},
        );
        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        final output = result.output!;
        // Relation detected (field excluded from serialization) but no entry
        // could be built for it.
        expect(
          output,
          containsCode('Map<String, Relation> get datumRelations => {};'),
        );
        expect(output, isNot(containsCode('BelongsTo<')));
      },
    );
  });
}
