import 'package:example/const/secrets.dart';
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

final futureInitializerPod = FutureProvider.autoDispose<ProviderContainer>((
  ref,
) async {
  ///Additional intial delay duration for app
  // await Future.delayed(const Duration(seconds: 1));
  await (init());
  await IsolatedHive.initFlutter();
  await Hive.initFlutter();
  try {
    await Supabase.instance.dispose();
  } catch (e) {
    talker.error(e);
  }
  await Supabase.initialize(
    url: Secrets.SUPABASE_URL,
    anonKey: Secrets.SUPABASE_ANON_KEY,
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
  return ProviderContainer(
    overrides: [
      appBoxProvider.overrideWithValue(appBox),
      translationsPod.overrideWith((ref) => translations),
      enableInternetCheckerPod.overrideWithValue(false),
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
        settings: const TalkerRiverpodLoggerSettings(
          printProviderDisposed: true,
        ),
      ),
    ],
  );
});
