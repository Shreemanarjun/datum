import 'package:auto_route/auto_route.dart';
import 'package:example/core/router/router.gr.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (Supabase.instance.client.auth.currentSession != null) {
      // if user is authenticated then we continue
      resolver.next(true);
    } else {
      // we redirect the user to our login page
      router.replaceAll([LoginRoute()]);
    }
  }
}
