import 'package:datum/datum.dart';
import 'package:test/test.dart';

void main() {
  group('DatumException subclasses', () {
    // A runtime-built map keeps these constructor invocations non-const so the
    // constructor bodies actually execute.
    late Map<String, dynamic> details;

    setUp(() {
      details = <String, dynamic>{'field': 'value'};
    });

    test('each specialized exception carries its dedicated code', () {
      final cases = <(DatumException, DatumExceptionCode)>[
        (
          AuthenticationException(message: 'auth failed', details: details),
          DatumExceptionCode.authenticationError,
        ),
        (
          AuthorizationException(message: 'not allowed', details: details),
          DatumExceptionCode.authorizationError,
        ),
        (
          ValidationException(message: 'invalid input', details: details),
          DatumExceptionCode.validationError,
        ),
        (
          TimeoutException(message: 'took too long', details: details),
          DatumExceptionCode.timeout,
        ),
        (
          CancellationException(message: 'cancelled', details: details),
          DatumExceptionCode.cancelled,
        ),
        (
          PreconditionFailedException(message: 'not ready', details: details),
          DatumExceptionCode.preconditionFailed,
        ),
        (
          ServerException(message: 'server blew up', details: details),
          DatumExceptionCode.serverError,
        ),
        (
          BadRequestException(message: 'bad request', details: details),
          DatumExceptionCode.badRequest,
        ),
        (
          UnavailableException(message: 'try later', details: details),
          DatumExceptionCode.unavailable,
        ),
      ];

      for (final (exception, expectedCode) in cases) {
        expect(exception.code, expectedCode);
        expect(exception.message, isNotEmpty);
        expect(exception.details, same(details));
        expect(
          exception.props,
          containsAll(<Object?>[expectedCode, exception.message, details]),
        );
        expect(
          exception.toString(),
          contains(expectedCode.name),
          reason: '$exception should mention its code',
        );
      }
    });

    test('exceptions with identical fields are equal', () {
      final a = ValidationException(message: 'invalid', details: details);
      final b = ValidationException(message: 'invalid', details: details);
      final c = ValidationException(message: 'different', details: details);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('DatumException.stringify is enabled', () {
      const exception = DatumException(
        code: DatumExceptionCode.unknown,
        message: 'anything',
      );
      expect(exception.stringify, isTrue);
    });
  });

  group('DatumError.from', () {
    test('maps userSwitchError code to UnknownError', () {
      const cause = UserSwitchException(
        message: 'switch failed',
        oldUserId: 'old-user',
        newUserId: 'new-user',
      );

      final error = DatumError.from(cause, StackTrace.current);

      expect(error, isA<UnknownError>());
      expect(error.message, 'switch failed');
      expect(error.cause, same(cause));
      expect(error.stackTrace, isNotNull);
    });

    test('maps unknown code to UnknownError', () {
      final cause = UnknownException(message: 'weird failure', error: 'boom');

      final error = DatumError.from(cause);

      expect(error, isA<UnknownError>());
      expect(error.message, 'weird failure');
      expect(error.cause, same(cause));
    });
  });

  group('DatumError equatable surface', () {
    test('stringify is enabled so toString includes the message', () {
      const error = ConflictError('unresolvable');
      expect(error.stringify, isTrue);
      expect(error.toString(), contains('unresolvable'));
    });

    test('NotFoundError includes id in props and equality', () {
      const withId = NotFoundError('gone', id: 'entity-1');
      const sameId = NotFoundError('gone', id: 'entity-1');
      const otherId = NotFoundError('gone', id: 'entity-2');

      expect(withId.props, contains('entity-1'));
      expect(withId, equals(sameId));
      expect(withId, isNot(equals(otherId)));
    });
  });
}
