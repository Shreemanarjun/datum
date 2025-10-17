import 'package:datum/source/utils/connectivity_checker.dart';
import 'package:mocktail/mocktail.dart';

/// A mock implementation of [DatumConnectivityChecker] using `mocktail`.
///
/// This allows for stubbing methods like `isConnected` and `onStatusChange`
/// in tests.
class MockConnectivityChecker extends Mock
    implements DatumConnectivityChecker {}
