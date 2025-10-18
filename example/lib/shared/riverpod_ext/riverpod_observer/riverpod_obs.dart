import 'package:example/shared/riverpod_ext/riverpod_observer/riverpod_log.dart';
import 'package:example/shared/riverpod_ext/riverpod_observer/talker_riverpod_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// [Riverpod] logger on [Talker] base
///
/// [talker] field is the current [Talker] instance.
/// Provide your instance if your application uses [Talker] as the default logger
/// Common Talker instance will be used by default
class TalkerRiverpodObserver extends ProviderObserver {
  TalkerRiverpodObserver({
    Talker? talker,
    this.settings = const TalkerRiverpodLoggerSettings(),
  }) {
    _talker = talker ?? Talker();
    _talker.settings.registerKeys([
      TalkerKey.riverpodAdd,
      TalkerKey.riverpodUpdate,
      TalkerKey.riverpodDispose,
      TalkerKey.riverpodFail,
    ]);
  }

  late Talker _talker;
  final TalkerRiverpodLoggerSettings settings;

  @override
  @mustCallSuper
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    super.didAddProvider(provider, value, container);
    if (!settings.enabled || !settings.printProviderAdded) {
      return;
    }
    final accepted = settings.providerFilter?.call(provider) ?? true;
    if (!accepted) {
      return;
    }
    _talker.logCustom(
      RiverpodAddLog(provider: provider, value: value, settings: settings),
    );
  }

  @override
  @mustCallSuper
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    super.didUpdateProvider(provider, previousValue, newValue, container);
    if (!settings.enabled || !settings.printProviderUpdated) {
      return;
    }
    final accepted = settings.providerFilter?.call(provider) ?? true;
    if (!accepted) {
      return;
    }
    _talker.logCustom(
      RiverpodUpdateLog(
        provider: provider,
        previousValue: previousValue,
        newValue: newValue,
        settings: settings,
      ),
    );
  }

  @override
  @mustCallSuper
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    super.didDisposeProvider(provider, container);
    if (!settings.enabled || !settings.printProviderDisposed) {
      return;
    }
    final accepted = settings.providerFilter?.call(provider) ?? true;
    if (!accepted) {
      return;
    }
    _talker.logCustom(
      RiverpodDisposeLog(provider: provider, settings: settings),
    );
  }

  @override
  @mustCallSuper
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    super.providerDidFail(provider, error, stackTrace, container);
    if (!settings.enabled || !settings.printProviderFailed) {
      return;
    }
    final accepted = settings.providerFilter?.call(provider) ?? true;
    if (!accepted) {
      return;
    }

    try {
      final errorFiltered = settings.didFailFilter?.call(error) ?? true;
      if (!errorFiltered) {
        return;
      }
    } catch (_) {
      return;
    }

    _talker.logCustom(
      RiverpodFailLog(
        provider: provider,
        providerError: error,
        providerStackTrace: stackTrace,
        settings: settings,
      ),
    );
  }
}
