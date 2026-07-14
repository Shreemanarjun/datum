import 'dart:async';

import 'package:datum/datum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';
import '../mocks/test_entity.dart';

class Blog extends RelationalDatumEntity {
  Blog({required this.id}) : userId = 'u1';
  @override
  final String id;
  @override
  final String userId;
  @override
  DateTime get modifiedAt => DateTime(2024);
  @override
  DateTime get createdAt => DateTime(2024);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;
  late final Map<String, Relation> _relations = {'posts': HasMany<TestEntity>(this, 'blogId'), 'owner': BelongsTo<TestEntity>(this, 'ownerId')};
  @override
  Map<String, Relation> get relations => _relations;
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId};
  @override
  Blog copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Blog(id: id);
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => null;
}

/// Hand-written entity that opts into relation memoization via the mixin.
class MemoBlog extends RelationalDatumEntity with MemoizedRelations {
  MemoBlog({required this.id}) : userId = 'u1';
  @override
  final String id;
  @override
  final String userId;
  @override
  DateTime get modifiedAt => DateTime(2024);
  @override
  DateTime get createdAt => DateTime(2024);
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;
  @override
  Map<String, Relation> buildRelations() => {'posts': HasMany<TestEntity>(this, 'blogId')};
  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId};
  @override
  MemoBlog copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => MemoBlog(id: id);
  @override
  Map<String, dynamic>? diff(DatumEntityInterface old) => null;
}

void main() {
  group('manager.exists / manager.count', () {
    late MockLocalAdapter<TestEntity> local;
    late DatumManager<TestEntity> manager;

    setUp(() async {
      local = MockLocalAdapter<TestEntity>(fromJson: TestEntity.fromJson);
      final connectivity = MockConnectivityChecker();
      when(() => connectivity.isConnected).thenAnswer((_) async => true);
      when(() => connectivity.onStatusChange).thenAnswer((_) => const Stream<bool>.empty());
      manager = DatumManager<TestEntity>(
        localAdapter: local,
        remoteAdapter: MockRemoteAdapter<TestEntity>(fromJson: TestEntity.fromJson),
        connectivity: connectivity,
        datumConfig: const DatumConfig<TestEntity>(),
      );
      await manager.initialize();
    });

    tearDown(() => manager.dispose());

    test('exists reflects presence', () async {
      expect(await manager.exists('e1', userId: 'u1'), isFalse);
      local.addLocalItem('u1', TestEntity.create('e1', 'u1', 'A'));
      expect(await manager.exists('e1', userId: 'u1'), isTrue);
    });

    test('count without a query counts all for the user', () async {
      local.addLocalItem('u1', TestEntity.create('e1', 'u1', 'A'));
      local.addLocalItem('u1', TestEntity.create('e2', 'u1', 'B'));
      expect(await manager.count(userId: 'u1'), 2);
    });

    test('count with a query counts matches', () async {
      local.addLocalItem('u1', TestEntity(id: 'e1', userId: 'u1', name: 'A', value: 5, modifiedAt: DateTime(2024), createdAt: DateTime(2024), version: 1));
      local.addLocalItem('u1', TestEntity(id: 'e2', userId: 'u1', name: 'B', value: 1, modifiedAt: DateTime(2024), createdAt: DateTime(2024), version: 1));
      final q = (DatumQueryBuilder<TestEntity>()..where('value', isGreaterThanOrEqualTo: 3)).build();
      expect(await manager.count(query: q, userId: 'u1'), 1);
    });
  });

  group('DatumEither ergonomic getters (README example)', () {
    test('success / failure aliases match the documented usage', () {
      const ok = Success<Object, int>(42);
      const bad = Failure<Object, int>('boom');

      expect(ok.isFailure(), isFalse);
      expect(ok.success, 42);
      expect(ok.failure, isNull);

      expect(bad.isFailure(), isTrue);
      expect(bad.failure, 'boom');
      expect(bad.success, isNull);
    });
  });

  group('typed relation accessors', () {
    test('relatedList / relatedOne return typed loaded values', () {
      final blog = Blog(id: 'b1');
      (blog.relations['posts'] as HasMany).setRaw([TestEntity.create('p1', 'u1', 'Post')]);
      (blog.relations['owner'] as BelongsTo).setRaw(TestEntity.create('o1', 'u1', 'Owner'));

      final posts = blog.relatedList<TestEntity>('posts');
      expect(posts, hasLength(1));
      expect(posts!.first.id, 'p1');

      final owner = blog.relatedOne<TestEntity>('owner');
      expect(owner?.id, 'o1');
    });

    test('return null for unloaded / missing relations', () {
      final blog = Blog(id: 'b1');
      expect(blog.relatedList<TestEntity>('posts'), isNull);
      expect(blog.relatedOne<TestEntity>('owner'), isNull);
      expect(blog.relatedList<TestEntity>('nonexistent'), isNull);
    });
  });

  group('MemoizedRelations mixin (relation-caching footgun fix)', () {
    test('relations are memoized so setRaw persists', () {
      final blog = MemoBlog(id: 'b1');
      // Same map instance across calls (memoized) — mutations persist.
      expect(identical(blog.relations, blog.relations), isTrue);

      (blog.relations['posts'] as HasMany).setRaw([TestEntity.create('p1', 'u1', 'P')]);
      expect(blog.relatedList<TestEntity>('posts'), hasLength(1));
    });
  });
}
