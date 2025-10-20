import 'package:flutter_test/flutter_test.dart';
import 'package:example/shared/exception/base_exception.dart';

void main() {
  group('BaseException', () {
    // Test 1: Default message
    test('should have default message "Unknown Error"', () {
      final exception = BaseException();
      expect(exception.message, equals('Unknown Error'));
    });

    // Test 2: Custom message
    test('should accept and store a custom message', () {
      const customMessage = 'Custom Error Message';
      final exception = BaseException(message: customMessage);
      expect(exception.message, equals(customMessage));
    });
  });
}
