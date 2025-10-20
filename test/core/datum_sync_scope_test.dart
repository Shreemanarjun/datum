import 'package:datum/datum.dart';
import 'package:test/test.dart';

void main() {
  group('DatumSyncScope', () {
    test('default constructor creates a scope with a default (empty) query',
        () {
      // Arrange & Act
      const scope = DatumSyncScope();

      // Assert
      expect(scope.query, isA<DatumQuery>());
      expect(scope.query.filters, isEmpty);
      expect(scope.query.sorting, isEmpty);
    });

    test('constructor correctly assigns the provided query', () {
      // Arrange & Act
      final query = DatumQuery(
        filters: const [Filter('status', FilterOperator.equals, 'active')],
        sorting: const [SortDescriptor('createdAt', descending: true)],
      );
      final scope = DatumSyncScope(query: query);

      // Assert
      expect(scope.query, same(query));
      expect(scope.query.filters, hasLength(1));
      expect(
        (scope.query.filters.first as Filter).field,
        'status',
      );
      expect(scope.query.sorting, hasLength(1));
    });
  });
}
