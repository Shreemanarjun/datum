import 'package:test/test.dart';

import 'helpers/build_helper.dart';

const String _plainMixinEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable()
class Note extends DatumEntity {
  final String id;
  final String title;

  @DatumIgnore(equality: true)
  final String cachedSummary;

  const Note({required this.id, required this.title, this.cachedSummary = ''});
}
''';

const String _relationalMixinEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

class Author extends DatumEntity {
  const Author();
}

class Tag extends DatumEntity {
  const Tag();
}

@DatumSerializable()
class Article extends RelationalDatumEntity {
  final String id;
  final String authorId;

  @BelongsToRelation<Author>('authorId')
  final Author? _author = null;

  @HasManyRelation<Tag>('articleId')
  final List<Tag>? _tags = null;

  @HasOneRelation<Author>('articleId')
  final Author? editor = null;

  const Article({required this.id, required this.authorId});
}
''';

void main() {
  group('mixin generation (default generateMixin: true)', () {
    late String output;
    late Iterable<String> logMessages;

    setUpAll(() async {
      final result = await generate(_plainMixinEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(result.output, isNotNull);
      output = result.output!;
      logMessages = result.logMessages.toList();
    });

    test('emits mixin on DatumEntity with ignore comment', () {
      expect(output, containsCode('// ignore: unused_element'));
      expect(output, containsCode(r'mixin _$NoteMixin on DatumEntity {'));
    });

    test('mixin overrides toDatumMap and diff via extension methods', () {
      expect(
        output,
        containsCode(
          '@override Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) { return (this as Note).datumToMap(target: target); }',
        ),
      );
      expect(
        output,
        containsCode(
          '@override Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) { return (this as Note).datumDiff(oldVersion); }',
        ),
      );
    });

    test('non-relational copyWith is not marked @override', () {
      expect(
        output,
        containsCode(
          'DatumEntity copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) { return (this as Note).copyWithAll(',
        ),
      );
      expect(output, isNot(containsCode('@override DatumEntity copyWith({')));
    });

    test('mixin overrides ==, hashCode and toString', () {
      expect(
        output,
        containsCode(
          'return other is Note && (this as Note).datumEquals(other);',
        ),
      );
      expect(
        output,
        containsCode('int get hashCode => (this as Note).datumHashCode;'),
      );
      expect(output, containsCode(r"return 'Note(${map.toString()})';"));
    });

    test('props excludes equality-ignored fields', () {
      expect(output, containsCode('List<Object?> get props => ['));
      expect(output, containsCode('(this as Note).id,'));
      expect(output, containsCode('(this as Note).title,'));
      expect(output, isNot(containsCode('(this as Note).cachedSummary,')));
    });

    test('emits toMap/toJson helpers and factory extension', () {
      expect(
        output,
        containsCode('Map<String, dynamic> toMap() => toDatumMap();'),
      );
      expect(
        output,
        containsCode('String toJson() => DatumJsonUtils.encode(toDatumMap());'),
      );
      expect(output, containsCode('extension NoteFactory on Note {'));
      expect(
        output,
        containsCode(
          r'static Note fromMap(Map<String, dynamic> map) { return _$NoteFromMap(map); }',
        ),
      );
      expect(
        output,
        containsCode(
          'static Note fromJson(String source) { return fromMap(DatumJsonUtils.decode(source) as Map<String, dynamic>); }',
        ),
      );
    });

    test('no relations block for plain DatumEntity mixin', () {
      expect(output, isNot(containsCode('_cachedRelations')));
      expect(output, isNot(containsCode('datumRelations')));
    });

    test('emits the mixin documentation comment', () {
      // Note: the generator also emits a log.info about mixin usage, but
      // builder-internal logs are not forwarded by testBuilder, so assert on
      // the generated comment instead.
      expect(
        output,
        containsCode('// Mixin to provide all required method implementations'),
      );
      expect(logMessages, isNotEmpty);
    });
  });

  group('relational mixin generation', () {
    late String output;

    setUpAll(() async {
      final result = await generate(_relationalMixinEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(result.output, isNotNull);
      output = result.output!;
    });

    test('mixin is on RelationalDatumEntity with @override copyWith', () {
      expect(
        output,
        containsCode(r'mixin _$ArticleMixin on RelationalDatumEntity {'),
      );
      expect(
        output,
        containsCode('@override RelationalDatumEntity copyWith({'),
      );
    });

    test('generates getter/setter for private single relation field', () {
      expect(output, containsCode('/// Get the related entity'));
      expect(
        output,
        containsCode(
          "Author? get author { final value = relations['author']?.value; if (value is Author?) return value; return (this as Article)._author; }",
        ),
      );
      expect(output, containsCode('/// Set the related entity'));
      expect(
        output,
        containsCode(
          "set author(Author? value) { if (this is Article) { relations['author']?.setRaw(value); } }",
        ),
      );
    });

    test('generates getter/setter for private list relation field', () {
      expect(output, containsCode('/// Get the related entities'));
      expect(
        output,
        containsCode(
          "List<Tag>? get tags { final value = relations['tags']?.value; if (value is List<Tag>?) return value; return (this as Article)._tags; }",
        ),
      );
      expect(output, containsCode('/// Set the related entities'));
    });

    test('public relation fields get no mixin getter/setter', () {
      expect(output, isNot(containsCode('get editor {')));
      expect(output, isNot(containsCode('set editor(')));
    });

    test('caches relations map', () {
      expect(
        output,
        containsCode(
          'late final Map<String, Relation> _cachedRelations = (this as Article).datumRelations;',
        ),
      );
      expect(
        output,
        containsCode(
          '@override Map<String, Relation> get relations => _cachedRelations;',
        ),
      );
    });
  });
}
