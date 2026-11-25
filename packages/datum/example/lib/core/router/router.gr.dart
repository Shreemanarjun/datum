// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i7;
import 'package:example/features/auth/presentation/view/login_page.dart' as _i4;
import 'package:example/features/dashboard/dashboard_page.dart' as _i2;
import 'package:example/features/home/view/home_page.dart' as _i3;
import 'package:example/features/paint/view/paint_page.dart' as _i5;
import 'package:example/features/settings/settings_page.dart' as _i1;
import 'package:example/features/tasks/presentation/views/simple_datum_page.dart'
    as _i6;

/// generated route for
/// [_i2.DashboardPage]
class DashboardRoute extends _i7.PageRouteInfo<void> {
  const DashboardRoute({List<_i7.PageRouteInfo>? children})
      : super(DashboardRoute.name, initialChildren: children);

  static const String name = 'DashboardRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i2.DashboardPage();
    },
  );
}

/// generated route for
/// [_i3.HomePage]
class HomeRoute extends _i7.PageRouteInfo<void> {
  const HomeRoute({List<_i7.PageRouteInfo>? children})
      : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i3.HomePage();
    },
  );
}

/// generated route for
/// [_i4.LoginPage]
class LoginRoute extends _i7.PageRouteInfo<void> {
  const LoginRoute({List<_i7.PageRouteInfo>? children})
      : super(LoginRoute.name, initialChildren: children);

  static const String name = 'LoginRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i4.LoginPage();
    },
  );
}

/// generated route for
/// [_i5.PaintPage]
class PaintRoute extends _i7.PageRouteInfo<void> {
  const PaintRoute({List<_i7.PageRouteInfo>? children})
      : super(PaintRoute.name, initialChildren: children);

  static const String name = 'PaintRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i5.PaintPage();
    },
  );
}

/// generated route for
/// [_i6.SimpleDatumPage]
class SimpleDatumRoute extends _i7.PageRouteInfo<void> {
  const SimpleDatumRoute({List<_i7.PageRouteInfo>? children})
      : super(SimpleDatumRoute.name, initialChildren: children);

  static const String name = 'SimpleDatumRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i6.SimpleDatumPage();
    },
  );
}

/// generated route for
/// [_i1.SettingsPage]
class SettingsRoute extends _i7.PageRouteInfo<void> {
  const SettingsRoute({List<_i7.PageRouteInfo>? children})
      : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i1.SettingsPage();
    },
  );
}
