// A fully type-safe relational domain — no codegen — verified end-to-end on
// every local adapter.
//
// The model is a three-level dependent chain with back-links:
//
//   Author ─┬─ HasMany ──> Project ─┬─ HasMany ──> Ticket ─┬─ HasMany ──> Comment
//           │                       │                      │
//           └<─ BelongsTo ──────────┴<─ BelongsTo ─────────┴<─ BelongsTo ──┘
//
// Every entity is declared once through DatumSchema/DatumFieldSpec:
// `fromMap` is `schema.decode`, `toDatumMap` is `schema.toMap`, `diff` is
// `schema.diffOf`, `props` is `schema.propsOf`, and every query goes through
// typed field specs. The same scenario suite (eager loading, typed
// foreign-key queries, dependent updates, transitive cascade delete, sync)
// runs on InMemory, SQLite, and Hive — relation resolution happens at the
// manager layer, so it must behave identically on all of them.
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
  Map<String, Relation> buildRelations() => {
        'projects': HasMany<Project>(this, 'authorId',
            cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
      };
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

  @override
  Map<String, Relation> buildRelations() => {
        'author': BelongsTo<Author>(this, 'authorId'),
        'tickets': HasMany<Ticket>(this, 'projectId',
            cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
      };

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
  Map<String, Relation> buildRelations() => {
        'project': BelongsTo<Project>(this, 'projectId'),
        'comments': HasMany<Comment>(this, 'ticketId',
            cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
      };
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
  Map<String, Relation> buildRelations() => {
        'ticket': BelongsTo<Ticket>(this, 'ticketId'),
      };
}

// ---------------------------------------------------------------------------
// Seed helpers (named params only — no positional string soup)
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
    // One sync server per entity type: LocalSyncServer's /entities namespace
    // is single-type, and strict schema.decode (rightly) rejects rows of a
    // different entity leaking into a pull.
    late LocalSyncServer authorsServer;
    late LocalSyncServer projectsServer;
    late LocalSyncServer ticketsServer;
    late LocalSyncServer commentsServer;
    late DatumManager<Author> authors;
    late DatumManager<Project> projects;
    late DatumManager<Ticket> tickets;
    late DatumManager<Comment> comments;

    setUpAll(() async {
      await factory.setUp();
      authorsServer = LocalSyncServer();
      projectsServer = LocalSyncServer();
      ticketsServer = LocalSyncServer();
      commentsServer = LocalSyncServer();
      for (final server in [
        authorsServer,
        projectsServer,
        ticketsServer,
        commentsServer
      ]) {
        await server.start();
      }

      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: TestConnectivityChecker(),
        registrations: [
          DatumRegistration<Author>(
            localAdapter: factory.create(
                store: 'authors',
                fromMap: Author.schema.decode,
                schema: Author.schema),
            remoteAdapter: HttpRemoteAdapter<Author>(
                baseUri: authorsServer.baseUri, fromMap: Author.schema.decode),
          ),
          DatumRegistration<Project>(
            localAdapter: factory.create(
                store: 'projects',
                fromMap: Project.schema.decode,
                schema: Project.schema),
            remoteAdapter: HttpRemoteAdapter<Project>(
                baseUri: projectsServer.baseUri,
                fromMap: Project.schema.decode),
          ),
          DatumRegistration<Ticket>(
            localAdapter: factory.create(
                store: 'tickets',
                fromMap: Ticket.schema.decode,
                schema: Ticket.schema),
            remoteAdapter: HttpRemoteAdapter<Ticket>(
                baseUri: ticketsServer.baseUri, fromMap: Ticket.schema.decode),
          ),
          DatumRegistration<Comment>(
            localAdapter: factory.create(
                store: 'comments',
                fromMap: Comment.schema.decode,
                schema: Comment.schema),
            remoteAdapter: HttpRemoteAdapter<Comment>(
                baseUri: commentsServer.baseUri,
                fromMap: Comment.schema.decode),
          ),
        ],
      );
      expect(result.isSuccess(), isTrue, reason: '${result.errorOrNull}');
      authors = Datum.manager<Author>();
      projects = Datum.manager<Project>();
      tickets = Datum.manager<Ticket>();
      comments = Datum.manager<Comment>();

      // Seed the dependency graph: 1 author, 2 projects, 3 tickets, 4 comments.
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
    });

    tearDownAll(() async {
      try {
        await Datum.instance.dispose().timeout(const Duration(seconds: 30));
      } on StateError {
        Datum.resetForTesting();
      }
      for (final server in [
        authorsServer,
        projectsServer,
        ticketsServer,
        commentsServer
      ]) {
        await server.stop();
      }
      await factory.tearDown();
    });

    testWidgets('eager loading walks the dependent chain in both directions',
        (tester) async {
      final ada =
          (await authors.read('a1', userId: uid, withRelated: ['projects']))!;
      expect(ada.relatedList<Project>('projects')?.map((p) => p.id).toSet(),
          {'p1', 'p2'});

      final engine = (await projects
          .read('p1', userId: uid, withRelated: ['author', 'tickets']))!;
      expect(engine.relatedOne<Author>('author')?.name, 'ada');
      expect(engine.relatedList<Ticket>('tickets')?.map((t) => t.id).toSet(),
          {'t1', 't2'});

      final crash = (await tickets
          .read('t1', userId: uid, withRelated: ['project', 'comments']))!;
      expect(crash.relatedOne<Project>('project')?.title, 'engine');
      expect(crash.relatedList<Comment>('comments')?.map((c) => c.id).toSet(),
          {'c1', 'c2'});
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

      final threads = await comments.query(
        DatumQueryBuilder<Comment>()
            .whereField(Comment.ticketIdField, isIn: ['t1', 't2']).build(),
        source: DataSource.local,
        userId: uid,
      );
      expect(threads, hasLength(3));
    });

    testWidgets('schema-driven diff powers a dependent update', (tester) async {
      final docs = (await projects.read('p2', userId: uid))!;
      final renamed = docs.withTitle('handbook');

      final delta = Project.schema.diffOf(docs, renamed)!;
      expect(delta.keys.toSet(), {'title', 'modifiedAt', 'version'},
          reason: 'only the changed payload plus sync stamps');

      await projects.push(item: renamed, userId: uid);
      expect((await projects.read('p2', userId: uid))?.title, 'handbook');
    });

    testWidgets('the whole graph reaches the server', (tester) async {
      for (final sync in [authors, projects, tickets, comments]
          .map((m) => m.synchronize(uid))) {
        expect((await sync).failedCount, 0);
      }
      expect(authorsServer.storage[uid]?.keys.toSet(), {'a1'});
      expect(projectsServer.storage[uid]?.keys.toSet(), {'p1', 'p2'});
      expect(ticketsServer.storage[uid]?.keys.toSet(), {'t1', 't2', 't3'});
      expect(
          commentsServer.storage[uid]?.keys.toSet(), {'c1', 'c2', 'c3', 'c4'});
      expect(projectsServer.storage[uid]?['p2']?['title'], 'handbook');
    });

    testWidgets('cascade delete removes exactly the dependent subtree',
        (tester) async {
      final result = await projects.cascadeDelete(id: 'p1', userId: uid);
      expect(result.success, isTrue);
      expect(result.totalDeleted, 6, reason: 'p1 + t1 + t2 + c1 + c2 + c3');

      expect(await projects.read('p1', userId: uid), isNull);
      expect(await tickets.read('t1', userId: uid), isNull);
      expect(await tickets.read('t2', userId: uid), isNull);
      expect(await comments.read('c1', userId: uid), isNull);
      expect(await comments.read('c3', userId: uid), isNull);

      // The independent branch survives untouched.
      expect((await authors.read('a1', userId: uid))?.name, 'ada');
      expect((await tickets.read('t3', userId: uid))?.title, 'add examples');
      expect((await comments.read('c4', userId: uid))?.body, 'started');
    });

    testWidgets('the pruned graph converges on the server', (tester) async {
      for (final manager in [authors, projects, tickets, comments]) {
        expect((await manager.synchronize(uid)).failedCount, 0);
      }
      Set<String> surviving(LocalSyncServer server) =>
          server.storage[uid]!.entries
              .where((e) => e.value['isDeleted'] != true)
              .map((e) => e.key)
              .toSet();
      expect(surviving(authorsServer), {'a1'});
      expect(surviving(projectsServer), {'p2'});
      expect(surviving(ticketsServer), {'t3'});
      expect(surviving(commentsServer), {'c4'});
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  registerRelationSuite('inmemory', InMemoryFactory());
  registerRelationSuite('sqlite', SqliteFactory());
  registerRelationSuite('hive', HiveFactory());
}
