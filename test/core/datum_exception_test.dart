import 'package:datum/source/core/models/datum_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Datum Exceptions toString()', () {
    test('NetworkException formats correctly', () {
      final retryableException = NetworkException('Connection timed out');
      final nonRetryableException = NetworkException(
        'Bad request',
        isRetryable: false,
      );

      expect(
        retryableException.toString(),
        'NetworkException: Connection timed out (retryable: true)',
      );
      expect(
        nonRetryableException.toString(),
        'NetworkException: Bad request (retryable: false)',
      );
    });

    test('MigrationException formats correctly', () {
      final exception = MigrationException('Schema version mismatch');
      expect(
        exception.toString(),
        'MigrationException: Schema version mismatch',
      );
    });

    test('UserSwitchException formats correctly', () {
      final exception = UserSwitchException(
        'user-old',
        'user-new',
        'Unsynced data exists.',
      );
      expect(
        exception.toString(),
        'UserSwitchException: Unsynced data exists. (from: user-old, to: user-new)',
      );
    });

    test('AdapterException formats correctly without stack trace', () {
      final exception = AdapterException(
        'MockAdapter',
        'Failed to read from disk',
      );
      expect(
        exception.toString(),
        'AdapterException in MockAdapter: Failed to read from disk',
      );
    });

    test('AdapterException formats correctly with stack trace', () {
      final stackTrace = StackTrace.current;
      final exception = AdapterException(
        'MockAdapter',
        'Failed to write',
        stackTrace,
      );
      expect(
        exception.toString(),
        'AdapterException in MockAdapter: Failed to write\n$stackTrace',
      );
    });

    test('EntityNotFoundException formats correctly', () {
      final exception = EntityNotFoundException('Entity with ID 123 not found');
      expect(
        exception.toString(),
        'EntityNotFoundException: Entity with ID 123 not found',
      );
    });
  });
}
