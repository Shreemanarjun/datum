import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/mock_adapters.dart';
import 'manager_coverage_helpers.dart';

/// Coverage for DatumManager cascade-delete behaviors that require registered
/// related managers: restrict warnings, HasOne setNull, ManyToMany and
/// BelongsTo traversal, BelongsTo setNull operations, relationship cache
/// maintenance, and user switching with an initialized Datum singleton.

DateTime get _at => DateTime(2024);

class Band extends RelationalDatumEntity {
  Band({required this.id, required this.name, this.userId = 'u1'});

  factory Band.fromJson(Map<String, dynamic> j) => Band(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        userId: j['userId'] as String? ?? 'u1',
      );

  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  late final Map<String, Relation> _relations = {
    'albums': HasMany<Album>(this, 'bandId', cascadeDeleteBehavior: CascadeDeleteBehavior.restrict),
  };
  @override
  Map<String, Relation> get relations => _relations;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'name': name};

  @override
  Band copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Band(id: id, name: name, userId: userId);

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is Band && oldVersion.name == name) return null;
    return {'name': name};
  }
}

class Album extends RelationalDatumEntity {
  const Album({required this.id, required this.bandId, this.userId = 'u1'});

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: j['id'] as String,
        bandId: j['bandId'] as String? ?? '',
        userId: j['userId'] as String? ?? 'u1',
      );

  @override
  final String id;
  @override
  final String userId;
  final String bandId;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'bandId': bandId};

  @override
  Album copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

class Writer extends RelationalDatumEntity {
  Writer({required this.id, this.userId = 'u1'});

  factory Writer.fromJson(Map<String, dynamic> j) => Writer(id: j['id'] as String, userId: j['userId'] as String? ?? 'u1');

  @override
  final String id;
  @override
  final String userId;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  late final Map<String, Relation> _relations = {
    'bio': HasOne<Bio>(this, 'writerId', cascadeDeleteBehavior: CascadeDeleteBehavior.setNull),
  };
  @override
  Map<String, Relation> get relations => _relations;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId};

  @override
  Writer copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

class Bio extends RelationalDatumEntity {
  const Bio({required this.id, required this.writerId, this.userId = 'u1'});

  factory Bio.fromJson(Map<String, dynamic> j) => Bio(
        id: j['id'] as String,
        writerId: j['writerId'] as String?,
        userId: j['userId'] as String? ?? 'u1',
      );

  @override
  final String id;
  @override
  final String userId;
  final String? writerId;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'writerId': writerId};

  @override
  Bio copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

class Student extends RelationalDatumEntity {
  Student({required this.id, this.userId = 'u1'});

  factory Student.fromJson(Map<String, dynamic> j) => Student(id: j['id'] as String, userId: j['userId'] as String? ?? 'u1');

  @override
  final String id;
  @override
  final String userId;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  late final Map<String, Relation> _relations = {
    'courses': ManyToMany<Course>(
      this,
      Enrollment,
      'studentId',
      'courseId',
      cascadeDeleteBehavior: CascadeDeleteBehavior.cascade,
    ),
  };
  @override
  Map<String, Relation> get relations => _relations;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId};

  @override
  Student copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

class Course extends RelationalDatumEntity {
  const Course({required this.id, this.userId = 'u1'});

  factory Course.fromJson(Map<String, dynamic> j) => Course(id: j['id'] as String, userId: j['userId'] as String? ?? 'u1');

  @override
  final String id;
  @override
  final String userId;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId};

  @override
  Course copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

class Enrollment extends RelationalDatumEntity {
  const Enrollment({required this.id, required this.studentId, required this.courseId, this.userId = 'u1'});

  factory Enrollment.fromJson(Map<String, dynamic> j) => Enrollment(
        id: j['id'] as String,
        studentId: j['studentId'] as String? ?? '',
        courseId: j['courseId'] as String? ?? '',
        userId: j['userId'] as String? ?? 'u1',
      );

  @override
  final String id;
  @override
  final String userId;
  final String studentId;
  final String courseId;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'studentId': studentId,
        'courseId': courseId,
      };

  @override
  Enrollment copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

class Ticket extends RelationalDatumEntity {
  Ticket({required this.id, this.ownerId, this.userId = 'u1'});

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        id: j['id'] as String,
        ownerId: j['ownerId'] as String?,
        userId: j['userId'] as String? ?? 'u1',
      );

  @override
  final String id;
  @override
  final String userId;
  final String? ownerId;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  late final Map<String, Relation> _relations = {
    'owner': BelongsTo<Owner>(this, 'ownerId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
  };
  @override
  Map<String, Relation> get relations => _relations;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'ownerId': ownerId};

  @override
  Ticket copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

class Owner extends RelationalDatumEntity {
  const Owner({required this.id, this.userId = 'u1'});

  factory Owner.fromJson(Map<String, dynamic> j) => Owner(id: j['id'] as String, userId: j['userId'] as String? ?? 'u1');

  @override
  final String id;
  @override
  final String userId;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId};

  @override
  Owner copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

class Doc extends RelationalDatumEntity {
  Doc({required this.id, this.refId, this.userId = 'u1'});

  factory Doc.fromJson(Map<String, dynamic> j) => Doc(
        id: j['id'] as String,
        refId: j['refId'] as String?,
        userId: j['userId'] as String? ?? 'u1',
      );

  @override
  final String id;
  @override
  final String userId;
  final String? refId;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  late final Map<String, Relation> _relations = {
    'ref': BelongsTo<RefNode>(this, 'refId', cascadeDeleteBehavior: CascadeDeleteBehavior.setNull),
  };
  @override
  Map<String, Relation> get relations => _relations;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'refId': refId};

  @override
  Doc copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

class RefNode extends RelationalDatumEntity {
  const RefNode({required this.id, this.refId, this.userId = 'u1'});

  factory RefNode.fromJson(Map<String, dynamic> j) => RefNode(
        id: j['id'] as String,
        refId: j['refId'] as String?,
        userId: j['userId'] as String? ?? 'u1',
      );

  @override
  final String id;
  @override
  final String userId;

  /// Foreign key back to a [Doc]; nullable so setNull can clear it.
  final String? refId;
  @override
  DateTime get createdAt => _at;
  @override
  DateTime get modifiedAt => _at;
  @override
  int get version => 1;
  @override
  bool get isDeleted => false;

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {'id': id, 'userId': userId, 'refId': refId};

  @override
  RefNode copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) => null;
}

Future<void> _initDatum(List<DatumRegistration> registrations) async {
  Datum.resetForTesting();
  final result = await Datum.initialize(
    config: const DatumConfig(enableLogging: false),
    connectivityChecker: const OnlineConnectivity(),
    registrations: registrations,
  );
  expect(result.isSuccess(), isTrue, reason: 'Datum must initialize');
}

void main() {
  tearDown(() {
    Datum.resetForTesting();
    DatumRelationSchema.clear();
  });

  group('restrict relations', () {
    setUp(() async {
      await _initDatum([
        DatumRegistration<Band>(
          localAdapter: MockLocalAdapter<Band>(fromJson: Band.fromJson),
          remoteAdapter: MockRemoteAdapter<Band>(fromJson: Band.fromJson),
        ),
        DatumRegistration<Album>(
          localAdapter: MockLocalAdapter<Album>(fromJson: Album.fromJson),
          remoteAdapter: MockRemoteAdapter<Album>(fromJson: Album.fromJson),
        ),
      ]);
      final bands = Datum.manager<Band>();
      final albums = Datum.manager<Album>();
      await bands.push(item: Band(id: 'b1', name: 'orig'), userId: 'u1');
      await albums.push(item: const Album(id: 'a1', bandId: 'b1'), userId: 'u1');
    });

    test('getDeletePlan reports restrict warnings and cascadeDelete refuses to delete', () async {
      final bands = Datum.manager<Band>();

      final preview = await bands.getDeletePlan('b1', userId: 'u1');
      expect(preview, isNotNull);
      expect(preview!.canDelete, isFalse);
      expect(preview.warningMessages.join(), contains('restrict'));

      final result = await bands.cascadeDelete(id: 'b1', userId: 'u1');
      expect(result.success, isFalse);
      expect(result.restrictedRelations.keys, contains('albums'));
      expect(await bands.read('b1', userId: 'u1'), isNotNull);
    });

    test('clearRelationshipCacheForType removes cached relationship queries for that type', () async {
      final bands = Datum.manager<Band>();

      await bands.getDeletePlan('b1', userId: 'u1');
      expect(bands.getCacheStats()['relationship_queries'], greaterThan(0));

      bands.clearRelationshipCacheForType(Band);
      expect(bands.getCacheStats()['relationship_queries'], 0);
    });

    test('updating an entity invalidates its cached relationship queries', () async {
      final bands = Datum.manager<Band>();

      await bands.getDeletePlan('b1', userId: 'u1');
      expect(bands.getCacheStats()['relationship_queries'], greaterThan(0));

      // The update path invalidates caches keyed by this entity.
      await bands.push(item: Band(id: 'b1', name: 'renamed'), userId: 'u1');
      expect(bands.getCacheStats()['relationship_queries'], 0);
    });

    test('switchUser succeeds and triggers a global stream refresh when Datum is initialized', () async {
      final bands = Datum.manager<Band>();

      final result = await bands.switchUser(
        oldUserId: 'u1',
        newUserId: 'u2',
        strategy: UserSwitchStrategy.keepLocal,
      );

      expect(result.success, isTrue);
      expect(result.newUserId, 'u2');
    });
  });

  group('HasOne setNull relations', () {
    test('cascade delete nulls the foreign key on the related entity', () async {
      await _initDatum([
        DatumRegistration<Writer>(
          localAdapter: MockLocalAdapter<Writer>(fromJson: Writer.fromJson),
          remoteAdapter: MockRemoteAdapter<Writer>(fromJson: Writer.fromJson),
        ),
        DatumRegistration<Bio>(
          localAdapter: MockLocalAdapter<Bio>(fromJson: Bio.fromJson),
          remoteAdapter: MockRemoteAdapter<Bio>(fromJson: Bio.fromJson),
        ),
      ]);
      final writers = Datum.manager<Writer>();
      final bios = Datum.manager<Bio>();
      await writers.push(item: Writer(id: 'w1'), userId: 'u1');
      await bios.push(item: const Bio(id: 'bio1', writerId: 'w1'), userId: 'u1');

      final result = await writers.deleteCascade('w1').forUser('u1').execute();

      expect(result, isA<CascadeSuccess<Writer>>());
      expect(await writers.read('w1', userId: 'u1'), isNull);
      final bio = await bios.read('bio1', userId: 'u1');
      expect(bio, isNotNull);
      expect(bio!.writerId, isNull, reason: 'setNull must clear the foreign key');
    });

    test('a failing setNull patch is reported as a cascade failure', () async {
      await _initDatum([
        DatumRegistration<Writer>(
          localAdapter: MockLocalAdapter<Writer>(fromJson: Writer.fromJson),
          remoteAdapter: MockRemoteAdapter<Writer>(fromJson: Writer.fromJson),
        ),
        // No fromJson: the adapter's patch throws, failing the update step.
        DatumRegistration<Bio>(
          localAdapter: MockLocalAdapter<Bio>(),
          remoteAdapter: MockRemoteAdapter<Bio>(),
        ),
      ]);
      final writers = Datum.manager<Writer>();
      final bios = Datum.manager<Bio>();
      await writers.push(item: Writer(id: 'w2'), userId: 'u1');
      await bios.push(item: const Bio(id: 'bio2', writerId: 'w2'), userId: 'u1');

      final result = await writers.deleteCascade('w2').forUser('u1').execute();

      expect(result, isA<CascadeFailure<Writer>>());
      expect(await writers.read('w2', userId: 'u1'), isNotNull, reason: 'the plan stopped before deleting the writer');
    });
  });

  group('ManyToMany cascade relations', () {
    test('cascade delete traverses the pivot and deletes related targets', () async {
      await _initDatum([
        DatumRegistration<Student>(
          localAdapter: MockLocalAdapter<Student>(fromJson: Student.fromJson),
          remoteAdapter: MockRemoteAdapter<Student>(fromJson: Student.fromJson),
        ),
        DatumRegistration<Course>(
          localAdapter: MockLocalAdapter<Course>(fromJson: Course.fromJson),
          remoteAdapter: MockRemoteAdapter<Course>(fromJson: Course.fromJson),
        ),
        DatumRegistration<Enrollment>(
          localAdapter: MockLocalAdapter<Enrollment>(fromJson: Enrollment.fromJson),
          remoteAdapter: MockRemoteAdapter<Enrollment>(fromJson: Enrollment.fromJson),
        ),
      ]);
      final students = Datum.manager<Student>();
      final courses = Datum.manager<Course>();
      final enrollments = Datum.manager<Enrollment>();

      await students.push(item: Student(id: 's1'), userId: 'u1');
      await courses.push(item: const Course(id: 'c1'), userId: 'u1');
      await courses.push(item: const Course(id: 'c2'), userId: 'u1');
      await enrollments.push(item: const Enrollment(id: 'en1', studentId: 's1', courseId: 'c1'), userId: 'u1');
      await enrollments.push(item: const Enrollment(id: 'en2', studentId: 's1', courseId: 'c2'), userId: 'u1');

      final result = await students.cascadeDelete(id: 's1', userId: 'u1');

      expect(result.success, isTrue);
      expect(await students.read('s1', userId: 'u1'), isNull);
      expect(await courses.read('c1', userId: 'u1'), isNull);
      expect(await courses.read('c2', userId: 'u1'), isNull);
    });
  });

  group('BelongsTo cascade relations', () {
    setUp(() async {
      await _initDatum([
        DatumRegistration<Ticket>(
          localAdapter: MockLocalAdapter<Ticket>(fromJson: Ticket.fromJson),
          remoteAdapter: MockRemoteAdapter<Ticket>(fromJson: Ticket.fromJson),
        ),
        DatumRegistration<Owner>(
          localAdapter: MockLocalAdapter<Owner>(fromJson: Owner.fromJson),
          remoteAdapter: MockRemoteAdapter<Owner>(fromJson: Owner.fromJson),
        ),
      ]);
    });

    test('cascade delete follows the foreign key and deletes the owner too', () async {
      final tickets = Datum.manager<Ticket>();
      final owners = Datum.manager<Owner>();
      await owners.push(item: const Owner(id: 'o1'), userId: 'u1');
      await tickets.push(item: Ticket(id: 't1', ownerId: 'o1'), userId: 'u1');

      final result = await tickets.cascadeDelete(id: 't1', userId: 'u1');

      expect(result.success, isTrue);
      expect(await tickets.read('t1', userId: 'u1'), isNull);
      expect(await owners.read('o1', userId: 'u1'), isNull);
    });

    test('a null foreign key resolves to no related entities', () async {
      final tickets = Datum.manager<Ticket>();
      await tickets.push(item: Ticket(id: 't2'), userId: 'u1');

      final result = await tickets.cascadeDelete(id: 't2', userId: 'u1');

      expect(result.success, isTrue);
      expect(await tickets.read('t2', userId: 'u1'), isNull);
    });
  });

  group('BelongsTo setNull relations', () {
    test('cascade delete nulls foreign keys on referencing entities and queues sync updates', () async {
      await _initDatum([
        DatumRegistration<Doc>(
          localAdapter: MockLocalAdapter<Doc>(fromJson: Doc.fromJson),
          remoteAdapter: MockRemoteAdapter<Doc>(fromJson: Doc.fromJson),
        ),
        DatumRegistration<RefNode>(
          localAdapter: MockLocalAdapter<RefNode>(fromJson: RefNode.fromJson),
          remoteAdapter: MockRemoteAdapter<RefNode>(fromJson: RefNode.fromJson),
        ),
      ]);
      final docs = Datum.manager<Doc>();
      final refs = Datum.manager<RefNode>();

      await docs.push(item: Doc(id: 'd1', refId: 'unused'), userId: 'u1');
      // This node references the doc via its refId foreign key.
      await refs.push(item: const RefNode(id: 'r1', refId: 'd1'), userId: 'u1');
      final pendingBefore = (await refs.getPendingOperations('u1')).length;

      final result = await docs.cascadeDelete(id: 'd1', userId: 'u1');

      expect(result.success, isTrue);
      expect(await docs.read('d1', userId: 'u1'), isNull);
      final node = await refs.read('r1', userId: 'u1');
      expect(node, isNotNull);
      expect(node!.refId, isNull, reason: 'setNull must clear the foreign key');

      // The setNull update was queued for remote sync on the related manager.
      final pendingAfter = await refs.getPendingOperations('u1');
      expect(pendingAfter.length, pendingBefore + 1);
      expect(pendingAfter.last.type, DatumOperationType.update);
      expect(pendingAfter.last.entityId, 'r1');
    });

    test('a failing setNull operation is recorded as an error', () async {
      await _initDatum([
        DatumRegistration<Doc>(
          localAdapter: MockLocalAdapter<Doc>(fromJson: Doc.fromJson),
          remoteAdapter: MockRemoteAdapter<Doc>(fromJson: Doc.fromJson),
        ),
        // No fromJson: patching the referencing node throws.
        DatumRegistration<RefNode>(
          localAdapter: MockLocalAdapter<RefNode>(),
          remoteAdapter: MockRemoteAdapter<RefNode>(),
        ),
      ]);
      final docs = Datum.manager<Doc>();
      final refs = Datum.manager<RefNode>();

      await docs.push(item: Doc(id: 'd2'), userId: 'u1');
      await refs.push(item: const RefNode(id: 'r2', refId: 'd2'), userId: 'u1');

      final result = await docs.cascadeDelete(id: 'd2', userId: 'u1');

      expect(result.success, isFalse);
      expect(result.errors.join(), contains('setNull'));
    });
  });
}
