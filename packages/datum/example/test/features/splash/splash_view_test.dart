import 'dart:async';

import 'package:example/features/splash/view/splash_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';

void main() {
  testWidgets('shows the loader, then the real error when init fails',
      (tester) async {
    final completer = Completer<void>();
    final init = futureSignal(() => completer.future);
    addTearDown(init.dispose);
    var initializedCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: SplashView(
        initialization: init,
        onInitialized: () => initializedCalls++,
      ),
    ));

    expect(find.byType(LoaderChild), findsOneWidget);
    expect(find.byType(InitializationError), findsNothing);

    completer.completeError(StateError('Supabase URL missing'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LoaderChild), findsNothing);
    expect(find.text('Initialization failed'), findsOneWidget);
    expect(find.textContaining('Supabase URL missing'), findsOneWidget);
    // The failure is not masked by a "not overridden"-style fallback.
    expect(find.textContaining('not overriden'), findsNothing);
    expect(initializedCalls, 0);
  });

  testWidgets('calls onInitialized exactly once after success', (tester) async {
    final completer = Completer<void>();
    final init = futureSignal(() => completer.future);
    addTearDown(init.dispose);
    var initializedCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: SplashView(
        initialization: init,
        onInitialized: () => initializedCalls++,
      ),
    ));
    expect(find.byType(LoaderChild), findsOneWidget);
    expect(initializedCalls, 0);

    completer.complete();
    await tester.pump();
    await tester.pump();

    expect(initializedCalls, 1);
    expect(find.byType(LoaderChild), findsNothing);
    expect(find.byType(InitializationError), findsNothing);

    // Further rebuilds don't re-fire the callback.
    await tester.pump(const Duration(seconds: 1));
    expect(initializedCalls, 1);
  });
}
