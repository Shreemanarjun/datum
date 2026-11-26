import 'dart:async';
import 'package:datum/datum.dart' hide IsolateStrategy;

import 'package:example/const/secrets.dart';
import 'package:example/custom_connectivity_checker.dart';
import 'package:example/persistence/hive_datum_persistence.dart';
import 'package:example/sync/isolate_stratergy.dart';
import 'package:datum_hive/datum_hive.dart';
import 'package:example/bootstrap.dart' as bootstrap;
import 'package:example/features/tasks/data/entities/task.dart';
import 'package:example/features/auth/data/adapters/supabase_adapter.dart';
import 'package:example/data/paint/entity/paint_stroke.dart';
import 'package:example/data/paint/entity/paint_canvas.dart';
import 'package:example/my_datum_observer.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:example/i18n/strings.g.dart';
import 'package:platform_info/platform_info.dart';
import 'package:example/bootstrap.dart';
import 'package:example/init.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:example/features/settings/user_settings.dart';
import 'package:example/core/theme/theme_controller.dart';
import 'package:example/shared/translations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'dart:convert';
import 'dart:typed_data';

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

/// Reads (or creates on first launch) the AES key for the app's Hive box.
Future<Uint8List> _boxEncryptionKey() async {
  const storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  const storageKey = 'DatumStorage';
  var key = await storage.read(key: storageKey);
  if (key == null) {
    key = base64UrlEncode(Hive.generateSecureKey());
    await storage.write(key: storageKey, value: key);
  }
  return base64Url.decode(key);
}

Future<void> initializeApp() async {
  await (init());
  await IsolatedHive.initFlutter();
  await Hive.initFlutter();

  await Supabase.initialize(
    url: Secrets.SUPABASE_URL,
    publishableKey: Secrets.SUPABASE_ANON_KEY,
  );
  final encryptionCipher = await Platform.I.when(
    mobile: () async => HiveAesCipher(await _boxEncryptionKey()),
  );

  ///Load device translations
  ///
  translations.value = await AppLocaleUtils.findDeviceLocale().build();

  bindThemeStorage(await Hive.openBox(
    'DatumAppBox',
    encryptionCipher: encryptionCipher,
  ));
  final config = DatumConfig(
    enableLogging: true,
    autoStartSync: true, // Enable auto-start sync with reactive user ID
    initialUserId: _initialUserId, // Use top-level function
    changeCacheDuration: Duration(seconds: 1),
    remoteEventDebounceTime: Duration(milliseconds: 100),
    // Upload shortly after local writes (e.g. a burst of paint strokes) so
    // other devices see them by realtime without waiting for auto-sync.
    syncAfterWriteDelay: Duration(milliseconds: 300),
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
    // An expired session pauses sync (writes stay queued); signing back in
    // resumes it.
    authState: Supabase.instance.client.auth.onAuthStateChange
        .map((s) => s.session != null),
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
      DatumRegistration<UserSettings>(
        localAdapter: IsolatedHiveLocalAdapter<UserSettings>(
          entityBoxName: "UserSettings",
          fromMap: UserSettings.fromMap,
          schemaVersion: 0,
        ),
        remoteAdapter: SupabaseRemoteAdapter<UserSettings>(
          fromMap: UserSettings.fromMap,
          tableName: "user_settings",
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

  datum.fold(
      (error, stackTrace) =>
          Error.throwWithStackTrace(error, stackTrace ?? StackTrace.current),
      (_) {});
  syncThemeWithAccount();
  _syncWithSession();
}

/// Ties sync to the Supabase session: signing in resumes sync, starts
/// auto-sync and syncs once; signing out pauses it. (At app start the
/// persisted session is covered by `autoStartSync` and the cold-start sync.)
void _syncWithSession() {
  Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    final userId = state.session?.user.id;
    if (state.event == AuthChangeEvent.signedOut) {
      Datum.instance.pauseSync();
    } else if (state.event == AuthChangeEvent.signedIn && userId != null) {
      Datum.instance.resumeSync();
      Datum.instance.startAutoSync(userId);
      unawaited(Datum.instance.synchronize(userId).then<void>((_) {},
          onError: (Object e) => talker.warning('Sign-in sync failed: $e')));
    }
  });
}

/// App startup. Read by the splash screen; errors surface there.
final appInitialization = futureSignal(initializeApp);
