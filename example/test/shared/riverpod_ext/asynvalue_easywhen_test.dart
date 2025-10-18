import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:example/shared/riverpod_ext/riverpod_observer/riverpod_obs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:example/core/local_storage/app_storage_pod.dart';
import 'package:example/i18n/strings.g.dart';
import 'package:example/shared/riverpod_ext/asynvalue_easy_when.dart';
import 'package:example/shared/pods/translation_pod.dart';
import 'package:spot/spot.dart';

import '../../helpers/pump_app.dart';

final testAsyncValuePod = FutureProvider.autoDispose<String>((ref) async {
  return "Hi";
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Check AsyncValue Easy when', () {
    late Box appBox;
    setUp(() async {
      appBox = await Hive.openBox('appBox', bytes: Uint8List(0));
    });
    tearDown(() {
      appBox.clear();
    });
    testWidgets('check on data Placeholder should be rendered', (tester) async {
      await tester.pumpApp(
        child: Scaffold(
          body: Consumer(
            builder: (context, ref, child) {
              final valueAsync = ref.watch(testAsyncValuePod);
              return valueAsync.easyWhen(data: (data) => const Placeholder());
            },
          ),
        ),
        container: ProviderContainer(
          overrides: [
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Placeholder), findsOneWidget);
    });
    testWidgets('check on error Default error should be rendered', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          testAsyncValuePod.overrideWith((ref) => throw "Error"),
        ],
        observers: [TalkerRiverpodObserver()],
      );
      await tester.pumpApp(
        child: Scaffold(
          body: Consumer(
            builder: (context, ref, child) {
              final valueAsync = ref.watch(testAsyncValuePod);
              return valueAsync.easyWhen(data: (data) => const Placeholder());
            },
          ),
        ),
        container: container,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DefaultErrorWidget), findsOneWidget);
    });
    testWidgets('check on error custom error should be rendered', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          testAsyncValuePod.overrideWith((ref) {
            throw "custom error";
          }),
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
        ],
      );
      await tester.pumpApp(
        child: Scaffold(
          body: Consumer(
            builder: (context, ref, child) {
              final valueAsync = ref.watch(testAsyncValuePod);
              return valueAsync.easyWhen(
                data: (data) => const Placeholder(),
                errorWidget: (error, stackTrace) {
                  return Text(error.toString());
                },
              );
            },
          ),
        ),
        container: container,
      );
      await tester.pumpAndSettle();
      expect(find.text("custom error"), findsOneWidget);
    });

    testWidgets('check custom loading widget should be rendered', (
      tester,
    ) async {
      await tester.pumpApp(
        child: Scaffold(
          body: Consumer(
            builder: (context, ref, child) {
              final valueAsync = ref.watch(testAsyncValuePod);
              return valueAsync.easyWhen(
                data: (data) => const Placeholder(),
                loadingWidget: () {
                  return const Text('Loading');
                },
              );
            },
          ),
        ),
        container: ProviderContainer(
          overrides: [
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        ),
      );

      expect(find.text('Loading'), findsOneWidget);
    });
    testWidgets(
      'check isLinear  should render error in row and text should be Try again letter when onRetry is not passed ',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            testAsyncValuePod.overrideWith((ref) {
              throw "Error";
            }),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final valueAsync = ref.watch(testAsyncValuePod);
                return valueAsync.easyWhen(
                  data: (data) => const Placeholder(),
                  isLinear: true,
                );
              },
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.byType(Row), findsOneWidget);
        await takeScreenshot();
        expect(find.text('Try Again later.'), findsOneWidget);
      },
    );
    testWidgets('check isLinear should render error in row ', (tester) async {
      final container = ProviderContainer(
        overrides: [
          testAsyncValuePod.overrideWith((ref) {
            throw "Error";
          }),
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
        ],
      );
      await tester.pumpApp(
        child: Scaffold(
          body: Consumer(
            builder: (context, ref, child) {
              final valueAsync = ref.watch(testAsyncValuePod);
              return valueAsync.easyWhen(
                data: (data) => const Placeholder(),
                isLinear: true,
                onRetry: () => ref.invalidate(testAsyncValuePod),
              );
            },
          ),
        ),
        container: container,
      );
      await tester.pumpAndSettle();
      expect(find.byType(Row), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Try again '), findsOneWidget);
    });
    testWidgets('check isLinear should render error in column ', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          testAsyncValuePod.overrideWith((ref) {
            throw "Error";
          }),
          appBoxProvider.overrideWithValue(appBox),
          translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
        ],
      );
      await tester.pumpApp(
        child: Scaffold(
          body: Consumer(
            builder: (context, ref, child) {
              final valueAsync = ref.watch(testAsyncValuePod);
              return valueAsync.easyWhen(
                data: (data) => const Placeholder(),
                onRetry: () => ref.invalidate(testAsyncValuePod),
              );
            },
          ),
        ),
        container: container,
      );
      await tester.pumpAndSettle();
      expect(find.byType(Column), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Try again '), findsOneWidget);
    });
    testWidgets(
      'check on error Default Dio Error connection timeout should be rendered and with connection time out text',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            testAsyncValuePod.overrideWith(
              (ref) => throw DioException(
                type: DioExceptionType.connectionTimeout,
                requestOptions: RequestOptions(path: "/"),
              ),
            ),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final valueAsync = ref.watch(testAsyncValuePod);
                return valueAsync.easyWhen(
                  data: (data) => const Placeholder(),
                  includedefaultDioErrorMessage: true,
                );
              },
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.byType(DefaultDioErrorWidget), findsOneWidget);
        expect(find.text('Connection Timeout Error'), findsOneWidget);
      },
    );
    testWidgets(
      'check on error Default Dio Error sendTimeout should be rendered and with connection sendTimeout text',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            testAsyncValuePod.overrideWith(
              (ref) => throw DioException(
                type: DioExceptionType.sendTimeout,
                requestOptions: RequestOptions(path: "/"),
              ),
            ),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final valueAsync = ref.watch(testAsyncValuePod);
                return valueAsync.easyWhen(
                  data: (data) => const Placeholder(),
                  includedefaultDioErrorMessage: true,
                );
              },
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.byType(DefaultDioErrorWidget), findsOneWidget);
        expect(
          find.text('Unable to connect to the server.Please try again later.'),
          findsOneWidget,
        );
      },
    );
    testWidgets(
      'check on error Default Dio Error receiveTimeout should be rendered and with connection receiveTimeout text',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            testAsyncValuePod.overrideWith(
              (ref) => throw DioException(
                type: DioExceptionType.receiveTimeout,
                requestOptions: RequestOptions(path: "/"),
              ),
            ),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final valueAsync = ref.watch(testAsyncValuePod);
                return valueAsync.easyWhen(
                  data: (data) => const Placeholder(),
                  includedefaultDioErrorMessage: true,
                );
              },
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.byType(DefaultDioErrorWidget), findsOneWidget);
        expect(
          find.text('Check you internet connection reliability.'),
          findsOneWidget,
        );
      },
    );
    testWidgets(
      'check on error Default Dio Error badCertificate should be rendered and with connection badCertificate text',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            testAsyncValuePod.overrideWith(
              (ref) => throw DioException(
                type: DioExceptionType.badCertificate,
                requestOptions: RequestOptions(path: "/"),
              ),
            ),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final valueAsync = ref.watch(testAsyncValuePod);
                return valueAsync.easyWhen(
                  data: (data) => const Placeholder(),
                  includedefaultDioErrorMessage: true,
                );
              },
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.byType(DefaultDioErrorWidget), findsOneWidget);
        expect(
          find.text('Please update your OS or add certificate.'),
          findsOneWidget,
        );
      },
    );
    testWidgets(
      'check on error Default Dio Error badResponse should be rendered and with connection badResponse text',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            testAsyncValuePod.overrideWith(
              (ref) => throw DioException(
                type: DioExceptionType.badResponse,
                requestOptions: RequestOptions(path: "/"),
              ),
            ),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final valueAsync = ref.watch(testAsyncValuePod);
                return valueAsync.easyWhen(
                  data: (data) => const Placeholder(),
                  includedefaultDioErrorMessage: true,
                );
              },
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.byType(DefaultDioErrorWidget), findsOneWidget);
        expect(
          find.text('Something went wrong.Please try again later.'),
          findsOneWidget,
        );
      },
    );
    testWidgets(
      'check on error Default Dio Error cancel should be rendered and with connection cancel text',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            testAsyncValuePod.overrideWith((ref) {
              throw DioException(
                type: DioExceptionType.cancel,
                requestOptions: RequestOptions(path: "/"),
              );
            }),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final valueAsync = ref.watch(testAsyncValuePod);
                return valueAsync.easyWhen(
                  data: (data) => const Placeholder(),
                  includedefaultDioErrorMessage: true,
                );
              },
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.byType(DefaultDioErrorWidget), findsOneWidget);
        expect(find.text('Request Cancelled'), findsOneWidget);
      },
    );
    testWidgets(
      'check on error Default Dio Error connectionError should be rendered and with connectionError text',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            testAsyncValuePod.overrideWith(
              (ref) => throw DioException(
                type: DioExceptionType.connectionError,
                requestOptions: RequestOptions(path: "/"),
              ),
            ),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final valueAsync = ref.watch(testAsyncValuePod);
                return valueAsync.easyWhen(
                  data: (data) => const Placeholder(),
                  includedefaultDioErrorMessage: true,
                );
              },
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.byType(DefaultDioErrorWidget), findsOneWidget);
        expect(
          find.text('Unable to connect to server.Please try again later.'),
          findsOneWidget,
        );
      },
    );
    testWidgets(
      'check on error Default Dio Error unknown should be rendered and with unknown text',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            testAsyncValuePod.overrideWith((ref) async {
              throw DioException(
                type: DioExceptionType.unknown,
                requestOptions: RequestOptions(path: "/"),
              );
            }),
            appBoxProvider.overrideWithValue(appBox),
            translationsPod.overrideWith((ref) => AppLocale.en.buildSync()),
          ],
        );
        await tester.pumpApp(
          child: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final valueAsync = ref.watch(testAsyncValuePod);
                return valueAsync.easyWhen(
                  data: (data) => const Placeholder(),
                  includedefaultDioErrorMessage: true,
                );
              },
            ),
          ),
          container: container,
        );
        await tester.pumpAndSettle();
        expect(find.byType(DefaultDioErrorWidget), findsOneWidget);
        expect(
          find.text('Please check your internet connection.'),
          findsOneWidget,
        );
      },
    );
  });
}
