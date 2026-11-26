import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// An in-process HTTP backend for exercising Datum against **real network
/// behavior** — actual sockets, JSON over the wire, HTTP status semantics, and
/// injectable faults that in-memory mocks cannot reproduce.
///
/// Endpoints (entity payloads are raw JSON maps keyed by `id` + `userId`):
///
/// - `GET  /health`                       → 200
/// - `GET  /entities?userId=`             → JSON list (all users when omitted)
/// - `GET  /entities/:id?userId=`         → JSON map | 404
/// - `POST /entities`                     → create/overwrite from body
/// - `PUT  /entities/:id`                 → full update from body
/// - `PATCH /entities/:id?userId=`        → merge delta into stored map | 404
/// - `DELETE /entities/:id?userId=`       → `{deleted: bool}`
/// - `GET/PUT /metadata/:userId`          → sync metadata map | 404
///
/// Fault injection (settable between requests from tests):
/// - [latency]: added to every response.
/// - [remainingFailures] + [failMatcher]: respond 500 to the next N matching
///   requests (all requests when no matcher is set).
/// - [offline]: respond 503 to everything.
/// - [dropConnections]: sever the socket without any response (client sees a
///   connection error, not an HTTP status).
/// - [enforceVersions]: reject stale writes (`version` <= stored) with 409.
///
/// Every request is appended to [requestLog] as `'METHOD /path'`.
class LocalSyncServer {
  HttpServer? _server;

  /// The bound port (after [start]).
  int get port => _server!.port;

  /// Base URI for adapters.
  Uri get baseUri => Uri.parse('http://127.0.0.1:$port');

  /// storage[userId][entityId] = raw entity map.
  final Map<String, Map<String, Map<String, dynamic>>> storage = {};

  /// Per-user sync metadata maps.
  final Map<String, Map<String, dynamic>> metadata = {};

  /// Added to every response.
  Duration latency = Duration.zero;

  /// Number of upcoming matching requests to fail with [failStatusCode].
  int remainingFailures = 0;

  /// Restricts which requests [remainingFailures] applies to.
  bool Function(String method, String path)? failMatcher;

  /// Status code used for injected failures (500 = transient/retryable;
  /// e.g. 401 to simulate auth failures, which are non-retryable).
  int failStatusCode = 500;

  /// Number of upcoming matching responses to corrupt (non-JSON garbage body
  /// with a 200 status — simulates proxy mangling / truncated payloads).
  int corruptNextResponses = 0;

  /// Restricts which responses [corruptNextResponses] applies to.
  bool Function(String method, String path)? corruptMatcher;

  /// Respond 503 to everything.
  bool offline = false;

  /// Sever the socket without responding.
  bool dropConnections = false;

  /// Reject writes whose `version` is <= the stored version with 409.
  bool enforceVersions = false;

  /// `'METHOD /path'` entries, in arrival order.
  final List<String> requestLog = [];

  /// Full request URIs (including query parameters), parallel to [requestLog].
  final List<Uri> requestUris = [];

  // --- Periodic chaos knobs (see ChaosProfile) -----------------------------

  /// Fail every Nth request with [failStatusCode] (1-based; null = off).
  int? failEveryNth;

  /// Sever every Nth request's socket without responding (null = off).
  int? dropEveryNth;

  /// Corrupt every Nth response body (null = off).
  int? corruptEveryNth;

  /// Random extra latency up to this much per request (null = off).
  Duration? jitter;

  final _random = math.Random(7);
  int _requestCounter = 0;

  // --- Change feed (cursor-based incremental pull) -------------------------

  /// Monotonically increasing change counter; every entity write bumps it.
  int changeSeq = 0;

  final Map<String, int> _seqByEntity = {};

  /// Server-clock receive time per row: what `modifiedSince` filters on, so
  /// writers' (possibly skewed) `modifiedAt` clocks never hide a row.
  final Map<String, DateTime> _receivedAt = {};

  void _touch(String userId, String id) {
    _seqByEntity['$userId/$id'] = ++changeSeq;
    _receivedAt['$userId/$id'] = DateTime.now();
  }

  /// Binds to a random loopback port.
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle, onError: (_) {});
  }

  /// Stops the server, severing open connections.
  Future<void> stop() async => _server?.close(force: true);

  /// Seeds an entity directly into storage (bypasses HTTP + faults).
  void seed(String userId, Map<String, dynamic> entity) {
    final id = entity['id'] as String;
    (storage[userId] ??= {})[id] = Map<String, dynamic>.from(entity);
    _touch(userId, id);
  }

  /// Mutates the stored remote metadata hash for [userId] so the engine's
  /// skip fast-path sees a difference and the next sync cycle actually runs.
  void pokeMetadata(String userId) {
    final meta = Map<String, dynamic>.from(
      metadata[userId] ?? {'userId': userId},
    );
    meta['dataHash'] = 'poked-${DateTime.now().microsecondsSinceEpoch}';
    metadata[userId] = meta;
  }

  /// Writes a 200 response whose body is not valid JSON (simulates proxy
  /// mangling / truncated payloads).
  Future<void> _corruptResponse(HttpRequest req, String garbage) async {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(garbage);
    await req.response.close();
  }

  Map<String, dynamic>? _find(String id, String? userId) {
    if (userId != null) return storage[userId]?[id];
    for (final byId in storage.values) {
      final hit = byId[id];
      if (hit != null) return hit;
    }
    return null;
  }

  Future<void> _handle(HttpRequest req) async {
    requestLog.add('${req.method} ${req.uri.path}');
    requestUris.add(req.uri);
    _requestCounter++;

    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (jitter != null) {
      await Future<void>.delayed(
        Duration(microseconds: _random.nextInt(jitter!.inMicroseconds + 1)),
      );
    }
    if (await _injectFault(req)) return;

    try {
      return await _route(req, req.uri.queryParameters['userId']);
    } on Object catch (e) {
      return _respond(req, 500, {'error': e.toString()});
    }
  }

  bool _isNth(int? n) => n != null && _requestCounter % n == 0;

  /// Applies the configured fault knobs; true when [req] was answered (or its
  /// socket severed) and must not reach a route.
  Future<bool> _injectFault(HttpRequest req) async {
    final path = req.uri.path;
    if (dropConnections || _isNth(dropEveryNth)) {
      final socket = await req.response.detachSocket(writeHeaders: false);
      socket.destroy();
      return true;
    }
    if (offline) {
      await _respond(req, 503, {'error': 'offline'});
    } else if (_isNth(failEveryNth)) {
      await _respond(req, failStatusCode, {
        'error': 'periodic injected failure',
      });
    } else if (remainingFailures > 0 &&
        (failMatcher?.call(req.method, path) ?? true)) {
      remainingFailures--;
      await _respond(req, failStatusCode, {'error': 'injected failure'});
    } else if (_isNth(corruptEveryNth)) {
      await _corruptResponse(req, '{{{chaos-corrupted%%%');
    } else if (corruptNextResponses > 0 &&
        (corruptMatcher?.call(req.method, path) ?? true)) {
      corruptNextResponses--;
      await _corruptResponse(req, '{{{this is not json%%%');
    } else {
      return false;
    }
    return true;
  }

  Future<void> _route(HttpRequest req, String? userId) => switch ((
    req.method,
    req.uri.pathSegments,
  )) {
    (_, []) => _respond(req, 404, {'error': 'not found'}),
    ('GET', ['health']) => _respond(req, 200, {'ok': true}),
    ('GET', ['entities']) => _listEntities(req, userId),
    ('GET', ['entities', final id]) => _respondFound(req, _find(id, userId)),
    ('POST', ['entities']) => _writeEntity(req, null, 201),
    ('PUT', ['entities', final id]) => _writeEntity(req, id, 200),
    ('PATCH', ['entities', final id]) => _patchEntity(req, id, userId),
    ('DELETE', ['entities', final id]) => _deleteEntity(req, id, userId),
    ('GET', ['changes']) => _changes(req, userId),
    ('GET', ['metadata', final uid]) => _respondFound(req, metadata[uid]),
    ('PUT', ['metadata', final uid]) => _putMetadata(req, uid),
    _ => _respond(req, 404, {
      'error': 'no route for ${req.method} ${req.uri.path}',
    }),
  };

  Future<void> _respondFound(HttpRequest req, Map<String, dynamic>? found) =>
      found == null
      ? _respond(req, 404, {'error': 'not found'})
      : _respond(req, 200, found);

  /// Whether a write carrying [incoming]'s `version` (or [missing] when
  /// absent) must be rejected against the stored [existing] row.
  bool _isStale(
    Map<String, dynamic> incoming,
    Map<String, dynamic>? existing, {
    int missing = 0,
  }) =>
      enforceVersions &&
      existing != null &&
      (incoming['version'] as int? ?? missing) <=
          (existing['version'] as int? ?? 0);

  Future<void> _listEntities(HttpRequest req, String? userId) async {
    // Incremental pull support: ?modifiedSince=<ISO-8601> returns only rows
    // the server RECEIVED at or after the watermark (server clock).
    final since = DateTime.tryParse(req.uri.queryParameters['modifiedSince'] ?? '');
    final items = [
      for (final MapEntry(key: uid, value: byId) in storage.entries)
        if (userId == null || uid == userId)
          for (final MapEntry(key: id, value: row) in byId.entries)
            if (since == null || !(_receivedAt['$uid/$id']?.isBefore(since) ?? true)) row,
    ];
    return _respond(req, 200, items);
  }

  /// POST (create/overwrite, id from the body) and PUT (id from the path).
  Future<void> _writeEntity(HttpRequest req, String? pathId, int status) async {
    final body = await _readBody(req);
    final uid = body['userId'] as String;
    final id = pathId ?? body['id'] as String;
    if (_isStale(body, storage[uid]?[id])) {
      return _respond(req, 409, {'error': 'stale version'});
    }
    (storage[uid] ??= {})[id] = body;
    _touch(uid, id);
    return _respond(req, status, body);
  }

  Future<void> _patchEntity(HttpRequest req, String id, String? userId) async {
    final existing = _find(id, userId);
    if (existing == null) return _respond(req, 404, {'error': 'not found'});
    final delta = await _readBody(req);
    if (_isStale(delta, existing, missing: 1 << 62)) {
      return _respond(req, 409, {'error': 'stale version'});
    }
    existing.addAll(delta);
    _touch(existing['userId'] as String? ?? userId ?? '', id);
    return _respond(req, 200, existing);
  }

  Future<void> _deleteEntity(HttpRequest req, String id, String? userId) {
    final uid =
        userId ??
        storage.keys.firstWhere(
          (u) => storage[u]!.containsKey(id),
          orElse: () => '',
        );
    final removed = storage[uid]?.remove(id) != null;
    // Hard deletes vanish from the change feed (documented limitation of
    // cursor pulls — use soft deletes).
    _seqByEntity.remove('$uid/$id');
    _receivedAt.remove('$uid/$id');
    return _respond(req, 200, {'deleted': removed});
  }

  /// Cursor-based change feed: rows written after the cursor, plus the next
  /// cursor. `cursor` absent/invalid = from the beginning.
  Future<void> _changes(HttpRequest req, String? userId) {
    final cursor = int.tryParse(req.uri.queryParameters['cursor'] ?? '') ?? 0;
    final items = <Map<String, dynamic>>[];
    for (final MapEntry(key: uid, value: byId) in storage.entries) {
      if (userId != null && uid != userId) continue;
      for (final MapEntry(key: id, value: entity) in byId.entries) {
        if ((_seqByEntity['$uid/$id'] ?? 0) > cursor) items.add(entity);
      }
    }
    return _respond(req, 200, {'items': items, 'nextCursor': '$changeSeq'});
  }

  Future<void> _putMetadata(HttpRequest req, String uid) async {
    metadata[uid] = await _readBody(req);
    return _respond(req, 200, {'ok': true});
  }

  Future<Map<String, dynamic>> _readBody(HttpRequest req) async {
    final text = await utf8.decodeStream(req);
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  }

  Future<void> _respond(HttpRequest req, int status, Object body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }
}
