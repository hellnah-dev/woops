import '../domain/chat_models.dart';

/// Messages from the same person this close together share one bubble group
/// (joined corners, one avatar), like Instagram.
const groupGap = Duration(minutes: 5);

/// A centered time header appears after a pause this long.
const timeHeaderGap = Duration(minutes: 15);

/// Whether [a] and [b] (neighbours in the list) belong to one bubble group.
bool isSameGroup(ChatMessage? a, ChatMessage? b) {
  if (a == null || b == null) return false;
  if (a.kind == MessageKind.system || b.kind == MessageKind.system) return false;
  if (a.senderId != b.senderId) return false;
  final local = (a.createdAt.toLocal(), b.createdAt.toLocal());
  if (local.$1.day != local.$2.day || local.$1.month != local.$2.month || local.$1.year != local.$2.year) {
    return false;
  }
  return a.createdAt.difference(b.createdAt).abs() < groupGap;
}

/// Whether [message] gets a time header above it. [older] is the message
/// shown just above it (null for the first message of the chat).
bool needsTimeHeader(ChatMessage? older, ChatMessage message) {
  if (older == null) return true;
  final a = older.createdAt.toLocal();
  final b = message.createdAt.toLocal();
  if (a.day != b.day || a.month != b.month || a.year != b.year) return true;
  return b.difference(a) >= timeHeaderGap;
}

// The analyzer doesn't know Unicode property escapes; the runtime does.
final _emojiOnly = RegExp(
  // ignore: valid_regexps
  r'^(?:\p{Extended_Pictographic}|\p{Emoji_Modifier}|\p{Regional_Indicator}|\u200d|\ufe0f|\s)+$',
  unicode: true,
);
// ignore: valid_regexps
final _pictograph = RegExp(r'\p{Extended_Pictographic}|\p{Regional_Indicator}{2}', unicode: true);

/// One to three emoji and nothing else: shown large, without a bubble.
bool isBigEmoji(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty || t.length > 40 || !_emojiOnly.hasMatch(t)) return false;
  final count = _pictograph.allMatches(t).length;
  return count >= 1 && count <= 3;
}
