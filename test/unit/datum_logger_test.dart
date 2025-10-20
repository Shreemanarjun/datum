import 'package:datum/source/utils/datum_logger.dart';
import 'package:test/test.dart';

void main() {
  group('DatumLogger', () {
    group('copyWith', () {
      test('creates a new instance with the updated value', () {
        // Arrange
        final logger = DatumLogger(enabled: true);

        // Act
        final newLogger = logger.copyWith(enabled: false);

        // Assert
        expect(newLogger.enabled, isFalse);
        expect(logger.enabled, isTrue); // Original should be unchanged
        expect(newLogger, isNot(same(logger))); // Should be a new instance
      });

      test('creates a copy with the same value if no new value is provided',
          () {
        // Arrange
        final logger = DatumLogger(enabled: false);

        // Act
        final newLogger = logger.copyWith();

        // Assert
        expect(newLogger.enabled, isFalse);
        expect(newLogger, isNot(same(logger)));
      });

      test('can enable a disabled logger', () {
        // Arrange
        final logger = DatumLogger(enabled: false);
        final newLogger = logger.copyWith(enabled: true);
        expect(newLogger.enabled, isTrue);
      });
    });
  });
}
