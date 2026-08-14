---




title: REST API Remote Adapter
---

This guide shows how to implement a complete REST API remote adapter for Datum.

## Overview

This adapter provides a generic implementation for connecting to REST APIs. It handles authentication, error handling, and all the required Datum operations.

## Implementation

```dart
import 'dart:convert';
import 'package:datum/datum.dart';
import 'package:http/http.dart' as http;

class RestRemoteAdapter<T extends DatumEntityInterface> extends RemoteAdapter<T> {
  final String baseUrl;
  final String resourcePath;
  final T Function(Map<String, dynamic>) fromMap;
  final Map<String, String> Function(T)? toJsonMap;
  final String? authToken;

  RestRemoteAdapter({
    required this.baseUrl,
    required this.resourcePath,
    required this.fromMap,
    this.toJsonMap,
    this.authToken,
  });

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (authToken != null) 'Authorization': 'Bearer $authToken',
  };

  Uri _buildUri(String path, [Map<String, String>? queryParams]) {
    final uri = Uri.parse('$baseUrl/$resourcePath/$path');
    if (queryParams != null) {
      return uri.replace(queryParameters: queryParams);
    }
    return uri;
  }

  @override
  Future<void> initialize() async {
    // Any initialization logic here
  }

  @override
  Future<void> dispose() async {
    // Cleanup resources
  }

  @override
  Future<AdapterHealthStatus> checkHealth() async {
    try {
      final response = await http.get(_buildUri('health'), headers: _headers);
      return response.statusCode == 200
          ? AdapterHealthStatus.healthy
          : AdapterHealthStatus.unhealthy;
    } catch (e) {
      return AdapterHealthStatus.unhealthy;
    }
  }

  @override
  Future<bool> isConnected() async {
    try {
      final response = await http.head(Uri.parse(baseUrl), headers: _headers);
      return response.statusCode < 500;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    try {
      final response = await http.get(
        _buildUri(id, userId != null ? {'userId': userId} : null),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return fromMap(data);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to read entity: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error during read: $e');
    }
  }

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) async {
    try {
      final queryParams = <String, String>{};
      if (userId != null) {
        queryParams['userId'] = userId;
      }

      // Add scope filters if provided
      if (scope != null) {
        for (final filter in scope.query.filters) {
          if (filter is Filter) {
            queryParams['filter[${filter.field}]'] = '${filter.operator.name}:${filter.value}';
          }
        }
      }

      final response = await http.get(
        _buildUri('', queryParams.isNotEmpty ? queryParams : null),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.map((item) => fromMap(item)).toList();
      } else {
        throw Exception('Failed to read entities: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error during readAll: $e');
    }
  }

  @override
  Future<void> create(T entity) async {
    try {
      final jsonData = toJsonMap?.call(entity) ?? entity.toDatumMap();
      final response = await http.post(
        _buildUri(''),
        headers: _headers,
        body: json.encode(jsonData),
      );

      if (response.statusCode != 201 && response.statusCode != 200) {
        throw Exception('Failed to create entity: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error during create: $e');
    }
  }

  @override
  Future<void> update(T entity) async {
    try {
      final jsonData = toJsonMap?.call(entity) ?? entity.toDatumMap();
      final response = await http.put(
        _buildUri(entity.id),
        headers: _headers,
        body: json.encode(jsonData),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update entity: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error during update: $e');
    }
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    try {
      final response = await http.delete(
        _buildUri(id, userId != null ? {'userId': userId} : null),
        headers: _headers,
      );

      if (response.statusCode == 404) return false;
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete entity: ${response.statusCode}');
      }
      return true;
    } catch (e) {
      throw Exception('Network error during delete: $e');
    }
  }

  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    try {
      final response = await http.patch(
        _buildUri(id, userId != null ? {'userId': userId} : null),
        headers: _headers,
        body: json.encode(delta),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return fromMap(data);
      } else {
        throw Exception('Failed to patch entity: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error during patch: $e');
    }
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    try {
      final queryParams = <String, String>{};
      if (userId != null) {
        queryParams['userId'] = userId;
      }

      // Add filters
      for (final filter in query.filters) {
        if (filter is Filter) {
          queryParams['filter[${filter.field}]'] = '${filter.operator.name}:${filter.value}';
        }
      }

      // Add sorting
      for (final sort in query.sorting) {
        queryParams['sort[${sort.field}]'] = sort.descending ? 'desc' : 'asc';
      }

      // Add pagination
      if (query.limit != null) {
        queryParams['limit'] = query.limit.toString();
      }
      if ((query.offset ?? 0) > 0) {
        queryParams['offset'] = query.offset.toString();
      }

      final response = await http.get(
        _buildUri('query', queryParams),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.map((item) => fromMap(item)).toList();
      } else {
        throw Exception('Failed to query entities: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error during query: $e');
    }
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    try {
      final response = await http.get(
        _buildUri('../sync-metadata/$userId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DatumSyncMetadata.fromMap(data);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get sync metadata: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error during getSyncMetadata: $e');
    }
  }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {
    try {
      final response = await http.put(
        _buildUri('../sync-metadata/$userId'),
        headers: _headers,
        body: json.encode(metadata.toMap()),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update sync metadata: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error during updateSyncMetadata: $e');
    }
  }

  @override
  Stream<DatumChangeDetail<T>>? get changeStream {
    // REST APIs typically don't support real-time streams
    // Consider using WebSockets or Server-Sent Events for real-time updates
    return null;
  }
}
```

> **Reference implementation:** the `datum_test` package ships `HttpRemoteAdapter`,
> a complete REST adapter (including `DeltaSyncCapable` incremental pulls and
> Datum's exception taxonomy) that you can use as a production-grade template.

## Usage Example

```dart
import 'rest_remote_adapter.dart'; // the adapter implemented above

// Create the adapter
final taskAdapter = RestRemoteAdapter<Task>(
  baseUrl: 'https://api.example.com',
  resourcePath: 'tasks',
  fromMap: (map) => Task.fromMap(map),
  authToken: 'your-jwt-token',
);

// Register with Datum
final registrations = [
  DatumRegistration<Task>(
    localAdapter: HiveLocalAdapter<Task>(
      entityBoxName: 'tasks',
      fromMap: (map) => Task.fromMap(map),
    ),
    remoteAdapter: taskAdapter,
  ),
];
```

## Backend API Requirements

Your REST API should implement these endpoints:

### CRUD Operations
- `GET /tasks/:id` - Get single task
- `GET /tasks` - Get all tasks (supports query parameters)
- `POST /tasks` - Create new task
- `PUT /tasks/:id` - Update existing task
- `PATCH /tasks/:id` - Partial update task
- `DELETE /tasks/:id` - Delete task

### Query Support
- `GET /tasks/query` - Advanced querying with filters, sorting, pagination

### Sync Metadata
- `GET /sync-metadata/:userId` - Get sync metadata
- `PUT /sync-metadata/:userId` - Update sync metadata

### Health Check
- `GET /health` - Health check endpoint

## Features

- **Generic REST API Support**: Works with any REST API following common conventions
- **Authentication**: JWT token support with Bearer authentication
- **Error Handling**: Comprehensive error handling for network issues
- **Query Support**: Advanced filtering, sorting, and pagination
- **Health Monitoring**: Built-in health checks
- **Sync Metadata**: Full sync metadata management

## Configuration Options

- **Base URL**: Configure the API base URL
- **Resource Path**: Specify the resource endpoint path
- **Authentication**: JWT token or custom auth headers
- **Custom Mapping**: Transform data between API and Datum formats
- **Timeout Configuration**: Set request timeouts
- **Retry Logic**: Implement retry strategies for failed requests
