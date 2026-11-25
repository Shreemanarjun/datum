import 'package:flutter/material.dart';
import 'package:example/bootstrap.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// Shows a loader while [initialization] runs, then calls [onInitialized].
/// An initialization failure is logged and shown on screen.
class SplashView extends SignalStatefulWidget {
  const SplashView({
    super.key,
    required this.initialization,
    required this.onInitialized,
  });

  final FutureSignal<void> initialization;
  final VoidCallback onInitialized;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  final _stopwatch = Stopwatch()..start();
  late final EffectCleanup _disposeEffect;

  @override
  void initState() {
    super.initState();
    _disposeEffect = effect(() {
      switch (widget.initialization.value) {
        case AsyncData():
          talker
              .info('Initialization took ${_stopwatch.elapsedMilliseconds}ms');
          untracked(widget.onInitialized);
        case AsyncError(:final error, :final stackTrace):
          talker.error('Initialization failed', error, stackTrace);
        default:
      }
    });
  }

  @override
  void dispose() {
    _disposeEffect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.initialization.value) {
      AsyncError(:final error, :final stackTrace) =>
        InitializationError(error: error, stackTrace: stackTrace),
      AsyncData() => const SizedBox.shrink(),
      _ => const LoaderChild(),
    };
  }
}

class InitializationError extends StatelessWidget {
  const InitializationError(
      {super.key, required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Initialization failed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText('$error',
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              SelectableText('$stackTrace',
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class LoaderChild extends StatefulWidget {
  const LoaderChild({
    super.key,
  });

  @override
  State<LoaderChild> createState() => _LoaderChildState();
}

class _LoaderChildState extends State<LoaderChild>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(seconds: 2),
    vsync: this,
  )..repeat(reverse: true);
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.elasticOut,
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: Colors.white,
        child: Stack(
          alignment: AlignmentDirectional.center,
          children: [
            Center(
              child: RotationTransition(
                turns: _animation,
                child: const FlutterLogo(
                  size: 100,
                ),
              ),
            ),
            const Positioned(
              bottom: 44,
              child: CircularProgressIndicator(
                color: Colors.amber,
              ),
            ),
            const Positioned(
              bottom: 16,
              child: Material(
                  child: Text(
                "Welcome to Datum Example App",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              )),
            ),
          ],
        ),
      ),
    );
  }
}
