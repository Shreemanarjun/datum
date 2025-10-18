// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:example/custom_connectivity_checker.dart';
import 'package:example/custom_datum_logger.dart';
import 'package:example/data/user/adapters/local.dart';
import 'package:example/data/user/adapters/user_remote_adapter.dart';
import 'package:example/data/user/entity/user.dart';
import 'package:example/my_datum_observer.dart';
import 'package:flutter/material.dart';
import 'package:datum/datum.dart';
import 'package:talker_flutter/talker_flutter.dart';

final Talker talker = TalkerFlutter.init();

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Add this line
  const config = DatumConfig(enableLogging: true, autoStartSync: true);
  Datum.initialize(
    config: config,
    connectivityChecker: CustomConnectivityChecker(),
    logger: CustomDatumLogger(enabled: config.enableLogging),
    observers: [MyDatumObserver()],
    registrations: [
      DatumRegistration<User>(
        localAdapter: UserLocalAdapter(),
        remoteAdapter: UserRemoteAdapter(),
      ),
    ],
  ).then((_) => runApp(const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,

        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
