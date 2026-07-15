import 'package:datum/datum.dart' hide IsolateStrategy;

import 'package:example/const/secrets.dart';
import 'package:example/custom_connectivity_checker.dart';
import 'package:example/persistence/hive_datum_persistence.dart';
import 'package:example/sync/isolate_stratergy.dart';
import 'package:example/features/tasks/data/adapters/hive_isolate_adapter.dart';
import 'package:example/bootstrap.dart' as bootstrap;
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/features/auth/data/adapters/supabase_adapter.dart';
import 'package:example/data/paint/entity/paint_stroke.dart';
import 'package:example/data/paint/entity/paint_canvas.dart';
import 'package:example/features/tasks/presentation/controllers/simple_datum_provider.dart';
import 'package:example/my_datum_observer.dart';
import 'package:example/shared/riverpod_ext/riverpod_observer/riverpod_obs.dart';
import 'package:example/shared/riverpod_ext/riverpod_observer/talker_riverpod_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:example/i18n/strings.g.dart';
import 'package:example/shared/pods/internet_checker_pod.dart';
import 'package:example/shared/pods/translation_pod.dart';
import 'package:platform_info/platform_info.dart';
import 'package:example/bootstrap.dart';
import 'package:example/core/local_storage/app_storage_pod.dart';
import 'package:example/features/splash/controller/box_encryption_key_pod.dart';
import 'package:example/init.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Top-level functions to avoid closure capture issues with Isolate
Future<String?> _initialUserId() async {
  try {
    final currentUser = Supabase.instance.client.auth.currentUser;
    return currentUser?.id;
  } catch (e) {
    talker.warning('Could not get current user for initialUserId: $e');
    return null;
  }
}

Future<void> _onMigrationError(Object error, StackTrace stackTrace) async {
  talker.error(error, stackTrace);
}

final futureInitializerPod = FutureProvider<ProviderContainer>((
  ref,
) async {
  ///Additional intial delay duration for app
  // await Future.delayed(const Duration(seconds: 1));
  await (init());
  await IsolatedHive.initFlutter();
  await Hive.initFlutter();

  await Supabase.initialize(
    url: Secrets.SUPABASE_URL,
    publishableKey: Secrets.SUPABASE_ANON_KEY,
  );
  final encryptionCipher = await Platform.I.when(
    mobile: () async {
      final encryptionKey = await ref.watch(boxEncryptionKeyPod.future);
      return HiveAesCipher(encryptionKey);
    },
  );

  ///Load device translations
  ///
  AppLocale deviceLocale = AppLocaleUtils.findDeviceLocale();
  final translations = await deviceLocale.build();

  final appBox = await Hive.openBox(
    'DatumAppBox',
    encryptionCipher: encryptionCipher,
  );
  final config = DatumConfig(
    enableLogging: true,
    autoStartSync: true, // Enable auto-start sync with reactive user ID
    initialUserId: _initialUserId, // Use top-level function
    changeCacheDuration: Duration(seconds: 1),
    remoteEventDebounceTime: Duration(milliseconds: 100),
    autoSyncInterval: Duration(
      minutes: 10,
    ),
    syncRequestStrategy: SequentialRequestStrategy(),
    syncExecutionStrategy:
        const IsolateStrategy(DatumSyncExecutionStrategy.sequential()),
    schemaVersion: 0,
    migrations: [],
    enablePerformanceLogging: false,
    logLevel: LogLevel.trace,
    onMigrationError: _onMigrationError, // Use top-level function
    // Cold start sync now runs in background - won't block app initialization
    coldStartConfig: const ColdStartConfig(
      strategy: ColdStartStrategy.adaptive, // Runs in background
      syncThreshold: Duration(hours: 2), // Sync if > 2 hours since last sync
      maxDuration: Duration(seconds: 10), // 10 second background sync
      initialDelay: Duration(milliseconds: 500), // Small delay after app start
    ),
  );
  final datum = await Datum.initialize(
    config: config,
    persistence: HiveDatumPersistence(),
    connectivityChecker: CustomConnectivityChecker(),
    logger: bootstrap.isolateLogger,
    observers: [
      MyDatumObserver(),
    ],
    registrations: [
      DatumRegistration<Task>(
        localAdapter: IsolatedHiveLocalAdapter<Task>(
          entityBoxName: "Task",
          fromMap: Task.fromMap, // Use tear-off
          schemaVersion: 0,
        ),
        remoteAdapter: SupabaseRemoteAdapter<Task>(
          fromMap: Task.fromMap,
          tableName: "tasks",
        ),
      ),
      DatumRegistration<PaintStroke>(
        localAdapter: IsolatedHiveLocalAdapter<PaintStroke>(
          entityBoxName: "PaintStroke",
          fromMap: PaintStrokeFactory.fromMap, // Use generated factory
          schemaVersion: 0,
        ),
        remoteAdapter: SupabaseRemoteAdapter<PaintStroke>(
          fromMap: PaintStrokeFactory.fromMap,
          tableName: "paint_strokes",
        ),
      ),
      DatumRegistration<PaintCanvas>(
        localAdapter: IsolatedHiveLocalAdapter<PaintCanvas>(
          entityBoxName: "PaintCanvas",
          fromMap: PaintCanvasFactory.fromMap, // Use generated factory
          schemaVersion: 0,
        ),
        remoteAdapter: SupabaseRemoteAdapter<PaintCanvas>(
          fromMap: PaintCanvasFactory.fromMap,
          tableName: "paint_canvases",
        ),
      ),
    ],
  );

  return ProviderContainer(
    overrides: [
      appBoxProvider.overrideWithValue(appBox),
      translationsPod.overrideWith((ref) => translations),
      enableInternetCheckerPod.overrideWithValue(false),
      simpleDatumProvider.overrideWith(
        (ref) => datum.fold(
          (l, s) => throw l,
          (r) => r,
        ),
      ),
    ],
    observers: [
      ///Added new talker riverpod observer
      ///
      /// If you want old behaviour
      /// Replace with
      ///
      ///  MyObserverLogger( talker: talker,)
      ///
      ///
      ///
      ///
      TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(
          printProviderDisposed: true,
          providerFilter: (provider) {
            if (provider.name == "countdownProvider") {
              return false;
            }
            return true;
          },
        ),
      ),
    ],
  );
});
