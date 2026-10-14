import 'package:woops/core/supabase/supabase_providers.dart';
import 'package:woops/features/chat/application/chat_controllers.dart';
import 'package:woops/features/chat/data/chat_repository.dart';
import 'package:woops/features/chat/domain/chat_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  const args = (conversationId: 'c1', otherUserId: 'other');
  late FakeChatRepository repo;
  late ProviderContainer container;

  Future<ChatController> start() async {
    container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(repo), currentUserIdProvider.overrideWithValue('me')],
    );
    addTearDown(container.dispose);
    container.listen(chatControllerProvider(args), (_, _) {});
    await pumpEventQueue();
    return container.read(chatControllerProvider(args).notifier);
  }

  ChatState state() => container.read(chatControllerProvider(args));

  test('loads history newest-first and marks the conversation read', () async {
    final t = DateTime.utc(2026, 10, 14);
    repo = FakeChatRepository()..history = [msg('1', at: t), msg('2', at: t.add(const Duration(minutes: 1)))];
    await start();
    expect(state().messages.map((m) => m.id), ['2', '1']);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(repo.markReadCalls, 1);
  });

  test('sending shows an optimistic bubble that becomes the server message', () async {
    repo = FakeChatRepository();
    final c = await start();
    final future = c.send('  Hello there  ');
    expect(state().messages.single.delivery, DeliveryState.sending);
    expect(state().messages.single.body, 'Hello there');
    await future;
    expect(state().messages.single.delivery, DeliveryState.sent);
    expect(state().messages.single.id, startsWith('srv-'));
  });

  test('blank messages are ignored', () async {
    repo = FakeChatRepository();
    final c = await start();
    await c.send('   ');
    expect(state().messages, isEmpty);
    expect(repo.sentClientIds, isEmpty);
  });

  test('a failed send can be retried with the same client id (no duplicates)', () async {
    repo = FakeChatRepository()..failNextSends = 1;
    final c = await start();
    await c.send('Hi');
    final failed = state().messages.single;
    expect(failed.delivery, DeliveryState.failed);
    expect(state().error?.code, 'rate_limited');

    await c.retry(failed);
    expect(state().messages, hasLength(1));
    expect(state().messages.single.delivery, DeliveryState.sent);
    expect(repo.sentClientIds, [failed.clientId]);
  });

  test('realtime echo of my own message does not create a duplicate', () async {
    repo = FakeChatRepository();
    final c = await start();
    await c.send('Hi');
    final sent = state().messages.single;
    repo.incoming.add(sent); // the same row arrives through Realtime
    await pumpEventQueue();
    expect(state().messages, hasLength(1));
  });

  test('incoming messages from the match appear and trigger a read receipt', () async {
    repo = FakeChatRepository();
    await start();
    repo.incoming.add(msg('x', at: DateTime.now().toUtc()));
    await pumpEventQueue();
    expect(state().messages.single.id, 'x');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(repo.markReadCalls, greaterThanOrEqualTo(1));
  });

  test('read receipts from the other person update state', () async {
    repo = FakeChatRepository();
    await start();
    final at = DateTime.utc(2026, 10, 14, 12);
    repo.receipts.add(at);
    await pumpEventQueue();
    expect(state().otherReadAt, at);
  });
}
