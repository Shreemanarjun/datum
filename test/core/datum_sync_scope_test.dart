import 'package:datum/source/core/models/datum_sync_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatumSyncScope', () {
    test('default constructor has correct default values', () {
      // Arrange & Act
      const scope = DatumSyncScope();

      // Assert
      expect(scope.filters, isEmpty);
      expect(scope.trigger, DatumSyncTrigger.user);
    });

    test('filter constructor sets filters and default trigger', () {
      // Arrange & Act
      const filters = {'minDate': '2023-01-01'};
      const scope = DatumSyncScope.filter(filters);

      // Assert
      expect(scope.filters, filters);
      expect(scope.trigger, DatumSyncTrigger.user);
    });

    test('trigger constructor sets trigger and default filters', () {
      // Arrange & Act
      const scope = DatumSyncScope.trigger(DatumSyncTrigger.entity);

      // Assert
      expect(scope.filters, isEmpty);
      expect(scope.trigger, DatumSyncTrigger.entity);
    });
  });
}
