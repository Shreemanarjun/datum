import 'package:collection/collection.dart';

const _deep = DeepCollectionEquality();

/// Keys of [current] whose values differ (deeply) from [previous], with their
/// new values; `null` when nothing changed. Default `diff` for hand-written
/// entities, over their remote maps: the delta is what gets sent upstream.
Map<String, dynamic>? diffDatumMaps(
  Map<String, dynamic> current,
  Map<String, dynamic> previous,
) {
  final changes = <String, dynamic>{
    for (final MapEntry(:key, :value) in current.entries)
      if (!previous.containsKey(key) || !_deep.equals(value, previous[key])) key: value,
  };
  return changes.isEmpty ? null : changes;
}
