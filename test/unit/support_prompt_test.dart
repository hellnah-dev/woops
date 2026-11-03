import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woops/features/support/support_prompt.dart';

void main() {
  final t0 = DateTime(2026, 10, 22, 12);

  Future<SupportPromptPolicy> policy([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    return SupportPromptPolicy(await SharedPreferences.getInstance());
  }

  test('a first match asks once', () async {
    final p = await policy();
    expect(p.shouldAsk(SupportMoment.firstMatch, now: t0), isTrue);
    await p.markAsked(SupportMoment.firstMatch, now: t0);
    expect(p.shouldAsk(SupportMoment.firstMatch, now: t0.add(const Duration(days: 30))), isFalse);
  });

  test('never two asks within 3 days', () async {
    final p = await policy();
    for (var i = 0; i < SupportPromptPolicy.messagesBeforeAsking; i++) {
      await p.noteMessageSent();
    }
    await p.markAsked(SupportMoment.firstMatch, now: t0);
    expect(p.shouldAsk(SupportMoment.chatting, now: t0.add(const Duration(days: 2))), isFalse);
    expect(p.shouldAsk(SupportMoment.chatting, now: t0.add(const Duration(days: 3))), isTrue);
  });

  test('chatting waits for enough sent messages', () async {
    final p = await policy();
    for (var i = 0; i < SupportPromptPolicy.messagesBeforeAsking - 1; i++) {
      await p.noteMessageSent();
    }
    expect(p.shouldAsk(SupportMoment.chatting, now: t0), isFalse);
    await p.noteMessageSent();
    expect(p.shouldAsk(SupportMoment.chatting, now: t0), isTrue);
  });

  test('regular waits a week after the first open', () async {
    final p = await policy();
    expect(p.shouldAsk(SupportMoment.regular, now: t0), isFalse);
    await p.noteAppOpened(now: t0);
    await p.noteAppOpened(now: t0.add(const Duration(days: 5))); // keeps the first date
    expect(p.shouldAsk(SupportMoment.regular, now: t0.add(const Duration(days: 6))), isFalse);
    expect(p.shouldAsk(SupportMoment.regular, now: t0.add(const Duration(days: 7))), isTrue);
  });

  test('after helping or "don’t ask again", it never asks', () async {
    final p = await policy();
    await p.markDone();
    expect(p.shouldAsk(SupportMoment.firstMatch, now: t0), isFalse);
  });
}
