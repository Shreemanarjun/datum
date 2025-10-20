// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i5;
import 'package:example/features/counter/view/counter_page.dart'
    deferred as _i1;
import 'package:example/features/home/view/home_page.dart' as _i2;
import 'package:example/features/login/view/login_page.dart' as _i3;
import 'package:example/features/simple_datum/view/simple_datum_page.dart'
    as _i4;

/// generated route for
/// [_i1.CounterPage]
class CounterRoute extends _i5.PageRouteInfo<void> {
  const CounterRoute({List<_i5.PageRouteInfo>? children})
      : super(CounterRoute.name, initialChildren: children);

  static const String name = 'CounterRoute';

  static _i5.PageInfo page = _i5.PageInfo(
    name,
    builder: (data) {
      return _i5.DeferredWidget(_i1.loadLibrary, () => _i1.CounterPage());
    },
  );
}

/// generated route for
/// [_i2.HomePage]
class HomeRoute extends _i5.PageRouteInfo<void> {
  const HomeRoute({List<_i5.PageRouteInfo>? children})
      : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i5.PageInfo page = _i5.PageInfo(
    name,
    builder: (data) {
      return const _i2.HomePage();
    },
  );
}

/// generated route for
/// [_i3.LoginPage]
class LoginRoute extends _i5.PageRouteInfo<void> {
  const LoginRoute({List<_i5.PageRouteInfo>? children})
      : super(LoginRoute.name, initialChildren: children);

  static const String name = 'LoginRoute';

  static _i5.PageInfo page = _i5.PageInfo(
    name,
    builder: (data) {
      return const _i3.LoginPage();
    },
  );
}

/// generated route for
/// [_i4.SimpleDatumPage]
class SimpleDatumRoute extends _i5.PageRouteInfo<void> {
  const SimpleDatumRoute({List<_i5.PageRouteInfo>? children})
      : super(SimpleDatumRoute.name, initialChildren: children);

  static const String name = 'SimpleDatumRoute';

  static _i5.PageInfo page = _i5.PageInfo(
    name,
    builder: (data) {
      return const _i4.SimpleDatumPage();
    },
  );
}
