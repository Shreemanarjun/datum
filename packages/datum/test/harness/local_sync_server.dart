import 'dart:convert';
import 'dart:io';

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

  /// Binds to a random loopback port.
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle, onError: (_) {});
  }

  /// Stops the server, severing open connections.
  Future<void> stop() async => _server?.close(force: true);

  /// Seeds an entity directly into storage (bypasses HTTP + faults).
  void seed(String userId, Map<String, dynamic> entity) => (storage[userId] ??= {})[entity['id'] as String] = Map<String, dynamic>.from(entity);

  Map<String, dynamic>? _find(String id, String? userId) {
    if (userId != null) return storage[userId]?[id];
    for (final byId in storage.values) {
      final hit = byId[id];
      if (hit != null) return hit;
    }
    return null;
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    requestLog.add('${req.method} $path');

    if (latency > Duration.zero) await Future<void>.delayed(latency);

    if (dropConnections) {
      final socket = await req.response.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    }
    if (offline) return _respond(req, 503, {'error': 'offline'});
    if (remainingFailures > 0 && (failMatcher?.call(req.method, path) ?? true)) {
      remainingFailures--;
      return _respond(req, failStatusCode, {'error': 'injected failure'});
    }
    if (corruptNextResponses > 0 && (corruptMatcher?.call(req.method, path) ?? true)) {
      corruptNextResponses--;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{{{this is not json%%%');
      await req.response.close();
      return;
    }

    try {
      final segments = req.uri.pathSegments;
      final userId = req.uri.queryParameters['userId'];

      if (segments.isEmpty) return _respond(req, 404, {'error': 'not found'});

      switch ((req.method, segments)) {
        case ('GET', ['health']):
          return _respond(req, 200, {'ok': true});

        case ('GET', ['entities']):
          final items = userId != null ? (storage[userId]?.values.toList() ?? []) : storage.values.expand((m) => m.values).toList();
          return _respond(req, 200, items);

        case ('GET', ['entities', final id]):
          final found = _find(id, userId);
          return found == null ? _respond(req, 404, {'error': 'not found'}) : _respond(req, 200, found);

        case ('POST', ['entities']):
          final body = await _readBody(req);
          final uid = body['userId'] as String;
          if (enforceVersions) {
            final existing = storage[uid]?[body['id'] as String];
            if (existing != null && (body['version'] as int? ?? 0) <= (existing['version'] as int? ?? 0)) {
              return _respond(req, 409, {'error': 'stale version'});
            }
          }
          (storage[uid] ??= {})[body['id'] as String] = body;
          return _respond(req, 201, body);

        case ('PUT', ['entities', final id]):
          final body = await _readBody(req);
          final uid = body['userId'] as String;
          if (enforceVersions) {
            final existing = storage[uid]?[id];
            if (existing != null && (body['version'] as int? ?? 0) <= (existing['version'] as int? ?? 0)) {
              return _respond(req, 409, {'error': 'stale version'});
            }
          }
          (storage[uid] ??= {})[id] = body;
          return _respond(req, 200, body);

        case ('PATCH', ['entities', final id]):
          final existing = _find(id, userId);
          if (existing == null) return _respond(req, 404, {'error': 'not found'});
          final delta = await _readBody(req);
          if (enforceVersions && (delta['version'] as int? ?? 1 << 62) <= (existing['version'] as int? ?? 0)) {
            return _respond(req, 409, {'error': 'stale version'});
          }
          existing.addAll(delta);
          return _respond(req, 200, existing);

        case ('DELETE', ['entities', final id]):
          final uid = userId ?? storage.keys.firstWhere((u) => storage[u]!.containsKey(id), orElse: () => '');
          final removed = storage[uid]?.remove(id) != null;
          return _respond(req, 200, {'deleted': removed});

        case ('GET', ['metadata', final uid]):
          final meta = metadata[uid];
          return meta == null ? _respond(req, 404, {'error': 'not found'}) : _respond(req, 200, meta);

        case ('PUT', ['metadata', final uid]):
          metadata[uid] = await _readBody(req);
          return _respond(req, 200, {'ok': true});

        default:
          return _respond(req, 404, {'error': 'no route for ${req.method} $path'});
      }
    } on Object catch (e) {
      return _respond(req, 500, {'error': e.toString()});
    }
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
