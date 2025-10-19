import 'package:example/features/simple_datum/view/simple_datum_page.dart';
import 'package:example/shared/riverpod_ext/asynvalue_easy_when.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MetricsStatusWidget extends ConsumerWidget {
  const MetricsStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the new top-level provider for pending operations count.
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const SizedBox.shrink();
    final pendingOpsAsync = ref.watch(pendingOperationsProvider(userId));

    return pendingOpsAsync.easyWhen(
      data: (count) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Badge(
          label: Text(count.toString()),
          isLabelVisible: count > 0,
          child: const Icon(Icons.pending_actions),
        ),
      ),
      loadingWidget: () => const SizedBox.shrink(),
      errorWidget: (e, st) => const SizedBox.shrink(),
    );
  }
}
