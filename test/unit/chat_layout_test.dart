import 'package:flutter_test/flutter_test.dart';
import 'package:woops/features/chat/domain/chat_models.dart';
import 'package:woops/features/chat/presentation/chat_layout.dart';

ChatMessage msg(String sender, DateTime at, {MessageKind kind = MessageKind.text}) => ChatMessage(
  id: '$sender-${at.millisecondsSinceEpoch}',
  conversationId: 'c',
  senderId: sender,
  clientId: '$sender-${at.millisecondsSinceEpoch}',
  kind: kind,
  createdAt: at,
  body: 'hi',
);

void main() {
  final t = DateTime(2026, 10, 22, 12);

  group('isSameGroup', () {
    test('same sender within a few minutes groups', () {
      expect(isSameGroup(msg('a', t), msg('a', t.add(const Duration(minutes: 2)))), isTrue);
    });
    test('different sender, long pause, system or missing never group', () {
      expect(isSameGroup(msg('a', t), msg('b', t)), isFalse);
      expect(isSameGroup(msg('a', t), msg('a', t.add(const Duration(minutes: 6)))), isFalse);
      expect(isSameGroup(msg('a', t), msg('a', t, kind: MessageKind.system)), isFalse);
      expect(isSameGroup(null, msg('a', t)), isFalse);
    });
    test('never across midnight', () {
      final late = DateTime(2026, 10, 22, 23, 59);
      expect(isSameGroup(msg('a', late), msg('a', late.add(const Duration(minutes: 2)))), isFalse);
    });
  });

  group('needsTimeHeader', () {
    test('first message and long pauses get a header', () {
      expect(needsTimeHeader(null, msg('a', t)), isTrue);
      expect(needsTimeHeader(msg('a', t), msg('b', t.add(const Duration(minutes: 20)))), isTrue);
    });
    test('quick replies do not', () {
      expect(needsTimeHeader(msg('a', t), msg('b', t.add(const Duration(minutes: 3)))), isFalse);
    });
  });

  group('isBigEmoji', () {
    test('one to three emoji only', () {
      expect(isBigEmoji('😍'), isTrue);
      expect(isBigEmoji('❤️'), isTrue);
      expect(isBigEmoji('👍🏽'), isTrue);
      expect(isBigEmoji('👨‍👩‍👧'), isTrue);
      expect(isBigEmoji(' 😂😂😂 '), isTrue);
      expect(isBigEmoji('🇳🇵'), isTrue);
    });
    test('text, digits, or many emoji stay in a bubble', () {
      expect(isBigEmoji('hi 😍'), isFalse);
      expect(isBigEmoji('123'), isFalse);
      expect(isBigEmoji('#'), isFalse);
      expect(isBigEmoji('😂😂😂😂'), isFalse);
      expect(isBigEmoji(''), isFalse);
      expect(isBigEmoji(null), isFalse);
    });
  });
}
