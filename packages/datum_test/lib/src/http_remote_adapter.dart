import 'dart:convert';
import 'dart:io';

import 'package:datum/datum.dart';

/// A real HTTP-backed [RemoteAdapter] used with [LocalSyncServer] to exercise
/// the engine over actual sockets. Maps transport/HTTP failures onto Datum's
/// exception taxonomy exactly the way a production REST adapter should:
///
/// - connection errors (socket/HTTP-parse)     → [NetworkException] (retryable)
/// - HTTP 5xx                                  → [NetworkException] (retryable)
/// - HTTP 404                                  → [EntityNotFoundException]
/// - HTTP 409                                  → [ConflictException]
/// - other non-2xx                             → [NetworkException] (not retryable)
class HttpRemoteAdapter<T extends DatumEntityInterface> extends RemoteAdapter<T>
    with DeltaSyncCapable<T> {
  HttpRemoteAdapter({required this.baseUri, required this.fromMap});

  final Uri baseUri;
  final T Function(Map<String, dynamic> map) fromMap;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  @override
  String get name => 'HttpRemoteAdapter';

  @override
  Future<void> initialize() async {}

  @override
  Stream<DatumChangeDetail<T>>? get changeStream => null;

  @override
  Future<void> dispose() async => _client.close(force: true);

  Future<(int, String)> _request(
    String method,
    String path, {
    String? userId,
    Object? body,
    Map<String, String>? query,
  }) async {
    try {
      final params = {'userId': ?userId, ...?query};
      final uri = baseUri.replace(
        path: path,
        queryParameters: params.isEmpty ? null : params,
      );
      final request = await _client.openUrl(method, uri);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      return (response.statusCode, text);
    } on SocketException catch (e) {
      throw NetworkException(
        message: 'Connection failed: ${e.message}',
        isRetryable: true,
      );
    } on HttpException catch (e) {
      // Includes "connection closed before full header" (severed sockets).
      throw NetworkException(
        message: 'HTTP transport error: ${e.message}',
        isRetryable: true,
      );
    }
  }

  /// Decodes a JSON body, mapping malformed payloads (proxy mangling,
  /// truncation) onto Datum's [SerializationException].
  Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw SerializationException(
        message: 'Malformed response from remote: ${e.message}',
      );
    }
  }

  Never _fail(int status, String body, {String? id}) {
    if (status == 404) {
      throw EntityNotFoundException(
        message: 'Entity ${id ?? '?'} not found on remote',
      );
    }
    if (status == 409) {
      throw ConflictException(
        message: 'Remote rejected write (version conflict): $body',
      );
    }
    throw NetworkException(
      message: 'Server responded $status: $body',
      isRetryable: status >= 500,
    );
  }

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) =>
      _readEntities(userId: userId, scope: scope);

  @override
  Future<List<T>> readSince(
    DateTime since, {
    String? userId,
    DatumSyncScope? scope,
  }) => _readEntities(
    userId: userId,
    scope: scope,
    query: {'modifiedSince': since.toIso8601String()},
  );

  Future<List<T>> _readEntities({
    String? userId,
    DatumSyncScope? scope,
    Map<String, String>? query,
  }) async {
    final (status, text) = await _request(
      'GET',
      '/entities',
      userId: userId,
      query: query,
    );
    if (status != 200) _fail(status, text);
    final items = (_decode(text) as List)
        .map((raw) => fromMap(Map<String, dynamic>.from(raw as Map)))
        .toList();
    if (scope != null) {
      return DatumQueryMatcher.apply(items, scope.query);
    }
    return items;
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    final (status, text) = await _request(
      'GET',
      '/entities/$id',
      userId: userId,
    );
    if (status == 404) return null;
    if (status != 200) _fail(status, text, id: id);
    return fromMap(Map<String, dynamic>.from(_decode(text) as Map));
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    return DatumQueryMatcher.apply(await readAll(userId: userId), query);
  }

  @override
  Future<void> create(T entity) async {
    final (status, text) = await _request(
      'POST',
      '/entities',
      body: entity.toDatumMap(target: MapTarget.remote),
    );
    if (status != 200 && status != 201) _fail(status, text, id: entity.id);
  }

  @override
  Future<void> update(T entity) async {
    final (status, text) = await _request(
      'PUT',
      '/entities/${entity.id}',
      body: entity.toDatumMap(target: MapTarget.remote),
    );
    if (status != 200) _fail(status, text, id: entity.id);
  }

  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    final (status, text) = await _request(
      'PATCH',
      '/entities/$id',
      userId: userId,
      body: delta,
    );
    if (status != 200) _fail(status, text, id: id);
    return fromMap(Map<String, dynamic>.from(_decode(text) as Map));
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    final (status, text) = await _request(
      'DELETE',
      '/entities/$id',
      userId: userId,
    );
    if (status != 200) _fail(status, text, id: id);
    return (_decode(text) as Map)['deleted'] as bool;
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    final (status, text) = await _request('GET', '/metadata/$userId');
    if (status == 404) return null;
    if (status != 200) _fail(status, text);
    return DatumSyncMetadata.fromMap(
      Map<String, dynamic>.from(_decode(text) as Map),
    );
  }

  @override
  Future<void> updateSyncMetadata(
    DatumSyncMetadata metadata,
    String userId,
  ) async {
    final (status, text) = await _request(
      'PUT',
      '/metadata/$userId',
      body: metadata.toMap(),
    );
    if (status != 200) _fail(status, text);
  }

  @override
  Future<bool> isConnected() async {
    try {
      final (status, _) = await _request('GET', '/health');
      return status == 200;
    } on Object {
      return false;
    }
  }
}

/// [HttpRemoteAdapter] variant that pulls incrementally from the server's
/// **change feed** (`GET /changes?cursor=`) via [CursorSyncCapable] — the
/// reference implementation of cursor-based delta sync. Kept as a separate
/// type so the base adapter continues to exercise the timestamp
/// ([DeltaSyncCapable]) path; the engine prefers the cursor path when an
/// adapter advertises both.
class CursorHttpRemoteAdapter<T extends DatumEntityInterface>
    extends HttpRemoteAdapter<T>
    with CursorSyncCapable<T> {
  CursorHttpRemoteAdapter({required super.baseUri, required super.fromMap});

  @override
  Future<CursorPage<T>> readChanges(
    String? cursor, {
    String? userId,
    DatumSyncScope? scope,
  }) async {
    final (status, text) = await _request(
      'GET',
      '/changes',
      userId: userId,
      query: {'cursor': ?cursor},
    );
    if (status != 200) _fail(status, text);
    final body = Map<String, dynamic>.from(_decode(text) as Map);
    var items = (body['items'] as List)
        .map((raw) => fromMap(Map<String, dynamic>.from(raw as Map)))
        .toList();
    if (scope != null) {
      items = DatumQueryMatcher.apply(items, scope.query);
    }
    return (items: items, nextCursor: body['nextCursor'] as String);
  }
}
