/// Formats a Duration into a more human-readable string.
///
/// Examples:
/// - `Duration(minutes: 15)` -> "15m"
/// - `Duration(seconds: 5, milliseconds: 50)` -> "5s 50ms"
/// - `Duration(milliseconds: 120)` -> "120ms"
String formatDuration(Duration d) {
  if (d.inDays > 0) return '${d.inDays}d';
  if (d.inHours > 0) return '${d.inHours}h';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  if (d.inSeconds > 0) {
    final ms = d.inMilliseconds % 1000;
    if (ms > 0) return '${d.inSeconds}s ${ms}ms';
    return '${d.inSeconds}s';
  }
  if (d.inMilliseconds > 0) return '${d.inMilliseconds}ms';
  if (d.inMicroseconds > 0) return '${d.inMicroseconds}µs';
  return '0ms';
}
