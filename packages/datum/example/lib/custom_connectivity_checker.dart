// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:datum/datum.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class CustomConnectivityChecker extends DatumConnectivityChecker {
  /// While Datum listens to [onStatusChange], the library checks in the
  /// background (every 10 s and on each network change). Its last answer is
  /// used when there is one: probing the internet before every sync added
  /// 200 to 400 ms to each.
  @override
  Future<bool> get isConnected async {
    final known = InternetConnection().lastTryResults;
    return known == null ? await InternetConnection().hasInternetAccess : known == InternetStatus.connected;
  }

  @override
  Stream<bool> get onStatusChange => InternetConnection().onStatusChange.map(
        (status) => status == InternetStatus.connected,
      );
}
