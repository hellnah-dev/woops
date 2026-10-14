import 'package:intl/intl.dart';

/// Short timestamp for conversation lists: "now", "5m", "3h", "Mon", "12 Mar".
String shortTimeAgo(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final local = time.toLocal();
  final diff = current.difference(local);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return DateFormat.E().format(local);
  if (local.year == current.year) return DateFormat('d MMM').format(local);
  return DateFormat('d MMM y').format(local);
}

/// Time shown on a message bubble.
String messageTime(DateTime time) => DateFormat.jm().format(time.toLocal());

/// Header between days in a chat: "Today", "Yesterday", "Mon, 12 Mar".
String dayLabel(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final local = time.toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (local.year == current.year) return DateFormat('EEE, d MMM').format(local);
  return DateFormat('d MMM y').format(local);
}
