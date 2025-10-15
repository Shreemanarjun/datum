import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// A mockable wrapper around the `connectivity_plus` package.
class ConnectivityChecker {
  final Connectivity _connectivity;

  /// Creates a connectivity checker.
  ConnectivityChecker({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  /// Checks if the device is connected to a network.
  Future<bool> get isConnected async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// A stream that emits the connectivity status whenever it changes.
  Stream<bool> get onStatusChange {
    return _connectivity.onConnectivityChanged.map(
      (results) => !results.contains(ConnectivityResult.none),
    );
  }
}
