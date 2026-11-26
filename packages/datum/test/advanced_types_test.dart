import 'package:datum/datum.dart';
import 'package:datum_generator/datum_generator.dart';

import 'package:test/test.dart';

part 'advanced_types_test.g.dart';

// Test enums
enum TaskPriority {
  low,
  medium,
  high,
  critical,
}

enum TaskStatus {
  pending,
  inProgress,
  completed,
  cancelled,
}

// Test entity with advanced types
@DatumSerializable(tableName: 'advanced_test_entities', generateMixin: true)
class AdvancedTestEntity extends DatumEntity with _$AdvancedTestEntityMixin {
  @override
  final String id;

  @override
  final String userId;

  // Enum fields
  final TaskPriority priority;
  final TaskStatus? status;

  // Duration fields
  final Duration timeout;
  final Duration? estimatedDuration;

  // Uri fields
  final Uri apiEndpoint;
  final Uri? documentationUrl;

  // BigInt fields
  final BigInt transactionId;
  final BigInt? optionalId;

  @override
  final DateTime createdAt;

  @override
  final DateTime modifiedAt;

  @override
  final int version;

  @override
  final bool isDeleted;

  const AdvancedTestEntity({
    required this.id,
    required this.userId,
    required this.priority,
    this.status,
    required this.timeout,
    this.estimatedDuration,
    required this.apiEndpoint,
    this.documentationUrl,
    required this.transactionId,
    this.optionalId,
    required this.createdAt,
    required this.modifiedAt,
    this.version = 1,
    this.isDeleted = false,
  });
}

void main() {
  group('Advanced Types - Enum Serialization', () {
    test('should serialize non-nullable enum to string', () {
      final entity = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.high,
        status: null,
        timeout: const Duration(minutes: 5),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = entity.toDatumMap();
      expect(map['priority'], equals('high'));
    });

    test('should serialize nullable enum to string', () {
      final entity = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.medium,
        status: TaskStatus.inProgress,
        timeout: const Duration(minutes: 5),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = entity.toDatumMap();
      expect(map['status'], equals('inProgress'));
    });

    test('should serialize nullable enum as null when null', () {
      final entity = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.low,
        status: null,
        timeout: const Duration(minutes: 5),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = entity.toDatumMap();
      expect(map['status'], isNull);
    });

    test('should deserialize enum from string', () {
      final map = {
        'id': '1',
        'user_id': 'user1',
        'priority': 'critical',
        'status': 'completed',
        'timeout': 300000000,
        'api_endpoint': 'https://api.example.com',
        'transaction_id': '12345',
        'createdAt': 1704067200000,
        'modifiedAt': 1704067200000,
      };

      final entity = AdvancedTestEntityFactory.fromMap(map);
      expect(entity.priority, equals(TaskPriority.critical));
      expect(entity.status, equals(TaskStatus.completed));
    });

    test('should deserialize null enum as null', () {
      final map = {
        'id': '1',
        'user_id': 'user1',
        'priority': 'low',
        'timeout': 300000000,
        'api_endpoint': 'https://api.example.com',
        'transaction_id': '12345',
        'createdAt': 1704067200000,
        'modifiedAt': 1704067200000,
      };

      final entity = AdvancedTestEntityFactory.fromMap(map);
      expect(entity.status, isNull);
    });
  });

  group('Advanced Types - Duration Serialization', () {
    test('should serialize Duration to microseconds', () {
      final entity = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.medium,
        timeout: const Duration(minutes: 5, seconds: 30),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = entity.toDatumMap();
      expect(map['timeout'], equals(330000000)); // 5.5 minutes in microseconds
    });

    test('should serialize nullable Duration', () {
      final entity = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.medium,
        timeout: const Duration(hours: 1),
        estimatedDuration: const Duration(minutes: 30),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = entity.toDatumMap();
      expect(map['estimated_duration'], equals(1800000000)); // 30 minutes
    });

    test('should deserialize Duration from microseconds', () {
      final map = {
        'id': '1',
        'user_id': 'user1',
        'priority': 'medium',
        'timeout': 300000000, // 5 minutes
        'estimated_duration': 600000000, // 10 minutes
        'api_endpoint': 'https://api.example.com',
        'transaction_id': '12345',
        'createdAt': 1704067200000,
        'modifiedAt': 1704067200000,
      };

      final entity = AdvancedTestEntityFactory.fromMap(map);
      expect(entity.timeout, equals(const Duration(minutes: 5)));
      expect(entity.estimatedDuration, equals(const Duration(minutes: 10)));
    });
  });

  group('Advanced Types - Uri Serialization', () {
    test('should serialize Uri to string', () {
      final entity = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.medium,
        timeout: const Duration(minutes: 5),
        apiEndpoint: Uri.parse('https://api.example.com/v1/tasks'),
        documentationUrl: Uri.parse('https://docs.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = entity.toDatumMap();
      expect(map['api_endpoint'], equals('https://api.example.com/v1/tasks'));
      expect(map['documentation_url'], equals('https://docs.example.com'));
    });

    test('should deserialize Uri from string', () {
      final map = {
        'id': '1',
        'user_id': 'user1',
        'priority': 'medium',
        'timeout': 300000000,
        'api_endpoint': 'https://api.example.com/v2',
        'documentation_url': 'https://docs.example.com/guide',
        'transaction_id': '12345',
        'createdAt': 1704067200000,
        'modifiedAt': 1704067200000,
      };

      final entity = AdvancedTestEntityFactory.fromMap(map);
      expect(entity.apiEndpoint.toString(), equals('https://api.example.com/v2'));
      expect(
        entity.documentationUrl.toString(),
        equals('https://docs.example.com/guide'),
      );
    });
  });

  group('Advanced Types - BigInt Serialization', () {
    test('should serialize BigInt to string', () {
      final entity = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.medium,
        timeout: const Duration(minutes: 5),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.parse('999999999999999999'),
        optionalId: BigInt.parse('123456789012345678'),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = entity.toDatumMap();
      expect(map['transaction_id'], equals('999999999999999999'));
      expect(map['optional_id'], equals('123456789012345678'));
    });

    test('should deserialize BigInt from string', () {
      final map = {
        'id': '1',
        'user_id': 'user1',
        'priority': 'medium',
        'timeout': 300000000,
        'api_endpoint': 'https://api.example.com',
        'transaction_id': '888888888888888888',
        'optional_id': '777777777777777777',
        'createdAt': 1704067200000,
        'modifiedAt': 1704067200000,
      };

      final entity = AdvancedTestEntityFactory.fromMap(map);
      expect(entity.transactionId, equals(BigInt.parse('888888888888888888')));
      expect(entity.optionalId, equals(BigInt.parse('777777777777777777')));
    });

    test('should handle very large BigInt values', () {
      final largeNumber = BigInt.parse('12345678901234567890123456789012345678901234567890');
      final entity = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.medium,
        timeout: const Duration(minutes: 5),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: largeNumber,
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = entity.toDatumMap();
      final deserialized = AdvancedTestEntityFactory.fromMap(map);

      expect(deserialized.transactionId, equals(largeNumber));
    });
  });

  group('Advanced Types - Round-trip Serialization', () {
    test('should maintain data integrity through serialization round-trip', () {
      final original = AdvancedTestEntity(
        id: 'test-id',
        userId: 'user-123',
        priority: TaskPriority.critical,
        status: TaskStatus.inProgress,
        timeout: const Duration(hours: 2, minutes: 30, seconds: 45),
        estimatedDuration: const Duration(days: 1, hours: 3),
        apiEndpoint: Uri.parse('https://api.example.com/v3/tasks?filter=active'),
        documentationUrl: Uri.parse('https://docs.example.com/api#tasks'),
        transactionId: BigInt.parse('999888777666555444333222111'),
        optionalId: BigInt.parse('111222333444555666777888999'),
        createdAt: DateTime(2024, 6, 15, 10, 30, 45),
        modifiedAt: DateTime(2024, 6, 15, 14, 20, 30),
        version: 5,
        isDeleted: false,
      );

      // Serialize
      final map = original.toDatumMap();

      // Deserialize
      final deserialized = AdvancedTestEntityFactory.fromMap(map);

      // Verify all fields match
      expect(deserialized.id, equals(original.id));
      expect(deserialized.userId, equals(original.userId));
      expect(deserialized.priority, equals(original.priority));
      expect(deserialized.status, equals(original.status));
      expect(deserialized.timeout, equals(original.timeout));
      expect(deserialized.estimatedDuration, equals(original.estimatedDuration));
      expect(deserialized.apiEndpoint, equals(original.apiEndpoint));
      expect(deserialized.documentationUrl, equals(original.documentationUrl));
      expect(deserialized.transactionId, equals(original.transactionId));
      expect(deserialized.optionalId, equals(original.optionalId));
      expect(deserialized.version, equals(original.version));
      expect(deserialized.isDeleted, equals(original.isDeleted));
    });

    test('should handle all null optional fields', () {
      final original = AdvancedTestEntity(
        id: 'test-id',
        userId: 'user-123',
        priority: TaskPriority.low,
        status: null,
        timeout: const Duration(minutes: 1),
        estimatedDuration: null,
        apiEndpoint: Uri.parse('https://api.example.com'),
        documentationUrl: null,
        transactionId: BigInt.from(1),
        optionalId: null,
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = original.toDatumMap();
      final deserialized = AdvancedTestEntityFactory.fromMap(map);

      expect(deserialized.status, isNull);
      expect(deserialized.estimatedDuration, isNull);
      expect(deserialized.documentationUrl, isNull);
      expect(deserialized.optionalId, isNull);
    });
  });

  group('Advanced Types - Equality and Hashing', () {
    test('should consider entities with same advanced type values as equal', () {
      final entity1 = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.high,
        status: TaskStatus.completed,
        timeout: const Duration(minutes: 10),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final entity2 = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.high,
        status: TaskStatus.completed,
        timeout: const Duration(minutes: 10),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      expect(entity1, equals(entity2));
      expect(entity1.hashCode, equals(entity2.hashCode));
    });

    test('should consider entities with different enum values as not equal', () {
      final entity1 = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.high,
        timeout: const Duration(minutes: 10),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final entity2 = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.low, // Different
        timeout: const Duration(minutes: 10),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      expect(entity1, isNot(equals(entity2)));
    });
  });

  group('Advanced Types - Diff Tracking', () {
    test('should detect changes in enum fields', () {
      final old = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.low,
        timeout: const Duration(minutes: 10),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = old.toDatumMap();
      map['priority'] = 'high';
      map['modifiedAt'] = DateTime(2024, 1, 2).millisecondsSinceEpoch;
      final updated = AdvancedTestEntityFactory.fromMap(map);

      final diff = updated.diff(old);
      expect(diff, isNotNull);
      expect(diff!['priority'], equals('high'));
    });

    test('should detect changes in Duration fields', () {
      final old = AdvancedTestEntity(
        id: '1',
        userId: 'user1',
        priority: TaskPriority.medium,
        timeout: const Duration(minutes: 5),
        apiEndpoint: Uri.parse('https://api.example.com'),
        transactionId: BigInt.from(12345),
        createdAt: DateTime(2024, 1, 1),
        modifiedAt: DateTime(2024, 1, 1),
      );

      final map = old.toDatumMap();
      map['timeout'] = const Duration(minutes: 10).inMicroseconds;
      map['modifiedAt'] = DateTime(2024, 1, 2).millisecondsSinceEpoch;
      final updated = AdvancedTestEntityFactory.fromMap(map);

      final diff = updated.diff(old);
      expect(diff, isNotNull);
      expect(diff!['timeout'], equals(const Duration(minutes: 10).inMicroseconds));
    });
  });

  group('Advanced Types - Query Builder', () {
    test('should build type-safe queries for AdvancedTestEntity', () {
      final query = DatumQueryBuilder<AdvancedTestEntity>().whereTimeout(isGreaterThan: const Duration(minutes: 5)).orderByTimeout(descending: true).whereApiEndpoint(startsWith: 'https').build();

      expect(query.filters.length, 2);

      final timeoutFilter = query.filters.first as Filter;
      expect(timeoutFilter.field, 'timeout');
      expect(timeoutFilter.operator, FilterOperator.greaterThan);
      expect(timeoutFilter.value, const Duration(minutes: 5).inMicroseconds);

      final uriFilter = query.filters[1] as Filter;
      expect(uriFilter.field, 'api_endpoint');
      expect(uriFilter.operator, FilterOperator.startsWith);
      expect(uriFilter.value, 'https');

      expect(query.sorting.length, 1);
      expect(query.sorting.first.field, 'timeout');
      expect(query.sorting.first.descending, isTrue);
    });

    test('should handle Enum in Query Builder', () {
      final query = DatumQueryBuilder<AdvancedTestEntity>().wherePriority(isEqualTo: TaskPriority.high).build();

      final filter = query.filters.first as Filter;
      expect(filter.field, 'priority');
      expect(filter.value, 'high');
    });
  });
}
