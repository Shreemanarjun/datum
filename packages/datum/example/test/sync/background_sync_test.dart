import 'package:datum/datum.dart';

import 'package:datum_hive/datum_hive.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_test/hive_ce_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test/mocks/mock_adapters.dart';

class MockConnectivityChecker extends Mock
    implements DatumConnectivityChecker {}

void main() {
  group('Background Sync', () {
    late Datum datum;
    late MockRemoteAdapter<Task> remoteAdapter;
    late MockConnectivityChecker connectivityChecker;

    setUp(() async {
      await setUpTestHive();
      remoteAdapter = MockRemoteAdapter<Task>();
      connectivityChecker = MockConnectivityChecker();

      // Stub the connectivity checker methods
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);
      when(() => connectivityChecker.onStatusChange)
          .thenAnswer((_) => Stream.value(true));

      (await Datum.initialize(
        config: DatumConfig(),
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<Task>(
            localAdapter: HiveLocalAdapter<Task>(
              entityBoxName: 'test_task',
              fromMap: (map) => Task.fromMap(map),
            ),
            remoteAdapter: remoteAdapter,
          ),
        ],
      ))
          .fold(
        (l, s) => throw l,
        (r) => datum = r,
      );
    });

    tearDown(() async {
      await datum.dispose();
      await tearDownTestHive();
    });

    testWidgets('should unsubscribe and resubscribe on app lifecycle changes',
        (tester) async {
      final binding = tester.binding;

      // Build the app
      await tester.pumpWidget(
        MaterialApp(
          home: DatumProviderWithLifecycle(
            child: Container(),
          ),
        ),
      );

      // Simulate going to the background
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // Verify that unsubscribeFromChanges was called
      expect(remoteAdapter.isSubscribed, isFalse);

      // Simulate coming back to the foreground
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Verify that resubscribeToChanges was called
      expect(remoteAdapter.isSubscribed, isTrue);
    });
  });
}

class Task extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  Task({
    required this.id,
    required this.userId,
    DateTime? modifiedAt,
    DateTime? createdAt,
    this.version = 1,
    this.isDeleted = false,
  })  : modifiedAt = modifiedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) {
    return {
      'id': id,
      'userId': userId,
      'modifiedAt': modifiedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'version': version,
      'isDeleted': isDeleted,
    };
  }

  static Task fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      userId: map['userId'],
      modifiedAt: DateTime.parse(map['modifiedAt']),
      createdAt: DateTime.parse(map['createdAt']),
      version: map['version'],
      isDeleted: map['isDeleted'],
    );
  }

  DatumEntityInterface copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
  }) {
    return Task(
      id: id,
      userId: userId,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(covariant DatumEntityInterface oldVersion) {
    return null;
  }
}

class DatumProviderWithLifecycle extends StatefulWidget {
  final Widget child;

  const DatumProviderWithLifecycle({super.key, required this.child});

  @override
  DatumProviderWithLifecycleState createState() =>
      DatumProviderWithLifecycleState();
}

class DatumProviderWithLifecycleState extends State<DatumProviderWithLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      Datum.instance.unsubscribeAllFromRemoteChanges();
    } else if (state == AppLifecycleState.resumed) {
      Datum.instance.resubscribeAllToRemoteChanges();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
