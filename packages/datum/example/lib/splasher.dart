import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:example/app/view/app.dart';
import 'package:example/bootstrap.dart';
import 'package:example/features/tasks/presentation/controllers/datum_provider_with_lifecycle.dart';
import 'package:example/features/splash/controller/future_initializer.dart';
import 'package:example/features/splash/view/splash_view.dart';

class Splasher extends StatelessWidget {
  const Splasher({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primaryColor: Colors.blue),
      home: SplashView(
        initialization: appInitialization,
        onInitialized: () => bootstrap(
          () => ScreenUtilInit(
            designSize: const Size(375, 812),
            useInheritedMediaQuery: false,
            minTextAdapt: true,
            splitScreenMode: true,
            enableScaleText: () => true,
            enableScaleWH: () => false,
            ensureScreenSize: true,
            child: DatumProviderWithLifecycle(child: const App()),
          ),
        ),
      ),
    );
  }
}
