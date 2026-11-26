import 'package:datum/source/core/errors/datum_exception.dart';
import 'package:test/test.dart';

void main() {
  group('DatumException', () {
    test('should have correct equality when all properties are the same', () {
      const exception1 = DatumException(
        code: DatumExceptionCode.unknown,
        message: 'Test message',
        details: {'key': 'value'},
      );
      const exception2 = DatumException(
        code: DatumExceptionCode.unknown,
        message: 'Test message',
        details: {'key': 'value'},
      );
      const exception3 = DatumException(
        code: DatumExceptionCode.networkError,
        message: 'Test message',
        details: {'key': 'value'},
      );
      const exception4 = DatumException(
        code: DatumExceptionCode.unknown,
        message: 'Different message',
        details: {'key': 'value'},
      );
      const exception5 = DatumException(
        code: DatumExceptionCode.unknown,
        message: 'Test message',
        details: {'anotherKey': 'anotherValue'},
      );

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
      expect(exception1, isNot(equals(exception4)));
      expect(exception1, isNot(equals(exception5)));
    });

    test('should have correct string representation', () {
      const exception = DatumException(
        code: DatumExceptionCode.unknown,
        message: 'Something went wrong',
      );
      expect(exception.toString(), 'DatumException(unknown): Something went wrong');

      const exceptionWithDetails = DatumException(
        code: DatumExceptionCode.adapterError,
        message: 'Adapter failed',
        details: {'errorType': 'connection', 'statusCode': 500},
      );
      expect(exceptionWithDetails.toString(), 'DatumException(adapterError): Adapter failed Details: {errorType: connection, statusCode: 500}');
    });

    test('fromError factory should create a DatumException from an error object', () {
      final error = Exception('Original error');
      final stackTrace = StackTrace.current;
      final datumException = DatumException.fromError(
        error,
        code: DatumExceptionCode.serializationError,
        message: 'Failed to serialize data',
        stackTrace: stackTrace,
      );

      expect(datumException.code, DatumExceptionCode.serializationError);
      expect(datumException.message, 'Failed to serialize data');
      expect(datumException.details, containsPair('originalError', 'Exception: Original error'));
      expect(datumException.details, containsPair('stackTrace', stackTrace.toString()));
    });
  });

  group('NetworkException', () {
    test('should have correct equality', () {
      const exception1 = NetworkException(message: 'No internet', isRetryable: true);
      const exception2 = NetworkException(message: 'No internet', isRetryable: true);
      const exception3 = NetworkException(message: 'No internet', isRetryable: false);
      const exception4 = NetworkException(message: 'Timeout', isRetryable: true);

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
      expect(exception1, isNot(equals(exception4)));
    });

    test('should have correct string representation', () {
      const exception = NetworkException(message: 'Network issue');
      expect(exception.toString(), 'DatumException(networkError): Network issue');
    });
  });

  group('UserSwitchException', () {
    test('should have correct equality', () {
      const exception1 = UserSwitchException(message: 'User switch failed', oldUserId: 'user1', newUserId: 'user2');
      const exception2 = UserSwitchException(message: 'User switch failed', oldUserId: 'user1', newUserId: 'user2');
      const exception3 = UserSwitchException(message: 'User switch failed', oldUserId: 'user1', newUserId: 'user3');

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = UserSwitchException(message: 'Failed to switch', oldUserId: 'oldUser', newUserId: 'newUser');
      expect(exception.toString(), 'UserSwitchException(oldUserId: oldUser, newUserId: newUser,message: Failed to switch,code: DatumExceptionCode.userSwitchError)');
    });
  });

  group('AdapterException', () {
    test('should have correct equality', () {
      final stackTrace = StackTrace.current;
      final exception1 = AdapterException(message: 'Adapter error', error: 'Some error', stackTrace: stackTrace);
      final exception2 = AdapterException(message: 'Adapter error', error: 'Some error', stackTrace: stackTrace);
      final exception3 = AdapterException(message: 'Adapter error', error: 'Different error', stackTrace: stackTrace);

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      final stackTrace = StackTrace.current;
      final exception = AdapterException(message: 'Adapter failed', error: 'Connection refused', stackTrace: stackTrace);
      expect(exception.toString(), 'AdapterException(error: Connection refused, stackTrace: $stackTrace)');
    });
  });

  group('UnknownException', () {
    test('should have correct equality', () {
      final exception1 = UnknownException(message: 'Unknown error', error: 'Details');
      final exception2 = UnknownException(message: 'Unknown error', error: 'Details');
      final exception3 = UnknownException(message: 'Unknown error', error: 'Other details');

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      final exception = UnknownException(message: 'An unknown error occurred', error: 'Some underlying error');
      expect(exception.toString(), 'DatumException(unknown): An unknown error occurred Details: {error: Some underlying error}');
    });
  });

  group('ConflictException', () {
    test('should have correct equality', () {
      const exception1 = ConflictException(message: 'Conflict detected', details: {'entityId': '123'});
      const exception2 = ConflictException(message: 'Conflict detected', details: {'entityId': '123'});
      const exception3 = ConflictException(message: 'Conflict detected', details: {'entityId': '456'});

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = ConflictException(message: 'Conflict detected', details: {'entityId': '123'});
      expect(exception.toString(), 'DatumException(conflictDetected): Conflict detected Details: {entityId: 123}');
    });
  });

  group('EntityNotFoundException', () {
    test('should have correct equality', () {
      const exception1 = EntityNotFoundException(message: 'Entity not found', details: {'id': 'abc'});
      const exception2 = EntityNotFoundException(message: 'Entity not found', details: {'id': 'abc'});
      const exception3 = EntityNotFoundException(message: 'Entity not found', details: {'id': 'def'});

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = EntityNotFoundException(message: 'Entity not found', details: {'id': 'abc'});
      expect(exception.toString(), 'DatumException(entityNotFound): Entity not found Details: {id: abc}');
    });
  });

  group('SerializationException', () {
    test('should have correct equality', () {
      const exception1 = SerializationException(message: 'Failed to serialize', details: {'data': 'invalid'});
      const exception2 = SerializationException(message: 'Failed to serialize', details: {'data': 'invalid'});
      const exception3 = SerializationException(message: 'Failed to serialize', details: {'data': 'valid'});

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = SerializationException(message: 'Failed to serialize', details: {'data': 'invalid'});
      expect(exception.toString(), 'DatumException(serializationError): Failed to serialize Details: {data: invalid}');
    });
  });

  group('AuthenticationException', () {
    test('should have correct equality', () {
      const exception1 = AuthenticationException(message: 'Auth failed', details: {'reason': 'invalid_token'});
      const exception2 = AuthenticationException(message: 'Auth failed', details: {'reason': 'invalid_token'});
      const exception3 = AuthenticationException(message: 'Auth failed', details: {'reason': 'expired_token'});

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = AuthenticationException(message: 'Auth failed', details: {'reason': 'invalid_token'});
      expect(exception.toString(), 'DatumException(authenticationError): Auth failed Details: {reason: invalid_token}');
    });
  });

  group('AuthorizationException', () {
    test('should have correct equality', () {
      const exception1 = AuthorizationException(message: 'Not authorized', details: {'permission': 'write'});
      const exception2 = AuthorizationException(message: 'Not authorized', details: {'permission': 'write'});
      const exception3 = AuthorizationException(message: 'Not authorized', details: {'permission': 'read'});

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = AuthorizationException(message: 'Not authorized', details: {'permission': 'write'});
      expect(exception.toString(), 'DatumException(authorizationError): Not authorized Details: {permission: write}');
    });
  });

  group('ValidationException', () {
    test('should have correct equality', () {
      const exception1 = ValidationException(message: 'Invalid input', details: {'field': 'email'});
      const exception2 = ValidationException(message: 'Invalid input', details: {'field': 'email'});
      const exception3 = ValidationException(message: 'Invalid input', details: {'field': 'password'});

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = ValidationException(message: 'Invalid input', details: {'field': 'email'});
      expect(exception.toString(), 'DatumException(validationError): Invalid input Details: {field: email}');
    });
  });

  group('DatumTimeoutException', () {
    test('should have correct equality', () {
      const exception1 = DatumTimeoutException(message: 'Operation timed out');
      const exception2 = DatumTimeoutException(message: 'Operation timed out');
      const exception3 = DatumTimeoutException(message: 'Connection timed out');

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = DatumTimeoutException(message: 'Operation timed out');
      expect(exception.toString(), 'DatumException(timeout): Operation timed out');
    });
  });

  group('CancellationException', () {
    test('should have correct equality', () {
      const exception1 = CancellationException(message: 'Operation cancelled');
      const exception2 = CancellationException(message: 'Operation cancelled');
      const exception3 = CancellationException(message: 'User cancelled');

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = CancellationException(message: 'Operation cancelled');
      expect(exception.toString(), 'DatumException(cancelled): Operation cancelled');
    });
  });

  group('PreconditionFailedException', () {
    test('should have correct equality', () {
      const exception1 = PreconditionFailedException(message: 'Precondition failed', details: {'condition': 'active_user'});
      const exception2 = PreconditionFailedException(message: 'Precondition failed', details: {'condition': 'active_user'});
      const exception3 = PreconditionFailedException(message: 'Precondition failed', details: {'condition': 'admin_role'});

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = PreconditionFailedException(message: 'Precondition failed', details: {'condition': 'active_user'});
      expect(exception.toString(), 'DatumException(preconditionFailed): Precondition failed Details: {condition: active_user}');
    });
  });

  group('ServerException', () {
    test('should have correct equality', () {
      const exception1 = ServerException(message: 'Server error', details: {'statusCode': 500});
      const exception2 = ServerException(message: 'Server error', details: {'statusCode': 500});
      const exception3 = ServerException(message: 'Server error', details: {'statusCode': 502});

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = ServerException(message: 'Server error', details: {'statusCode': 500});
      expect(exception.toString(), 'DatumException(serverError): Server error Details: {statusCode: 500}');
    });
  });

  group('BadRequestException', () {
    test('should have correct equality', () {
      const exception1 = BadRequestException(message: 'Bad request', details: {'param': 'invalid'});
      const exception2 = BadRequestException(message: 'Bad request', details: {'param': 'invalid'});
      const exception3 = BadRequestException(message: 'Bad request', details: {'param': 'missing'});

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = BadRequestException(message: 'Bad request', details: {'param': 'invalid'});
      expect(exception.toString(), 'DatumException(badRequest): Bad request Details: {param: invalid}');
    });
  });

  group('UnavailableException', () {
    test('should have correct equality', () {
      const exception1 = UnavailableException(message: 'Service unavailable');
      const exception2 = UnavailableException(message: 'Service unavailable');
      const exception3 = UnavailableException(message: 'Database unavailable');

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      const exception = UnavailableException(message: 'Service unavailable');
      expect(exception.toString(), 'DatumException(unavailable): Service unavailable');
    });
  });

  group('MigrationException', () {
    test('should have correct equality', () {
      final error = Exception('Migration failed');
      final stackTrace = StackTrace.current;
      final exception1 = MigrationException(message: 'Migration error', e: error, stackTrace: stackTrace);
      final exception2 = MigrationException(message: 'Migration error', e: error, stackTrace: stackTrace);
      final exception3 = MigrationException(message: 'Another migration error', e: error, stackTrace: stackTrace);

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('should have correct string representation', () {
      final error = Exception('Migration failed');
      final stackTrace = StackTrace.current;
      final exception = MigrationException(message: 'Migration error', e: error, stackTrace: stackTrace);
      expect(exception.toString(), 'DatumException(migrationError): Migration error Details: {e: Exception: Migration failed, stackTrace: $stackTrace}');
    });
  });
}
