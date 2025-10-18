import 'package:datum/datum.dart';
import 'package:example/custom_connectivity_checker.dart';
import 'package:example/custom_datum_logger.dart';
import 'package:example/data/user/adapters/local.dart';
import 'package:example/data/user/adapters/user_remote_adapter.dart';
import 'package:example/data/user/entity/user.dart';
import 'package:example/my_datum_observer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final simpleDatumProvider = FutureProvider.autoDispose<Datum>(
  (ref) async {
    const config = DatumConfig(enableLogging: true, autoStartSync: true);
    final datum = await Datum.initialize(
      config: config,
      connectivityChecker: CustomConnectivityChecker(),
      logger: CustomDatumLogger(enabled: config.enableLogging),
      observers: [MyDatumObserver()],
      registrations: [
        DatumRegistration<User>(
          localAdapter: UserLocalAdapter(),
          remoteAdapter: UserRemoteAdapter(),
        ),
      ],
    );
    ref.onDispose(
      () async => await datum.dispose(),
    );
    return datum;
  },
);
