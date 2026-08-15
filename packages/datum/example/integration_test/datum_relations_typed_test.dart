// A fully type-safe relational domain — no codegen — verified end-to-end on
// every local adapter.
//
// The model is a three-level dependent chain with back-links plus a
// many-to-many through a pivot:
//
//   Author ─HasMany─> Project ─HasMany─> Ticket ─HasMany─> Comment
//      ^                 ^                  ^
//      └──BelongsTo──────┴──BelongsTo──────┘
//                                          │
//                             Ticket <─ManyToMany(TicketTag)─> Tag
//
// Everything is declared once through the typed schema layer:
// DatumFieldSpec/DatumSchema for fields (`fromMap` = schema.decode,
// `toDatumMap` = schema.toMap, `diff` = schema.diffOf, `props` =
// schema.propsOf) and DatumRelationSpec for relations — typed names for
// `withRelated`, typed access (`listOf`/`oneOf`), typed lazy fetching
// (`fetchListFor`/`fetchOneFor`), and cascade behavior, all bound at compile
// time. The same suite runs on InMemory, SQLite, and Hive: relations resolve
// at the manager layer, so behavior must be identical.
//
// One sync server per entity type: LocalSyncServer's /entities namespace is
// single-type, and strict schema.decode (rightly) rejects rows of a
// different entity leaking into a pull.
//
// Run on an iOS simulator:
//   flutter test integration_test/datum_relations_typed_test.dart -d <udid>
import 'dart:io';

import 'package:datum/datum.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:datum_sqlite/datum_sqlite.dart';
import 'package:datum_test/datum_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const uid = 'u1';
final _epoch = DateTime.utc(2026, 1, 1);

// ---------------------------------------------------------------------------
// Author
// ---------------------------------------------------------------------------

class Author extends RelationalDatumEntity with MemoizedRelations {
  Author({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String name;
  final String email;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  static final nameField =
      DatumFieldSpec<Author, String>('name', getter: (a) => a.name);
  static final emailField =
      DatumFieldSpec<Author, String>('email', getter: (a) => a.email);
  static final core = datumCoreFieldSpecs<Author>();
  static final schema = DatumSchema<Author>(
    name: 'authors',
    fields: [...core.all, nameField, emailField],
    construct: (r) => Author(
      id: r(core.id),
      userId: r(core.userId),
      name: r(nameField),
      email: r(emailField),
      createdAt: r(core.createdAt),
      modifiedAt: r(core.modifiedAt),
      version: r(core.version),
      isDeleted: r.getOr(core.isDeleted, false),
    ),
  );

  static final projectsRel = DatumRelationSpec<Author, Project>.hasMany(
    'projects',
    foreignKey: Project.authorIdField,
    cascadeDelete: CascadeDeleteBehavior.cascade,
  );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      schema.toMap(this, target: target);

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      schema.diffOf(oldVersion as Author, this);

  @override
  List<Object?> get props => [...super.props, ...schema.propsOf(this)];

  @override
  Author copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      Author(
        id: id,
        userId: userId,
        name: name,
        email: email,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  Map<String, Relation> buildRelations() =>
      datumRelationsFor(this, [projectsRel]);
}

// ---------------------------------------------------------------------------
// Project
// ---------------------------------------------------------------------------

class Project extends RelationalDatumEntity with MemoizedRelations {
  Project({
    required this.id,
    required this.userId,
    required this.authorId,
    required this.title,
    this.stars = 0,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String authorId;
  final String title;
  final int stars;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  static final authorIdField =
      DatumFieldSpec<Project, String>('authorId', getter: (p) => p.authorId);
  static final titleField =
      DatumFieldSpec<Project, String>('title', getter: (p) => p.title);
  static final starsField = DatumFieldSpec<Project, int>('stars',
      getter: (p) => p.stars, defaultValue: 0);
  static final core = datumCoreFieldSpecs<Project>();
  static final schema = DatumSchema<Project>(
    name: 'projects',
    fields: [...core.all, authorIdField, titleField, starsField],
    construct: (r) => Project(
      id: r(core.id),
      userId: r(core.userId),
      authorId: r(authorIdField),
      title: r(titleField),
      stars: r.getOr(starsField, 0),
      createdAt: r(core.createdAt),
      modifiedAt: r(core.modifiedAt),
      version: r(core.version),
      isDeleted: r.getOr(core.isDeleted, false),
    ),
  );

  static final authorRel = DatumRelationSpec<Project, Author>.belongsTo(
      'author',
      foreignKey: authorIdField);
  static final ticketsRel = DatumRelationSpec<Project, Ticket>.hasMany(
    'tickets',
    foreignKey: Ticket.projectIdField,
    cascadeDelete: CascadeDeleteBehavior.cascade,
  );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      schema.toMap(this, target: target);

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      schema.diffOf(oldVersion as Project, this);

  @override
  List<Object?> get props => [...super.props, ...schema.propsOf(this)];

  @override
  Project copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      Project(
        id: id,
        userId: userId,
        authorId: authorId,
        title: title,
        stars: stars,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  Project withTitle(String newTitle) => Project(
        id: id,
        userId: userId,
        authorId: authorId,
        title: newTitle,
        stars: stars,
        createdAt: createdAt,
        modifiedAt: DateTime.now(),
        version: version + 1,
        isDeleted: isDeleted,
      );

  @override
  Map<String, Relation> buildRelations() =>
      datumRelationsFor(this, [authorRel, ticketsRel]);
}

// ---------------------------------------------------------------------------
// Ticket
// ---------------------------------------------------------------------------

class Ticket extends RelationalDatumEntity with MemoizedRelations {
  Ticket({
    required this.id,
    required this.userId,
    required this.projectId,
    required this.title,
    this.priority = 0,
    this.done = false,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String projectId;
  final String title;
  final int priority;
  final bool done;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  static final projectIdField =
      DatumFieldSpec<Ticket, String>('projectId', getter: (t) => t.projectId);
  static final titleField =
      DatumFieldSpec<Ticket, String>('title', getter: (t) => t.title);
  static final priorityField = DatumFieldSpec<Ticket, int>('priority',
      getter: (t) => t.priority, defaultValue: 0);
  static final doneField = DatumFieldSpec<Ticket, bool>('done',
      getter: (t) => t.done, defaultValue: false);
  static final core = datumCoreFieldSpecs<Ticket>();
  static final schema = DatumSchema<Ticket>(
    name: 'tickets',
    fields: [...core.all, projectIdField, titleField, priorityField, doneField],
    construct: (r) => Ticket(
      id: r(core.id),
      userId: r(core.userId),
      projectId: r(projectIdField),
      title: r(titleField),
      priority: r.getOr(priorityField, 0),
      done: r.getOr(doneField, false),
      createdAt: r(core.createdAt),
      modifiedAt: r(core.modifiedAt),
      version: r(core.version),
      isDeleted: r.getOr(core.isDeleted, false),
    ),
  );

  static final projectRel = DatumRelationSpec<Ticket, Project>.belongsTo(
      'project',
      foreignKey: projectIdField);
  static final commentsRel = DatumRelationSpec<Ticket, Comment>.hasMany(
    'comments',
    foreignKey: Comment.ticketIdField,
    cascadeDelete: CascadeDeleteBehavior.cascade,
  );

  /// Pivot rows die with their ticket…
  static final linksRel = DatumRelationSpec<Ticket, TicketTag>.hasMany(
    'links',
    foreignKey: TicketTag.ticketIdField,
    cascadeDelete: CascadeDeleteBehavior.cascade,
  );

  /// …while the tags themselves are shared and survive.
  static final tagsRel = DatumRelationSpec.manyToMany<Ticket, Tag, TicketTag>(
    'tags',
    pivotSelfKey: TicketTag.ticketIdField,
    pivotOtherKey: TicketTag.tagIdField,
  );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      schema.toMap(this, target: target);

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      schema.diffOf(oldVersion as Ticket, this);

  @override
  List<Object?> get props => [...super.props, ...schema.propsOf(this)];

  @override
  Ticket copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      Ticket(
        id: id,
        userId: userId,
        projectId: projectId,
        title: title,
        priority: priority,
        done: done,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  Map<String, Relation> buildRelations() =>
      datumRelationsFor(this, [projectRel, commentsRel, linksRel, tagsRel]);
}

// ---------------------------------------------------------------------------
// Comment
// ---------------------------------------------------------------------------

class Comment extends RelationalDatumEntity with MemoizedRelations {
  Comment({
    required this.id,
    required this.userId,
    required this.ticketId,
    required this.body,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String ticketId;
  final String body;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  static final ticketIdField =
      DatumFieldSpec<Comment, String>('ticketId', getter: (c) => c.ticketId);
  static final bodyField =
      DatumFieldSpec<Comment, String>('body', getter: (c) => c.body);
  static final core = datumCoreFieldSpecs<Comment>();
  static final schema = DatumSchema<Comment>(
    name: 'comments',
    fields: [...core.all, ticketIdField, bodyField],
    construct: (r) => Comment(
      id: r(core.id),
      userId: r(core.userId),
      ticketId: r(ticketIdField),
      body: r(bodyField),
      createdAt: r(core.createdAt),
      modifiedAt: r(core.modifiedAt),
      version: r(core.version),
      isDeleted: r.getOr(core.isDeleted, false),
    ),
  );

  static final ticketRel = DatumRelationSpec<Comment, Ticket>.belongsTo(
      'ticket',
      foreignKey: ticketIdField);

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      schema.toMap(this, target: target);

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      schema.diffOf(oldVersion as Comment, this);

  @override
  List<Object?> get props => [...super.props, ...schema.propsOf(this)];

  @override
  Comment copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      Comment(
        id: id,
        userId: userId,
        ticketId: ticketId,
        body: body,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  Map<String, Relation> buildRelations() =>
      datumRelationsFor(this, [ticketRel]);
}

// ---------------------------------------------------------------------------
// Tag + TicketTag (pivot)
// ---------------------------------------------------------------------------

class Tag extends RelationalDatumEntity with MemoizedRelations {
  Tag({
    required this.id,
    required this.userId,
    required this.label,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String label;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  static final labelField =
      DatumFieldSpec<Tag, String>('label', getter: (t) => t.label);
  static final core = datumCoreFieldSpecs<Tag>();
  static final schema = DatumSchema<Tag>(
    name: 'tags',
    fields: [...core.all, labelField],
    construct: (r) => Tag(
      id: r(core.id),
      userId: r(core.userId),
      label: r(labelField),
      createdAt: r(core.createdAt),
      modifiedAt: r(core.modifiedAt),
      version: r(core.version),
      isDeleted: r.getOr(core.isDeleted, false),
    ),
  );

  /// The reverse many-to-many: which tickets carry this tag.
  static final ticketsRel =
      DatumRelationSpec.manyToMany<Tag, Ticket, TicketTag>(
    'tickets',
    pivotSelfKey: TicketTag.tagIdField,
    pivotOtherKey: TicketTag.ticketIdField,
  );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      schema.toMap(this, target: target);

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      schema.diffOf(oldVersion as Tag, this);

  @override
  List<Object?> get props => [...super.props, ...schema.propsOf(this)];

  @override
  Tag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => Tag(
        id: id,
        userId: userId,
        label: label,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  Map<String, Relation> buildRelations() =>
      datumRelationsFor(this, [ticketsRel]);
}

class TicketTag extends RelationalDatumEntity with MemoizedRelations {
  TicketTag({
    required this.id,
    required this.userId,
    required this.ticketId,
    required this.tagId,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    this.isDeleted = false,
  });

  @override
  final String id;
  @override
  final String userId;
  final String ticketId;
  final String tagId;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  static final ticketIdField =
      DatumFieldSpec<TicketTag, String>('ticketId', getter: (l) => l.ticketId);
  static final tagIdField =
      DatumFieldSpec<TicketTag, String>('tagId', getter: (l) => l.tagId);
  static final core = datumCoreFieldSpecs<TicketTag>();
  static final schema = DatumSchema<TicketTag>(
    name: 'ticket_tags',
    fields: [...core.all, ticketIdField, tagIdField],
    construct: (r) => TicketTag(
      id: r(core.id),
      userId: r(core.userId),
      ticketId: r(ticketIdField),
      tagId: r(tagIdField),
      createdAt: r(core.createdAt),
      modifiedAt: r(core.modifiedAt),
      version: r(core.version),
      isDeleted: r.getOr(core.isDeleted, false),
    ),
  );

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) =>
      schema.toMap(this, target: target);

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) =>
      schema.diffOf(oldVersion as TicketTag, this);

  @override
  List<Object?> get props => [...super.props, ...schema.propsOf(this)];

  @override
  TicketTag copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) =>
      TicketTag(
        id: id,
        userId: userId,
        ticketId: ticketId,
        tagId: tagId,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        version: version ?? this.version,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  @override
  Map<String, Relation> buildRelations() => const {};
}

// ---------------------------------------------------------------------------
// Seed helpers (named params only)
// ---------------------------------------------------------------------------

Author author({required String id, required String name}) => Author(
      id: id,
      userId: uid,
      name: name,
      email: '$name@example.com',
      createdAt: _epoch,
      modifiedAt: _epoch,
      version: 1,
    );

Project project(
        {required String id,
        required String authorId,
        required String title,
        int stars = 0}) =>
    Project(
      id: id,
      userId: uid,
      authorId: authorId,
      title: title,
      stars: stars,
      createdAt: _epoch,
      modifiedAt: _epoch,
      version: 1,
    );

Ticket ticket(
        {required String id,
        required String projectId,
        required String title,
        int priority = 0,
        bool done = false}) =>
    Ticket(
      id: id,
      userId: uid,
      projectId: projectId,
      title: title,
      priority: priority,
      done: done,
      createdAt: _epoch,
      modifiedAt: _epoch,
      version: 1,
    );

Comment comment(
        {required String id, required String ticketId, required String body}) =>
    Comment(
      id: id,
      userId: uid,
      ticketId: ticketId,
      body: body,
      createdAt: _epoch,
      modifiedAt: _epoch,
      version: 1,
    );

Tag tag({required String id, required String label}) => Tag(
    id: id,
    userId: uid,
    label: label,
    createdAt: _epoch,
    modifiedAt: _epoch,
    version: 1);

TicketTag link(
        {required String id,
        required String ticketId,
        required String tagId}) =>
    TicketTag(
      id: id,
      userId: uid,
      ticketId: ticketId,
      tagId: tagId,
      createdAt: _epoch,
      modifiedAt: _epoch,
      version: 1,
    );

// ---------------------------------------------------------------------------
// Per-backend adapter factories
// ---------------------------------------------------------------------------

abstract class AdapterFactory {
  Future<void> setUp();
  Future<void> tearDown();
  LocalAdapter<T> create<T extends DatumEntityInterface>({
    required String store,
    required T Function(Map<String, dynamic> map) fromMap,
    required DatumSchema<T> schema,
  });
}

class InMemoryFactory extends AdapterFactory {
  @override
  Future<void> setUp() async {}
  @override
  Future<void> tearDown() async {}

  @override
  LocalAdapter<T> create<T extends DatumEntityInterface>({
    required String store,
    required T Function(Map<String, dynamic> map) fromMap,
    required DatumSchema<T> schema,
  }) =>
      InMemoryLocalAdapter<T>(fromMap: fromMap);
}

class SqliteFactory extends AdapterFactory {
  late Directory _dir;
  sql.Database? _db;

  @override
  Future<void> setUp() async {
    _dir = await Directory.systemTemp.createTemp('datum_relations_sqlite');
    _db = sql.sqlite3.open('${_dir.path}/relations.db');
  }

  @override
  Future<void> tearDown() async {
    _db?.dispose();
    _db = null;
    await _dir.delete(recursive: true);
  }

  @override
  LocalAdapter<T> create<T extends DatumEntityInterface>({
    required String store,
    required T Function(Map<String, dynamic> map) fromMap,
    required DatumSchema<T> schema,
  }) =>
      SqliteLocalAdapter<T>(
          database: _db!,
          table: store,
          fromMap: fromMap,
          schema: schema,
          strictColumns: true);
}

class HiveFactory extends AdapterFactory {
  late Directory _dir;
  var _run = 0;

  @override
  Future<void> setUp() async {
    _dir = await Directory.systemTemp.createTemp('datum_relations_hive');
    Hive.init('${_dir.path}/hive');
    _run++;
  }

  @override
  Future<void> tearDown() async {
    await _dir.delete(recursive: true);
  }

  @override
  LocalAdapter<T> create<T extends DatumEntityInterface>({
    required String store,
    required T Function(Map<String, dynamic> map) fromMap,
    required DatumSchema<T> schema,
  }) =>
      HiveLocalAdapter<T>(entityBoxName: '${store}_$_run', fromMap: fromMap);
}

// ---------------------------------------------------------------------------
// The scenario suite, identical on every backend
// ---------------------------------------------------------------------------

void registerRelationSuite(String backend, AdapterFactory factory) {
  group('Typed relations · $backend', () {
    final servers = <String, LocalSyncServer>{};
    late DatumManager<Author> authors;
    late DatumManager<Project> projects;
    late DatumManager<Ticket> tickets;
    late DatumManager<Comment> comments;
    late DatumManager<Tag> tags;
    late DatumManager<TicketTag> links;

    DatumRegistration<T> register<T extends DatumEntityInterface>(
            String store, DatumSchema<T> schema) =>
        DatumRegistration<T>(
          localAdapter: factory.create(
              store: store, fromMap: schema.decode, schema: schema),
          remoteAdapter: HttpRemoteAdapter<T>(
              baseUri: servers[store]!.baseUri, fromMap: schema.decode),
        );

    setUpAll(() async {
      await factory.setUp();
      for (final store in [
        'authors',
        'projects',
        'tickets',
        'comments',
        'tags',
        'ticket_tags'
      ]) {
        servers[store] = LocalSyncServer();
        await servers[store]!.start();
      }

      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: TestConnectivityChecker(),
        registrations: [
          register<Author>('authors', Author.schema),
          register<Project>('projects', Project.schema),
          register<Ticket>('tickets', Ticket.schema),
          register<Comment>('comments', Comment.schema),
          register<Tag>('tags', Tag.schema),
          register<TicketTag>('ticket_tags', TicketTag.schema),
        ],
      );
      expect(result.isSuccess(), isTrue, reason: '${result.errorOrNull}');
      authors = Datum.manager<Author>();
      projects = Datum.manager<Project>();
      tickets = Datum.manager<Ticket>();
      comments = Datum.manager<Comment>();
      tags = Datum.manager<Tag>();
      links = Datum.manager<TicketTag>();

      // Seed the graph: 1 author, 2 projects, 3 tickets, 4 comments,
      // 2 shared tags, 4 pivot links.
      await authors.push(item: author(id: 'a1', name: 'ada'), userId: uid);
      await projects.saveMany(items: [
        project(id: 'p1', authorId: 'a1', title: 'engine', stars: 5),
        project(id: 'p2', authorId: 'a1', title: 'docs', stars: 1),
      ], userId: uid);
      await tickets.saveMany(items: [
        ticket(id: 't1', projectId: 'p1', title: 'crash on sync', priority: 3),
        ticket(
            id: 't2', projectId: 'p1', title: 'typo', priority: 1, done: true),
        ticket(id: 't3', projectId: 'p2', title: 'add examples', priority: 2),
      ], userId: uid);
      await comments.saveMany(items: [
        comment(id: 'c1', ticketId: 't1', body: 'repro attached'),
        comment(id: 'c2', ticketId: 't1', body: 'fixed in #42'),
        comment(id: 'c3', ticketId: 't2', body: 'lgtm'),
        comment(id: 'c4', ticketId: 't3', body: 'started'),
      ], userId: uid);
      await tags.saveMany(
          items: [tag(id: 'g1', label: 'bug'), tag(id: 'g2', label: 'ui')],
          userId: uid);
      await links.saveMany(items: [
        link(id: 'l1', ticketId: 't1', tagId: 'g1'),
        link(id: 'l2', ticketId: 't1', tagId: 'g2'),
        link(id: 'l3', ticketId: 't2', tagId: 'g1'),
        link(id: 'l4', ticketId: 't3', tagId: 'g2'),
      ], userId: uid);
    });

    tearDownAll(() async {
      try {
        await Datum.instance.dispose().timeout(const Duration(seconds: 30));
      } on StateError {
        Datum.resetForTesting();
      }
      for (final server in servers.values) {
        await server.stop();
      }
      await factory.tearDown();
    });

    testWidgets(
        'typed eager loading walks the dependent chain in both directions',
        (tester) async {
      final ada = (await authors.read('a1',
          userId: uid, withRelated: [Author.projectsRel].names))!;
      expect(Author.projectsRel.listOf(ada)?.map((p) => p.id).toSet(),
          {'p1', 'p2'});

      final engine = (await projects.read('p1',
          userId: uid,
          withRelated: [Project.authorRel, Project.ticketsRel].names))!;
      expect(Project.authorRel.oneOf(engine)?.name, 'ada');
      expect(Project.ticketsRel.listOf(engine)?.map((t) => t.id).toSet(),
          {'t1', 't2'});

      final crash = (await tickets.read('t1',
          userId: uid,
          withRelated:
              [Ticket.projectRel, Ticket.commentsRel, Ticket.tagsRel].names))!;
      expect(Ticket.projectRel.oneOf(crash)?.title, 'engine');
      expect(Ticket.commentsRel.listOf(crash)?.map((c) => c.id).toSet(),
          {'c1', 'c2'});
      expect(Ticket.tagsRel.listOf(crash)?.map((t) => t.label).toSet(),
          {'bug', 'ui'});
    });

    testWidgets('typed lazy fetching resolves without eager loading',
        (tester) async {
      final docs = (await projects.read('p2', userId: uid))!;
      expect(Project.ticketsRel.listOf(docs), isNull,
          reason: 'nothing eager-loaded');

      final docTickets = await Project.ticketsRel.fetchListFor(docs);
      expect(docTickets.map((t) => t.id).toList(), ['t3']);

      final owner = await Project.authorRel.fetchOneFor(docs);
      expect(owner?.email, 'ada@example.com');

      final thread = await Ticket.commentsRel.fetchListFor(docTickets.single);
      expect(thread.single.body, 'started');

      // Many-to-many, both directions, through the pivot:
      final t3Tags = await Ticket.tagsRel.fetchListFor(docTickets.single);
      expect(t3Tags.map((t) => t.label).toList(), ['ui']);

      final bug = (await tags.read('g1', userId: uid))!;
      final bugTickets = await Tag.ticketsRel.fetchListFor(bug);
      expect(bugTickets.map((t) => t.id).toSet(), {'t1', 't2'});
    });

    testWidgets('typed foreign-key queries equal string queries',
        (tester) async {
      final typed = await tickets.query(
        DatumQueryBuilder<Ticket>()
            .whereField(Ticket.projectIdField, isEqualTo: 'p1')
            .orderByField(Ticket.priorityField, descending: true)
            .build(),
        source: DataSource.local,
        userId: uid,
      );
      final stringly = await tickets.query(
        DatumQueryBuilder<Ticket>()
            .where('projectId', isEqualTo: 'p1')
            .orderBy('priority', descending: true)
            .build(),
        source: DataSource.local,
        userId: uid,
      );
      expect(
          typed.map((t) => t.id).toList(), stringly.map((t) => t.id).toList());
      expect(typed.map((t) => t.id).toList(), ['t1', 't2']);

      final open = await tickets.query(
        DatumQueryBuilder<Ticket>()
            .whereField(Ticket.priorityField, isGreaterThanOrEqualTo: 2)
            .whereField(Ticket.doneField, isEqualTo: false)
            .build(),
        source: DataSource.local,
        userId: uid,
      );
      expect(open.map((t) => t.id).toSet(), {'t1', 't3'});
    });

    testWidgets('schema-driven diff powers a dependent update', (tester) async {
      final docs = (await projects.read('p2', userId: uid))!;
      final renamed = docs.withTitle('handbook');

      final delta = Project.schema.diffOf(docs, renamed)!;
      expect(delta.keys.toSet(), {'title', 'modifiedAt', 'version'});

      await projects.push(item: renamed, userId: uid);
      expect((await projects.read('p2', userId: uid))?.title, 'handbook');
    });

    testWidgets('the whole graph reaches the servers', (tester) async {
      for (final manager in [
        authors,
        projects,
        tickets,
        comments,
        tags,
        links
      ]) {
        expect((await manager.synchronize(uid)).failedCount, 0);
      }
      expect(servers['authors']!.storage[uid]?.keys.toSet(), {'a1'});
      expect(servers['projects']!.storage[uid]?.keys.toSet(), {'p1', 'p2'});
      expect(
          servers['tickets']!.storage[uid]?.keys.toSet(), {'t1', 't2', 't3'});
      expect(servers['comments']!.storage[uid]?.keys.toSet(),
          {'c1', 'c2', 'c3', 'c4'});
      expect(servers['tags']!.storage[uid]?.keys.toSet(), {'g1', 'g2'});
      expect(servers['ticket_tags']!.storage[uid]?.keys.toSet(),
          {'l1', 'l2', 'l3', 'l4'});
      expect(servers['projects']!.storage[uid]?['p2']?['title'], 'handbook');
    });

    testWidgets('mid-level cascade preserves ancestors and sibling branches',
        (tester) async {
      final result = await tickets.cascadeDelete(id: 't2', userId: uid);
      expect(result.success, isTrue, reason: result.errors.join('; '));
      expect(result.totalDeleted, 3, reason: 't2 + c3 + l3');
      expect(result.deletedEntities[Ticket]?.map((e) => e.id).toSet(), {'t2'});
      expect(result.deletedEntities[Comment]?.map((e) => e.id).toSet(), {'c3'});
      expect(
          result.deletedEntities[TicketTag]?.map((e) => e.id).toSet(), {'l3'});

      // The parent project, sibling ticket, and the tag far side of the
      // deleted pivot row are untouched.
      expect(await projects.read('p1', userId: uid), isNotNull,
          reason: 'belongsTo never cascades upward');
      expect(await tickets.read('t1', userId: uid), isNotNull);
      expect(await comments.read('c1', userId: uid), isNotNull);
      expect((await tags.read('g1', userId: uid))?.label, 'bug');
    });

    testWidgets('cascade delete removes exactly the dependent subtree',
        (tester) async {
      final result = await projects.cascadeDelete(id: 'p1', userId: uid);
      expect(result.success, isTrue);
      expect(result.totalDeleted, 6,
          reason: 'p1 + t1 + c1 + c2 + l1 + l2 (t2\'s branch fell earlier)');

      expect(await projects.read('p1', userId: uid), isNull);
      expect(await tickets.read('t1', userId: uid), isNull);
      expect(await comments.read('c1', userId: uid), isNull);
      expect(await links.read('l1', userId: uid), isNull);

      // Shared tags and the independent branch survive.
      expect((await tags.read('g1', userId: uid))?.label, 'bug');
      expect((await authors.read('a1', userId: uid))?.name, 'ada');
      expect((await tickets.read('t3', userId: uid))?.title, 'add examples');
      expect((await links.read('l4', userId: uid))?.tagId, 'g2');

      // The orphaned tag now links nothing. Asserted with a fresh typed
      // pivot query: Relation.fetch() memoizes per entity INSTANCE, and
      // InMemoryLocalAdapter hands back shared instances — an earlier fetch
      // on the same tag would answer from its pre-cascade cache.
      final orphanLinks = await links.query(
        DatumQueryBuilder<TicketTag>()
            .whereField(TicketTag.tagIdField, isEqualTo: 'g1')
            .build(),
        source: DataSource.local,
        userId: uid,
      );
      expect(orphanLinks, isEmpty);
    });

    testWidgets('the pruned graph converges on the servers', (tester) async {
      for (final manager in [
        authors,
        projects,
        tickets,
        comments,
        tags,
        links
      ]) {
        expect((await manager.synchronize(uid)).failedCount, 0);
      }
      Set<String> surviving(String store) => servers[store]!
          .storage[uid]!
          .entries
          .where((e) => e.value['isDeleted'] != true)
          .map((e) => e.key)
          .toSet();
      expect(surviving('authors'), {'a1'});
      expect(surviving('projects'), {'p2'});
      expect(surviving('tickets'), {'t3'});
      expect(surviving('comments'), {'c4'});
      expect(surviving('tags'), {'g1', 'g2'});
      expect(surviving('ticket_tags'), {'l4'});
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  registerRelationSuite('inmemory', InMemoryFactory());
  registerRelationSuite('sqlite', SqliteFactory());
  registerRelationSuite('hive', HiveFactory());
}
