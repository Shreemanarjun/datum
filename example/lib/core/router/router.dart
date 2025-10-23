import 'package:auto_route/auto_route.dart';
import 'package:example/core/router/guard/auth_guard.dart';
import 'package:example/core/router/router.gr.dart';

/// This class used for defined routes and paths na dother properties
@AutoRouterConfig()
class AppRouter extends RootStackRouter {
  @override
  late final List<AutoRoute> routes = [
    AutoRoute(
      page: CounterRoute.page,
      path: '/counter',
    ),
    AutoRoute(
      page: LoginRoute.page,
      path: '/login',
      initial: true,
    ),
    AutoRoute(
      page: HomeRoute.page,
      path: '/home',
    ),
    AutoRoute(
      page: SimpleDatumRoute.page,
      path: '/simple_datum',
      guards: [
        AuthGuard(),
      ],
    ),
  ];
}
