import 'package:datum/datum.dart';
import 'package:example/data/task/entity/task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LastSyncResultNotifier extends Notifier<DatumSyncResult<DatumEntity>?> {
  @override
  DatumSyncResult<DatumEntity>? build() {
    // Load the initial value from storage.
    _load();
    return null; // Start with null, update when loaded.
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    // Since this is a global result display, we can't assume a single type.
    // For this example, we'll still fetch the Task result as a default.
    state = await Datum.manager<Task>().getLastSyncResult(userId)
        as DatumSyncResult<DatumEntity>?;
  }

  void update(DatumSyncResult<DatumEntity> result) {
    state = result;
    // The manager now automatically saves the result, so we don't need to do it here.
  }
}

final lastSyncResultProvider =
    NotifierProvider<LastSyncResultNotifier, DatumSyncResult<DatumEntity>?>(
  LastSyncResultNotifier.new,
  name: 'lastSyncResultProvider',
);
