// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:datum/datum.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class CustomConnectivityChecker extends DatumConnectivityChecker {
  @override
  Future<bool> get isConnected => InternetConnection().hasInternetAccess;

  @override
  Stream<bool> get onStatusChange => InternetConnection().onStatusChange.map(
        (status) => status == InternetStatus.connected,
      );
}
