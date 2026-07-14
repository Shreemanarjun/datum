import 'package:datum/datum.dart';
import 'package:test/test.dart';

void main() {
  group('DatumEither', () {
    group('Success', () {
      const success = Success<String, int>(42);

      test('isSuccess returns true', () {
        expect(success.isSuccess(), isTrue);
      });

      test('isFailure returns false', () {
        expect(success.isFailure(), isFalse);
      });

      test('fold calls onSuccess', () {
        final result = success.fold(
          (l, s) => 'failure',
          (r) => 'success',
        );
        expect(result, 'success');
      });

      test('onSuccess calls the callback', () {
        int? value;
        success.onSuccess((r) => value = r);
        expect(value, 42);
      });

      test('onFailure does not call the callback', () {
        String? value;
        success.onFailure((l, s) => value = l);
        expect(value, isNull);
      });

      test('getSuccess returns the value', () {
        expect(success.getSuccess(), 42);
      });

      test('getError throws a StateError', () {
        expect(() => success.getError(), throwsStateError);
      });

      test('successOrNull returns the value', () {
        expect(success.successOrNull, 42);
      });

      test('errorOrNull returns null', () {
        expect(success.errorOrNull, isNull);
      });
    });

    group('Failure', () {
      final failure = Failure<String, int>('error', StackTrace.current);

      test('isSuccess returns false', () {
        expect(failure.isSuccess(), isFalse);
      });

      test('isFailure returns true', () {
        expect(failure.isFailure(), isTrue);
      });

      test('fold calls onFailure', () {
        final result = failure.fold(
          (l, s) => 'failure',
          (r) => 'success',
        );
        expect(result, 'failure');
      });

      test('onSuccess does not call the callback', () {
        int? value;
        failure.onSuccess((r) => value = r);
        expect(value, isNull);
      });

      test('onFailure calls the callback', () {
        String? value;
        failure.onFailure((l, s) => value = l);
        expect(value, 'error');
      });

      test('getSuccess throws a StateError', () {
        expect(() => failure.getSuccess(), throwsStateError);
      });

      test('getError returns the value', () {
        final (error, stackTrace) = failure.getError();
        expect(error, 'error');
        expect(stackTrace, isA<StackTrace>());
      });

      test('successOrNull returns null', () {
        expect(failure.successOrNull, isNull);
      });

      test('errorOrNull returns the value', () {
        expect(failure.errorOrNull, 'error');
      });
    });
  });
}
