import 'package:datum/datum.dart';
import 'package:example/custom_connectivity_checker.dart';
import 'package:example/custom_datum_logger.dart';
import 'package:example/data/task/entity/task.dart';
import 'package:example/data/user/adapters/supabase_adapter.dart';
import 'package:example/features/simple_datum/controller/local.dart';
import 'package:example/my_datum_observer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final simpleDatumProvider = FutureProvider.autoDispose<Datum>(
  (ref) async {
    final config = DatumConfig(
      enableLogging: true,
      autoStartSync: true,
      initialUserId: Supabase.instance.client.auth.currentUser?.id,
      changeCacheDuration: Duration(seconds: 1),
      autoSyncInterval: Duration(
        minutes: 1,
      ),
      syncExecutionStrategy: DatumSyncExecutionStrategy.parallel(),
    );
    final datum = await Datum.initialize(
      config: config,
      connectivityChecker: CustomConnectivityChecker(),
      logger: CustomDatumLogger(enabled: config.enableLogging),
      observers: [
        MyDatumObserver(),
      ],
      registrations: [
        DatumRegistration<Task>(
          localAdapter: TaskLocalAdapter(),
          remoteAdapter: SupabaseRemoteAdapter<Task>(
            tableName: 'tasks',
            fromMap: Task.fromMap,
          ),
        ),
      ],
    );
    Datum.manager<Task>().startAutoSync(
      Supabase.instance.client.auth.currentUser!.id,
    );
    ref.onDispose(
      () async => await datum.dispose(),
    );
    return datum;
  },
  name: "simpleDatumProvider",
);
