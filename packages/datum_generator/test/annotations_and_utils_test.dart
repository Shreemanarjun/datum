import 'package:build/build.dart';
import 'package:datum_generator/datum_generator.dart';
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';

void main() {
  group('datumBuilder factory', () {
    test('returns a SharedPartBuilder producing .datum.g.part files', () {
      final builder = datumBuilder(BuilderOptions.empty);
      expect(builder, isA<SharedPartBuilder>());
      expect(builder.buildExtensions['.dart'], contains('.datum.g.part'));
    });
  });

  group('annotation defaults', () {
    test('DatumSerializable defaults', () {
      final annotation = DatumSerializable();
      expect(annotation.tableName, isNull);
      expect(annotation.generateMixin, isTrue);
      expect(annotation.strictNullChecks, isFalse);

      final custom = DatumSerializable(
        tableName: 'things',
        generateMixin: false,
        strictNullChecks: true,
      );
      expect(custom.tableName, 'things');
      expect(custom.generateMixin, isFalse);
      expect(custom.strictNullChecks, isTrue);
    });

    test('DatumIgnore defaults', () {
      final annotation = DatumIgnore();
      expect(annotation.copyWith, isFalse);
      expect(annotation.equality, isFalse);
      expect(annotation.fromMap, isTrue);
      expect(annotation.toMap, isTrue);
    });

    test('DatumField defaults', () {
      final annotation = DatumField();
      expect(annotation.name, isNull);
      expect(annotation.fromGenerator, isNull);
      expect(annotation.toGenerator, isNull);

      final custom = DatumField(
        name: 'a',
        fromGenerator: 'from(%DATA_PROPERTY%)',
        toGenerator: 'to(%DATA_PROPERTY%)',
      );
      expect(custom.name, 'a');
      expect(custom.fromGenerator, 'from(%DATA_PROPERTY%)');
      expect(custom.toGenerator, 'to(%DATA_PROPERTY%)');
    });

    test('BelongsToRelation defaults', () {
      final relation = BelongsToRelation<Object>('userId');
      expect(relation.foreignKey, 'userId');
      expect(relation.localKey, 'id');
      expect(relation.cascadeDelete, 'none');
    });

    test('HasManyRelation defaults', () {
      final relation = HasManyRelation<Object>('userId');
      expect(relation.foreignKey, 'userId');
      expect(relation.localKey, 'id');
      expect(relation.cascadeDelete, 'none');
    });

    test('HasOneRelation defaults', () {
      final relation = HasOneRelation<Object>('userId');
      expect(relation.foreignKey, 'userId');
      expect(relation.localKey, 'id');
      expect(relation.cascadeDelete, 'none');
    });

    test('ManyToManyRelation defaults', () {
      final relation = ManyToManyRelation<Object, Object>(
        pivotEntity: Object,
        thisForeignKey: 'postId',
        otherForeignKey: 'tagId',
      );
      expect(relation.pivotEntity, Object);
      expect(relation.thisForeignKey, 'postId');
      expect(relation.otherForeignKey, 'tagId');
      expect(relation.thisLocalKey, 'id');
      expect(relation.otherLocalKey, 'id');
      expect(relation.cascadeDelete, 'none');
    });
  });

  group('DatumJsonUtils', () {
    test('encodes values to JSON', () {
      expect(DatumJsonUtils.encode({'a': 1}), '{"a":1}');
      expect(DatumJsonUtils.encode([1, 2, 3]), '[1,2,3]');
      expect(DatumJsonUtils.encode(null), 'null');
    });

    test('decodes JSON strings', () {
      expect(DatumJsonUtils.decode('{"a":1}'), {'a': 1});
      expect(DatumJsonUtils.decode('[1,2,3]'), [1, 2, 3]);
      expect(DatumJsonUtils.decode('null'), isNull);
    });
  });
}
