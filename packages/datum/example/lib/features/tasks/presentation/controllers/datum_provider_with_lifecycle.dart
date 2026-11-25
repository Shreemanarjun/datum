import 'package:datum/datum.dart';
import 'package:example/bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    talker.debug('App lifecycle state changed: $state');

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // The adapter handles background/foreground transitions automatically
        talker.debug(
            'App backgrounded - adapter will handle reconnection automatically');
        break;

      case AppLifecycleState.resumed:
        // When app resumes, trigger a sync to catch up on any changes missed during background
        talker.debug(
            'App foregrounded - triggering sync to catch up on missed changes');
        _syncOnResume();
        break;

      case AppLifecycleState.detached:
        // Clean up on app termination
        talker.debug('App terminating - cleaning up subscriptions');
        Datum.instance.unsubscribeAllFromRemoteChanges();
        break;
    }
  }

  Future<void> _syncOnResume() async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        talker.info(
            'Performing background catch-up sync for user: ${currentUser.id}');
        await Datum.instance.synchronize(
          currentUser.id,
          options: DatumSyncOptions(
            forceFullSync:
                true, // Force full sync to ensure we get all changes missed during background
            direction: SyncDirection.pullOnly, // Only pull to avoid conflicts
          ),
        );
        talker.debug('Background catch-up sync completed successfully');
      } else {
        talker.debug(
            'No authenticated user found, skipping background catch-up sync');
      }
    } catch (e, stackTrace) {
      talker.error(
          'Failed to perform background catch-up sync: $e', stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
