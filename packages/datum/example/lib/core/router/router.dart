import 'dart:async';

import 'package:example/bootstrap.dart';
import 'package:example/features/auth/presentation/view/login_page.dart';
import 'package:example/features/dashboard/dashboard_page.dart';
import 'package:flutter/widgets.dart';
import 'package:kaisel/kaisel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Top-level routes. Typed values, no string paths, no codegen.
sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class Login extends AppRoute {
  const Login();
}

final class Dashboard extends AppRoute {
  const Dashboard();
}

/// Notifies when the Supabase session appears or disappears.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (signedIn != _last) notifyListeners();
      _last = signedIn;
    });
  }

  late final StreamSubscription<AuthState> _sub;
  late bool _last = signedIn;

  bool get signedIn => Supabase.instance.client.auth.currentSession != null;

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

/// Signed out → [Login]; signed in → [Dashboard]. Re-runs on auth changes, so
/// sign-in and sign-out navigate on their own.
KaiselRouterConfig<AppRoute> createRouterConfig() {
  final auth = _AuthListenable();
  return KaiselRouterConfig<AppRoute>(
    initial: auth.signedIn ? const Dashboard() : const Login(),
    reevaluateOn: auth,
    guards: [
      (current, proposed) => auth.signedIn
          ? [for (final r in proposed) r is Login ? const Dashboard() : r]
          : const [Login()],
    ],
    onScreenChanged: (screen) => talker.debug('Route: $screen'),
    builder: (context, route) => switch (route) {
      Login() => const LoginPage(),
      Dashboard() => const DashboardPage(),
    },
  );
}
