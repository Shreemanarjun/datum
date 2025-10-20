// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:example/bootstrap.dart';

import 'package:datum/datum.dart';

class CustomDatumLogger implements DatumLogger {
  @override
  final bool enabled;
  @override
  final bool colors;

  CustomDatumLogger({this.enabled = true, this.colors = true});

  @override
  void debug(String message) {
    if (enabled) talker.debug(message);
  }

  @override
  void error(String message, [StackTrace? stackTrace]) {
    if (enabled) talker.error(message, stackTrace);
  }

  @override
  void info(String message) {
    if (enabled) talker.info(message);
  }

  @override
  void warn(String message) {
    if (enabled) talker.warning(message);
  }

  @override
  CustomDatumLogger copyWith({bool? enabled, bool? colors}) {
    return CustomDatumLogger(
      enabled: enabled ?? this.enabled,
      colors: colors ?? this.colors,
    );
  }
}
