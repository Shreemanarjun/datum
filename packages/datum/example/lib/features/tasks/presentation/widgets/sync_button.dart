import 'package:datum/datum.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// Reusable sync button widget
class SyncButton extends SignalStatefulWidget {
  final String userId;
  final VoidCallback onSyncStart;
  final Function(DatumSyncResult<DatumEntityInterface>) onSyncComplete;
  final Function(dynamic) onSyncError;

  const SyncButton({
    super.key,
    required this.userId,
    required this.onSyncStart,
    required this.onSyncComplete,
    required this.onSyncError,
  });

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton> {
  late final _status =
      streamSignal(() => Datum.instance.statusForUser(widget.userId));

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _status.value.map(
      data: (status) {
        if (status?.status == DatumSyncStatus.syncing) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: Tooltip(
                message:
                    'Syncing... ${(status!.progress * 100).toStringAsFixed(0)}%',
                child: CircularProgressIndicator(
                  value: status.progress > 0 ? status.progress : null,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        }
        return Tooltip(
          message: 'Push and pull changes with remote',
          child: IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _handleSync,
          ),
        );
      },
      error: (error, _) => Tooltip(
        message: 'Sync status unavailable: $error',
        child: IconButton(
          icon: const Icon(Icons.sync_problem),
          onPressed: _handleSync,
        ),
      ),
      loading: () => const Padding(
        padding: EdgeInsets.all(16.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Future<void> _handleSync() async {
    widget.onSyncStart();
    try {
      widget.onSyncComplete(await Datum.instance.synchronize(widget.userId));
    } catch (e) {
      widget.onSyncError(e);
    }
  }
}
