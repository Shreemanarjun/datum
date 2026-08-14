import 'package:test/test.dart';

import 'helpers/build_helper.dart';

const String _relationalEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

class User extends DatumEntity {
  const User();
}

class Post extends DatumEntity {
  const Post();
}

class Profile extends DatumEntity {
  const Profile();
}

class Tag extends DatumEntity {
  const Tag();
}

class PostTag extends DatumEntity {
  const PostTag();
}

@DatumSerializable(generateMixin: false)
class Post2 extends RelationalDatumEntity {
  final String id;
  final String userId;

  @BelongsToRelation<User>('userId', localKey: 'remoteId', cascadeDelete: 'cascade')
  final User? _owner = null;

  @HasManyRelation<Post>('parentId')
  final List<Post>? _children = null;

  @HasOneRelation<Profile>('postId', localKey: 'profileKey', cascadeDelete: 'restrict')
  final Profile? _profile = null;

  @ManyToManyRelation<Tag, PostTag>(
    pivotEntity: PostTag,
    thisForeignKey: 'postId',
    otherForeignKey: 'tagId',
    thisLocalKey: 'localId',
    otherLocalKey: 'remoteId',
    cascadeDelete: 'setNull',
  )
  final List<Tag>? tags = null;

  const Post2({required this.id, required this.userId});
}
''';

const String _relationalNoRelations = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(generateMixin: false)
class Standalone extends RelationalDatumEntity {
  final String id;
  const Standalone({required this.id});
}
''';

const String _deepHierarchy = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

abstract class BaseModel extends RelationalDatumEntity {
  const BaseModel();
}

@DatumSerializable(generateMixin: false)
class Grandchild extends BaseModel {
  final String id;
  const Grandchild({required this.id});
}
''';

void main() {
  group('relational entity with all relation kinds', () {
    late String output;

    setUpAll(() async {
      final result = await generate(_relationalEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(result.output, isNotNull);
      output = result.output!;
    });

    test('generates datumRelations map with public names', () {
      expect(
        output,
        containsCode('Map<String, Relation> get datumRelations => {'),
      );
    });

    test('BelongsTo relation with snake_cased keys and cascade behavior', () {
      expect(
        output,
        containsCode(
          "'owner': BelongsTo<User>(this, 'user_id', localKey: 'remote_id', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade)..setRaw(_owner),",
        ),
      );
    });

    test('HasMany relation with defaults', () {
      expect(
        output,
        containsCode(
          "'children': HasMany<Post>(this, 'parent_id', localKey: 'id', cascadeDeleteBehavior: CascadeDeleteBehavior.none)..setRaw(_children),",
        ),
      );
    });

    test('HasOne relation with custom local key', () {
      expect(
        output,
        containsCode(
          "'profile': HasOne<Profile>(this, 'post_id', localKey: 'profile_key', cascadeDeleteBehavior: CascadeDeleteBehavior.restrict)..setRaw(_profile),",
        ),
      );
    });

    test('ManyToMany relation with pivot type and all keys', () {
      expect(
        output,
        containsCode(
          "'tags': ManyToMany<Tag>(this, PostTag, 'post_id', 'tag_id', thisLocalKey: 'local_id', otherLocalKey: 'remote_id', cascadeDeleteBehavior: CascadeDeleteBehavior.setNull)..setRaw(tags),",
        ),
      );
    });

    test('relation fields excluded from serialization and fromMap', () {
      expect(output, isNot(containsCode("'_owner'")));
      expect(output, isNot(containsCode("_owner: map[")));
      expect(output, isNot(containsCode("tags: map[")));
    });

    test('relation fields excluded from copyWithAll and equality', () {
      expect(output, isNot(containsCode('_owner ?? this._owner')));
      expect(output, isNot(containsCode('other._owner')));
      expect(output, isNot(containsCode('tags ?? this.tags')));
    });

    test('query builder skips relation fields entirely', () {
      // The generator builds the query extension from serializable fields,
      // which already exclude relation-annotated fields, so no whereX/withX
      // methods are generated for them.
      expect(
        output,
        containsCode('extension Post2Query on DatumQueryBuilder<Post2>'),
      );
      expect(output, isNot(containsCode('withOwner')));
      expect(output, isNot(containsCode('withChildren')));
      expect(output, isNot(containsCode('withProfile')));
      expect(output, isNot(containsCode('withTags')));
      expect(output, isNot(containsCode('withRelated')));
    });
  });

  group('relational entity without relation fields', () {
    test('still generates an (empty) datumRelations map', () async {
      final result = await generate(_relationalNoRelations);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(
        result.output,
        containsCode('Map<String, Relation> get datumRelations => {};'),
      );
    });
  });

  group('supertype detection', () {
    test('walks superclass chain to find RelationalDatumEntity', () async {
      final result = await generate(_deepHierarchy);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(
        result.output,
        containsCode('Map<String, Relation> get datumRelations => {};'),
      );
    });
  });
}
