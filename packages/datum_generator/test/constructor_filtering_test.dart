import 'package:test/test.dart';

import 'helpers/build_helper.dart';

const String _derivedFieldEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class Derived extends DatumEntity {
  final String id;
  final String userId;
  final String name;

  const Derived({required this.id, required this.name}) : userId = id;
}
''';

const String _multiCtorEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class Multi extends DatumEntity {
  final String a;
  final String b;

  const Multi({required this.a}) : b = 'derived';
  const Multi.full({required this.a, required this.b});
}
''';

const String _namedCtorOnlyEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class NamedOnly extends DatumEntity {
  final String a;

  const NamedOnly.create({required this.a});
}
''';

const String _mixinTarget = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
mixin Blob {
  String label = 'blob';

  String get virtualName => label;
}
''';

const String _metadataOnlyEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class MetaOnly extends DatumEntity {
  final DateTime modifiedAt;
  final int version;

  const MetaOnly({required this.modifiedAt, required this.version});
}
''';

const String _ignoreCombinationsEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class Ignores extends DatumEntity {
  final String id;

  @DatumIgnore(copyWith: true, equality: true, fromMap: false, toMap: false)
  final String token;

  @DatumIgnore(fromMap: true, toMap: false)
  final String writeOnly;

  const Ignores({required this.id, required this.token, this.writeOnly = ''});
}
''';

const String _staticFieldsEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class WithStatics extends DatumEntity {
  static const String kind = 'static-entity';
  static int counter = 0;

  final String id;

  String get derived => id.toUpperCase();

  const WithStatics({required this.id});
}
''';

void main() {
  group('derived (non-constructor) fields', () {
    late String output;

    setUpAll(() async {
      final result = await generate(_derivedFieldEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      output = result.output!;
    });

    test('derived field serialized in toMap but not passed to constructor', () {
      expect(output, containsCode("'user_id': userId,"));
      expect(output, isNot(containsCode('userId: ')));
    });

    test('copyWithAll omits derived field parameter', () {
      expect(output, containsCode('Derived copyWithAll({'));
      expect(output, isNot(containsCode('String? userId,')));
      expect(output, containsCode('id: id ?? this.id,'));
      expect(output, containsCode('name: name ?? this.name,'));
    });
  });

  group('multiple constructors', () {
    test('uses the unnamed constructor parameter list', () async {
      final result = await generate(_multiCtorEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = result.output!;
      // `b` is only a parameter of the named ctor, so it must not be passed.
      expect(output, containsCode('a: a ?? this.a,'));
      expect(output, isNot(containsCode('b: b ?? this.b,')));
      expect(output, isNot(containsCode("b: (map['b']")));
      // But b still serializes.
      expect(output, containsCode("'b': b,"));
    });
  });

  group('named-only constructor', () {
    test('falls back to first constructor for parameter names', () async {
      final result = await generate(_namedCtorOnlyEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = result.output!;
      expect(output, containsCode('a: a ?? this.a,'));
      expect(
        output,
        containsCode("a: (map['a'] ?? map['a'] ?? '') as String,"),
      );
    });
  });

  group('mixin declaration target', () {
    test(
      'generates with no constructor info (all fields treated as params)',
      () async {
        final result = await generate(_mixinTarget);
        expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
        final output = result.output!;
        expect(output, containsCode(r'extension $BlobDatum on Blob'));
        expect(output, containsCode("static const String tableName = 'blob';"));
      },
    );
  });

  group('metadata-only entity', () {
    late String output;

    setUpAll(() async {
      final result = await generate(_metadataOnlyEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      output = result.output!;
    });

    test('hasChanges is constant false when no non-metadata fields exist', () {
      expect(output, containsCode('final hasChanges = false;'));
    });

    test('diff has no old cast when all fields are excluded', () {
      expect(
        output,
        isNot(containsCode('final old = oldVersion as MetaOnly;')),
      );
      expect(output, containsCode('final changes = <String, dynamic>{};'));
      // modifiedAt field exists, so the metadata stamp block is emitted.
      expect(
        output,
        containsCode("changes['modified_at'] = modifiedAt.toIso8601String();"),
      );
    });
  });

  group('DatumIgnore combinations', () {
    late String output;

    setUpAll(() async {
      final result = await generate(_ignoreCombinationsEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      output = result.output!;
    });

    test('copyWith-ignored ctor param is forwarded as bare name', () {
      expect(output, isNot(containsCode('String? token,')));
      expect(output, containsCode('token: token,'));
      expect(output, isNot(containsCode('token: token ?? this.token,')));
    });

    test('equality-ignored field excluded from == and hashCode', () {
      expect(output, isNot(containsCode('other.token == token')));
      expect(output, isNot(containsCode('token.hashCode')));
    });

    test('fromMap/toMap: false keeps field in serialization round-trip', () {
      expect(output, containsCode("'token': token,"));
      expect(
        output,
        containsCode("token: (map['token'] ?? map['token'] ?? '') as String,"),
      );
    });

    test(
      'fromMap: true, toMap: false serializes but skips constructor arg',
      () {
        expect(output, containsCode("'write_only': writeOnly,"));
        expect(output, isNot(containsCode("writeOnly: (map['write_only']")));
        expect(output, isNot(containsCode("writeOnly: map['write_only']")));
      },
    );
  });

  group('multiple named-only constructors', () {
    test('falls back to the first constructor when none is unnamed', () async {
      final result = await generate('''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class Dual extends DatumEntity {
  final String x;
  final String y;

  const Dual.a({required this.x}) : y = '';
  const Dual.b({required this.x, required this.y});
}
''');
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = result.output!;
      // Parameters come from the first constructor (`Dual.a`), so `y` is not
      // a constructor argument.
      expect(output, containsCode('x: x ?? this.x,'));
      expect(output, isNot(containsCode('y: y ?? this.y,')));
      expect(output, isNot(containsCode("y: (map['y']")));
      // y still serializes.
      expect(output, containsCode("'y': y,"));
    });
  });

  group('extension target (no constructors at all)', () {
    test('generation proceeds but output cannot be formatted', () async {
      // Extensions expose `fields` but have no `constructors` getter, so the
      // generator falls through its constructor-introspection fallbacks and
      // produces degenerate (unformattable) code, failing the build.
      final result = await generate('''
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
extension Shouty on String {
  static const String suffix = '!';
}
''');
      expect(result.succeeded, isFalse);
    });
  });

  group('static and synthetic fields', () {
    test('static fields and getters are not serialized', () async {
      final result = await generate(_staticFieldsEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final output = result.output!;
      expect(output, isNot(containsCode("'kind'")));
      expect(output, isNot(containsCode("'counter'")));
      expect(output, isNot(containsCode("'derived'")));
      expect(output, containsCode("'id': id,"));
    });
  });
}
