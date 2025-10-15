import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:datum/source/utils/connectivity_checker.dart';

// Mock the Connectivity class from connectivity_plus
class MockConnectivity extends Mock implements Connectivity {}

void main() {
  group('ConnectivityChecker', () {
    late MockConnectivity mockConnectivity;
    late ConnectivityChecker connectivityChecker;
    late StreamController<List<ConnectivityResult>>
    connectivityStreamController;

    setUpAll(() {
      // Register fallback for ConnectivityResult list if any() is used
      registerFallbackValue([ConnectivityResult.none]);
    });

    setUp(() {
      mockConnectivity = MockConnectivity();
      connectivityStreamController =
          StreamController<List<ConnectivityResult>>();

      // Stub the onConnectivityChanged stream to use our controller
      when(
        () => mockConnectivity.onConnectivityChanged,
      ).thenAnswer((_) => connectivityStreamController.stream);

      connectivityChecker = ConnectivityChecker(connectivity: mockConnectivity);
    });

    tearDown(() {
      connectivityStreamController.close();
    });

    group('isConnected', () {
      test('returns true when connected to Wi-Fi', () async {
        when(
          () => mockConnectivity.checkConnectivity(),
        ).thenAnswer((_) async => [ConnectivityResult.wifi]);

        expect(await connectivityChecker.isConnected, isTrue);
      });

      test('returns true when connected to mobile data', () async {
        when(
          () => mockConnectivity.checkConnectivity(),
        ).thenAnswer((_) async => [ConnectivityResult.mobile]);

        expect(await connectivityChecker.isConnected, isTrue);
      });

      test('returns false when not connected', () async {
        when(
          () => mockConnectivity.checkConnectivity(),
        ).thenAnswer((_) async => [ConnectivityResult.none]);

        expect(await connectivityChecker.isConnected, isFalse);
      });

      test(
        'returns true when connected to multiple networks (e.g., Wi-Fi and Ethernet)',
        () async {
          when(() => mockConnectivity.checkConnectivity()).thenAnswer(
            (_) async => [ConnectivityResult.wifi, ConnectivityResult.ethernet],
          );

          expect(await connectivityChecker.isConnected, isTrue);
        },
      );
    });

    group('onStatusChange', () {
      test(
        'emits true when connectivity changes from none to connected',
        () async {
          final expectedEvents = <bool>[];
          final subscription = connectivityChecker.onStatusChange.listen(
            expectedEvents.add,
          );

          connectivityStreamController.add([ConnectivityResult.none]);
          await Future<void>.delayed(Duration.zero); // Allow stream to process
          connectivityStreamController.add([ConnectivityResult.wifi]);
          await Future<void>.delayed(Duration.zero); // Allow stream to process

          expect(expectedEvents, [false, true]);
          await subscription.cancel();
        },
      );

      test(
        'emits false when connectivity changes from connected to none',
        () async {
          final expectedEvents = <bool>[];
          final subscription = connectivityChecker.onStatusChange.listen(
            expectedEvents.add,
          );

          connectivityStreamController.add([ConnectivityResult.wifi]);
          await Future<void>.delayed(Duration.zero); // Allow stream to process
          connectivityStreamController.add([ConnectivityResult.none]);
          await Future<void>.delayed(Duration.zero); // Allow stream to process

          expect(expectedEvents, [true, false]);
          await subscription.cancel();
        },
      );

      test(
        'emits true multiple times if underlying connectivity results change but boolean status remains true',
        () async {
          final expectedEvents = <bool>[];
          final subscription = connectivityChecker.onStatusChange.listen(
            expectedEvents.add,
          );

          connectivityStreamController.add([ConnectivityResult.wifi]);
          await Future<void>.delayed(Duration.zero);
          connectivityStreamController.add([ConnectivityResult.mobile]);
          await Future<void>.delayed(Duration.zero);

          expect(expectedEvents, [true, true]);
          await subscription.cancel();
        },
      );
    });
  });
}
