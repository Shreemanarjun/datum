import 'dart:async';

/// An abstract interface for checking network connectivity.
///
/// This allows the `datum` library to remain platform-agnostic. The user of
/// the library is responsible for providing a concrete implementation.
///
/// ### Example Implementation for Flutter:
/// ```dart
/// import 'package:connectivity_plus/connectivity_plus.dart';
///
/// class MyConnectivityChecker implements ConnectivityChecker {
///   final _connectivity = Connectivity();
///
///   @override
///   Future<bool> get isConnected async =>
///       !(await _connectivity.checkConnectivity()).contains(ConnectivityResult.none);
///
///   @override
///   Stream<bool> get onStatusChange => _connectivity.onConnectivityChanged
///       .map((results) => !results.contains(ConnectivityResult.none));
/// }
/// ```
abstract class DatumConnectivityChecker {
  /// Checks if the device is connected to a network.
  Future<bool> get isConnected;

  /// A stream that emits the connectivity status whenever it changes.
  Stream<bool> get onStatusChange;
}
