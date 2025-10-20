import 'package:example/shared/riverpod_ext/riverpod_observer/riverpod_log.dart';
import 'package:example/shared/riverpod_ext/riverpod_observer/riverpod_obs.dart';
import 'package:example/shared/riverpod_ext/riverpod_observer/talker_riverpod_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';

void main() {
  group('TalkerRiverpodObserver', () {
    late Talker talker;
    late TalkerRiverpodObserver observer;

    setUp(() {
      talker = Talker();
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(printProviderDisposed: true),
      );
      talker.history.clear();
    });

    test('didAddProvider logs when enabled and accepted', () {
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      observer.didAddProvider(provider, 'test', container);
      expect(talker.history.whereType<RiverpodAddLog>().length, 1);
    });

    test('didAddProvider does not log when disabled', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: const TalkerRiverpodLoggerSettings(enabled: false),
      );
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      observer.didAddProvider(provider, 'test', container);
      expect(talker.history.whereType<RiverpodAddLog>().length, 0);
    });

    test('didAddProvider does not log when printProviderAdded is false', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: const TalkerRiverpodLoggerSettings(printProviderAdded: false),
      );
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      observer.didAddProvider(provider, 'test', container);
      expect(talker.history.whereType<RiverpodAddLog>().length, 0);
    });

    test('didAddProvider does not log when providerFilter rejects', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(
          providerFilter: (provider) => provider.name != 'testProvider',
        ),
      );
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      observer.didAddProvider(provider, 'test', container);
      expect(talker.history.whereType<RiverpodAddLog>().length, 0);
    });

    test('didUpdateProvider logs when enabled and accepted', () {
      final provider = StateProvider((ref) => 'initial', name: 'testProvider');
      final container = ProviderContainer();
      observer.didUpdateProvider(provider, 'initial', 'updated', container);
      expect(talker.history.whereType<RiverpodUpdateLog>().length, 1);
    });

    test('didUpdateProvider does not log when disabled', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: const TalkerRiverpodLoggerSettings(enabled: false),
      );
      final provider = StateProvider((ref) => 'initial', name: 'testProvider');
      final container = ProviderContainer();
      observer.didUpdateProvider(provider, 'initial', 'updated', container);
      expect(talker.history.whereType<RiverpodUpdateLog>().length, 0);
    });

    test(
      'didUpdateProvider does not log when printProviderUpdated is false',
      () {
        observer = TalkerRiverpodObserver(
          talker: talker,
          settings: const TalkerRiverpodLoggerSettings(
            printProviderUpdated: false,
          ),
        );
        final provider = StateProvider(
          (ref) => 'initial',
          name: 'testProvider',
        );
        final container = ProviderContainer();
        observer.didUpdateProvider(provider, 'initial', 'updated', container);
        expect(talker.history.whereType<RiverpodUpdateLog>().length, 0);
      },
    );

    test('didUpdateProvider does not log when providerFilter rejects', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(
          providerFilter: (provider) => provider.name != 'testProvider',
        ),
      );
      final provider = StateProvider((ref) => 'initial', name: 'testProvider');
      final container = ProviderContainer();
      observer.didUpdateProvider(provider, 'initial', 'updated', container);
      expect(talker.history.whereType<RiverpodUpdateLog>().length, 0);
    });
    test('didDisposeProvider logs when enabled and accepted', () {
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer(observers: [observer]);
      container.read(provider);
      container.dispose();
      expect(talker.history.whereType<RiverpodDisposeLog>().length, 1);
    });

    test('didDisposeProvider does not log when disabled', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: const TalkerRiverpodLoggerSettings(enabled: false),
      );
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      observer.didDisposeProvider(provider, container);
      expect(talker.history.whereType<RiverpodDisposeLog>().length, 0);
    });

    test(
      'didDisposeProvider does not log when printProviderDisposed is false',
      () {
        observer = TalkerRiverpodObserver(
          talker: talker,
          settings: const TalkerRiverpodLoggerSettings(
            printProviderDisposed: false,
          ),
        );
        final provider = Provider((ref) => 'test', name: 'testProvider');
        final container = ProviderContainer();
        observer.didDisposeProvider(provider, container);
        expect(talker.history.whereType<RiverpodDisposeLog>().length, 0);
      },
    );

    test('didDisposeProvider does not log when providerFilter rejects', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(
          providerFilter: (provider) => provider.name != 'testProvider',
        ),
      );
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      observer.didDisposeProvider(provider, container);
      expect(talker.history.whereType<RiverpodDisposeLog>().length, 0);
    });

    test('didDisposeProvider does not log when provider is filtered out', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(
          // Filter out providers that don't have a name
          providerFilter: (provider) => provider.name != null,
        ),
      );
      // Provider without a name
      final provider = Provider((ref) => 'test');
      final container = ProviderContainer();
      observer.didDisposeProvider(provider, container);
      expect(talker.history.whereType<RiverpodDisposeLog>().length, 0);
    });

    test('didDisposeProvider does not log when provider type is filtered out',
        () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(
          // Filter out StateProviders
          providerFilter: (provider) => provider is! StateProvider,
        ),
      );
      // A StateProvider that will be filtered out
      final provider = StateProvider((ref) => 0, name: 'filteredProvider');
      final container = ProviderContainer();
      observer.didDisposeProvider(provider, container);
      expect(talker.history.whereType<RiverpodDisposeLog>().length, 0);
    });

    test(
        'didDisposeProvider does not log when providerFilter rejects a FutureProvider',
        () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(
          printProviderDisposed: true,
          // Filter out FutureProviders
          providerFilter: (provider) => provider is! FutureProvider,
        ),
      );
      // A FutureProvider that will be filtered out
      final provider =
          FutureProvider((ref) => 'test', name: 'filteredProvider');
      final container = ProviderContainer();
      observer.didDisposeProvider(provider, container);
      expect(talker.history.whereType<RiverpodDisposeLog>().length, 0);
    });

    test('providerDidFail logs when enabled and accepted', () {
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      final error = Exception('test error');
      final stackTrace = StackTrace.current;
      observer.providerDidFail(provider, error, stackTrace, container);
      expect(talker.history.whereType<RiverpodFailLog>().length, 1);
    });

    test('providerDidFail does not log when disabled', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: const TalkerRiverpodLoggerSettings(enabled: false),
      );
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      final error = Exception('test error');
      final stackTrace = StackTrace.current;
      observer.providerDidFail(provider, error, stackTrace, container);
      expect(talker.history.whereType<RiverpodFailLog>().length, 0);
    });

    test('providerDidFail does not log when printProviderFailed is false', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: const TalkerRiverpodLoggerSettings(
          printProviderFailed: false,
        ),
      );
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      final error = Exception('test error');
      final stackTrace = StackTrace.current;
      observer.providerDidFail(provider, error, stackTrace, container);
      expect(talker.history.whereType<RiverpodFailLog>().length, 0);
    });

    test('providerDidFail does not log when providerFilter rejects', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(
          providerFilter: (provider) => provider.name != 'testProvider',
        ),
      );
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      final error = Exception('test error');
      final stackTrace = StackTrace.current;
      observer.providerDidFail(provider, error, stackTrace, container);
      expect(talker.history.whereType<RiverpodFailLog>().length, 0);
    });

    test('providerDidFail does not log when didFailFilter rejects', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(
          didFailFilter: (error) =>
              error.toString() != Exception('test error').toString(),
        ),
      );
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      final error = Exception('test error');
      final stackTrace = StackTrace.current;
      observer.providerDidFail(provider, error, stackTrace, container);
      expect(talker.history.whereType<RiverpodFailLog>().length, 0);
    });

    test('providerDidFail does not log when didFailFilter throws', () {
      observer = TalkerRiverpodObserver(
        talker: talker,
        settings: TalkerRiverpodLoggerSettings(
          // This filter will throw because Hello's toString() throws
          didFailFilter: (error) => error.toString().isNotEmpty,
        ),
      );
      final provider = Provider((ref) => 'test', name: 'testProvider');
      final container = ProviderContainer();
      final error = Hello();
      observer.providerDidFail(provider, error, StackTrace.current, container);
      expect(talker.history.whereType<RiverpodFailLog>().length, 0);
    });
  });
}

class Hello {
  void call() {
    throw UnimplementedError();
  }

  @override
  String toString() {
    throw UnimplementedError();
  }
}
