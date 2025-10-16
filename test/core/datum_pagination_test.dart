import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/test_entity.dart';

void main() {
  group('PaginationConfig', () {
    test('constructor provides correct default values', () {
      const config = PaginationConfig();
      expect(config.pageSize, 50);
      expect(config.currentPage, isNull);
      expect(config.cursor, isNull);
    });

    test('constructor sets values correctly', () {
      const config = PaginationConfig(pageSize: 20, currentPage: 2);
      expect(config.pageSize, 20);
      expect(config.currentPage, 2);
      expect(config.cursor, isNull);
    });

    test('supports value equality', () {
      const config1 = PaginationConfig(pageSize: 20, currentPage: 2);
      const config2 = PaginationConfig(pageSize: 20, currentPage: 2);
      const config3 = PaginationConfig(pageSize: 10, currentPage: 2);

      expect(config1, equals(config2));
      expect(config1.hashCode, equals(config2.hashCode));
      expect(config1, isNot(equals(config3)));
    });
  });

  group('PaginatedResult', () {
    final testItems = [TestEntity.create('e1', 'u1', 'Item 1')];

    test('constructor sets all fields correctly', () {
      final paginatedResult = PaginatedResult<TestEntity>(
        items: testItems,
        totalCount: 10,
        currentPage: 2,
        totalPages: 5,
        hasMore: true,
        nextCursor: 'cursor-abc',
      );

      expect(paginatedResult.items, testItems);
      expect(paginatedResult.totalCount, 10);
      expect(paginatedResult.currentPage, 2);
      expect(paginatedResult.totalPages, 5);
      expect(paginatedResult.hasMore, isTrue);
      expect(paginatedResult.nextCursor, 'cursor-abc');
    });

    test('empty() constructor creates a correct empty result', () {
      const emptyResult = PaginatedResult<TestEntity>.empty();

      expect(emptyResult.items, isEmpty);
      expect(emptyResult.totalCount, 0);
      expect(emptyResult.currentPage, 1);
      expect(emptyResult.totalPages, 0);
      expect(emptyResult.hasMore, isFalse);
      expect(emptyResult.nextCursor, isNull);
    });

    test('supports value equality', () {
      final result1 = PaginatedResult<TestEntity>(
        items: testItems,
        totalCount: 10,
        currentPage: 2,
        totalPages: 5,
        hasMore: true,
        nextCursor: 'cursor-abc',
      );

      final result2 = PaginatedResult<TestEntity>(
        items: testItems,
        totalCount: 10,
        currentPage: 2,
        totalPages: 5,
        hasMore: true,
        nextCursor: 'cursor-abc',
      );

      final result3 = PaginatedResult<TestEntity>(
        items: testItems,
        totalCount: 11, // Different totalCount
        currentPage: 2,
        totalPages: 5,
        hasMore: true,
        nextCursor: 'cursor-abc',
      );

      expect(result1, equals(result2));
      expect(result1.hashCode, equals(result2.hashCode));
      expect(result1, isNot(equals(result3)));
    });
  });
}
