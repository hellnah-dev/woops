import 'dart:typed_data';

import 'package:woops/core/supabase/supabase_providers.dart';
import 'package:woops/core/utils/image_processing.dart';
import 'package:woops/features/chat/application/chat_controllers.dart';
import 'package:woops/features/chat/data/chat_crypto.dart';
import 'package:woops/features/chat/data/chat_repository.dart';
import 'package:woops/features/chat/data/local_chat_store.dart';
import 'package:woops/features/chat/domain/chat_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  const args = (conversationId: 'c1', otherUserId: 'other');
  late FakeChatRepository repo;
  late MemoryLocalChatStore store;
  late ProviderContainer container;

  late ChatCrypto myCrypto;
  late ChatCrypto theirCrypto;

  setUp(() {
    store = MemoryLocalChatStore();
  });

  /// Both phones' keys; "other" has published theirs so I can encrypt to them.
  Future<void> withKeys() async {
    myCrypto = ChatCrypto(vault: MemoryKeyVault(), userId: 'me', fetchPublicKey: repo.fetchChatKey);
    theirCrypto = ChatCrypto(
      vault: MemoryKeyVault(),
      userId: 'other',
      fetchPublicKey: (id) async => id == 'me' ? await myCrypto.myPublicKey() : null,
    );
    repo.chatKeys['other'] = await theirCrypto.myPublicKey();
    repo.chatKeys['me'] = await myCrypto.myPublicKey();
  }

  Future<ChatController> start() async {
    container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        localChatStoreProvider.overrideWithValue(store),
        currentUserIdProvider.overrideWithValue('me'),
        chatCryptoProvider.overrideWith(
          (ref) => ChatCrypto(vault: MemoryKeyVault(), userId: 'me', fetchPublicKey: repo.fetchChatKey),
        ),
        imageProcessorProvider.overrideWithValue(ImageProcessor(isWeb: true)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(chatControllerProvider(args), (_, _) {});
    await pumpEventQueue();
    return container.read(chatControllerProvider(args).notifier);
  }

  ChatState state() => container.read(chatControllerProvider(args));

  test('loads history from the phone newest-first and marks the conversation read', () async {
    final t = DateTime.utc(2026, 10, 14);
    await store.upsert('c1', [msg('1', at: t), msg('2', at: t.add(const Duration(minutes: 1)))]);
    repo = FakeChatRepository();
    await start();
    expect(state().messages.map((m) => m.id), ['2', '1']);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(repo.markReadCalls, 1);
    expect((await store.read('c1')).unreadFor('me'), 0);
  });

  test('messages waiting on the relay are saved locally, then acknowledged', () async {
    repo = FakeChatRepository()..pending = [msg('p1', at: DateTime.utc(2026, 10, 14))];
    await start();
    await pumpEventQueue();
    expect((await store.read('c1')).messages.map((m) => m.id), ['p1']);
    expect(repo.ackedIds, ['p1']);
    expect(repo.pending, isEmpty);
    expect(state().messages.map((m) => m.id), ['p1']);
  });

  test('sending shows an optimistic bubble that becomes the server message and is saved', () async {
    repo = FakeChatRepository();
    final c = await start();
    final future = c.send('  Hello there  ');
    expect(state().messages.single.delivery, DeliveryState.sending);
    expect(state().messages.single.body, 'Hello there');
    await future;
    expect(state().messages.single.delivery, DeliveryState.sent);
    expect(state().messages.single.id, startsWith('srv-'));
    expect((await store.read('c1')).messages.single.delivery, DeliveryState.sent);
  });

  test('blank messages are ignored', () async {
    repo = FakeChatRepository();
    final c = await start();
    await c.send('   ');
    expect(state().messages, isEmpty);
    expect(repo.sentClientIds, isEmpty);
  });

  test('a failed send is kept on the phone and can be retried with the same client id', () async {
    repo = FakeChatRepository()..failNextSends = 1;
    final c = await start();
    await c.send('Hi');
    final failed = state().messages.single;
    expect(failed.delivery, DeliveryState.failed);
    expect(state().error?.code, 'rate_limited');
    expect((await store.read('c1')).messages.single.delivery, DeliveryState.failed);

    await c.retry(failed);
    await pumpEventQueue();
    expect(state().messages, hasLength(1));
    expect(state().messages.single.delivery, DeliveryState.sent);
    expect(repo.sentClientIds, [failed.clientId]);
  });

  test('realtime echo of my own message does not create a duplicate and is not acked', () async {
    repo = FakeChatRepository();
    final c = await start();
    await c.send('Hi');
    final sent = state().messages.single;
    repo.incoming.add(sent);
    await pumpEventQueue();
    expect(state().messages, hasLength(1));
    expect(repo.ackedIds, isEmpty);
  });

  test('incoming messages are saved, acknowledged and trigger a read receipt', () async {
    repo = FakeChatRepository();
    await start();
    repo.incoming.add(msg('x', at: DateTime.now().toUtc()));
    await pumpEventQueue();
    expect(state().messages.single.id, 'x');
    expect((await store.read('c1')).messages.single.id, 'x');
    expect(repo.ackedIds, ['x']);
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

  test('local messages survive a JSON round trip; "sending" restores as failed', () {
    final m = msg('a', at: DateTime.utc(2026, 10, 14)).copyWith(delivery: DeliveryState.sending);
    final back = ChatMessage.fromLocalJson(m.toLocalJson());
    expect(back.id, 'a');
    expect(back.body, m.body);
    expect(back.delivery, DeliveryState.failed);
  });

  group('end-to-end encryption', () {
    Future<ChatController> startWithKeys() async {
      repo = FakeChatRepository();
      await withKeys();
      container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          localChatStoreProvider.overrideWithValue(store),
          currentUserIdProvider.overrideWithValue('me'),
          chatCryptoProvider.overrideWithValue(myCrypto),
          imageProcessorProvider.overrideWithValue(ImageProcessor(isWeb: true)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(chatControllerProvider(args), (_, _) {});
      await pumpEventQueue();
      return container.read(chatControllerProvider(args).notifier);
    }

    test('both phones derive the same key; tampering is detected', () async {
      repo = FakeChatRepository();
      await withKeys();
      final sealed = await theirCrypto.encrypt('Hey you 💕', conversationId: 'c1', otherUserId: 'me');
      expect(sealed, isNot(contains('Hey you')));
      expect(await myCrypto.decrypt(sealed, conversationId: 'c1'), 'Hey you 💕');
      // The sender can also read their own envelope.
      expect(await theirCrypto.decrypt(sealed, conversationId: 'c1'), 'Hey you 💕');
      // Bound to the conversation: another conversation can't open it.
      await expectLater(myCrypto.decrypt(sealed, conversationId: 'c2'), throwsA(anything));
      final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final media = await myCrypto.encryptBytes(bytes);
      expect(media.bytes, isNot(bytes));
      expect(await theirCrypto.decryptBytes(media.bytes, media.key), bytes);
    });

    test('messages are sent as ciphertext and kept readable on my phone', () async {
      final c = await startWithKeys();
      await c.send('A secret hello');
      expect(repo.sentEncrypted, [true]);
      expect(repo.sentBodies.single, isNot(contains('A secret hello')));
      expect(await theirCrypto.decrypt(repo.sentBodies.single, conversationId: 'c1'), 'A secret hello');
      final local = (await store.read('c1')).messages.single;
      expect(local.body, 'A secret hello');
      expect(local.encrypted, isTrue);
    });

    test('incoming encrypted messages are decrypted before they are saved', () async {
      await startWithKeys();
      final sealed = await theirCrypto.encrypt('Dinner Friday?', conversationId: 'c1', otherUserId: 'me');
      repo.incoming.add(msg('e1', at: DateTime.now().toUtc()).copyWith(body: sealed, encrypted: true));
      await pumpEventQueue();
      expect(state().messages.single.body, 'Dinner Friday?');
      expect((await store.read('c1')).messages.single.body, 'Dinner Friday?');
      expect(repo.ackedIds, ['e1']);
    });

    test('photos: encrypted on the relay, saved on the phone, then deleted from the server', () async {
      final c = await startWithKeys();
      final photo = Uint8List.fromList(List.generate(5000, (i) => (i * 7) % 256));
      await c.sendPhoto(photo);
      expect(repo.sentEncrypted, [true]);
      final path = repo.media.keys.single;
      expect(path, startsWith('me/c1/'));
      expect(repo.media[path], isNot(photo)); // only ciphertext leaves the phone
      final mine = state().messages.single;
      expect(mine.kind, MessageKind.image);
      expect(store.media[mine.localPath], photo);

      // The other phone receives it through the relay.
      final otherStore = MemoryLocalChatStore();
      final otherRepo = FakeChatRepository(myId: 'other')..media.addAll(repo.media);
      final sync = ChatSync(otherRepo, otherStore, theirCrypto, 'other');
      final relayed = ChatMessage(
        id: 'm1',
        conversationId: 'c1',
        senderId: 'me',
        clientId: mine.clientId,
        kind: MessageKind.image,
        body: repo.sentBodies.single,
        mediaPath: path,
        encrypted: true,
        createdAt: DateTime.now().toUtc(),
      );
      final opened = await sync.open(relayed);
      expect(otherStore.media[opened.localPath], photo);
      expect(otherRepo.media, isEmpty); // deleted from the server once saved
    });

    test('a photo is refused when the 5 MB media allowance would be exceeded', () async {
      final c = await startWithKeys();
      repo.mediaUsed = repo.mediaLimit - 100;
      await c.sendPhoto(Uint8List(2000));
      expect(state().messages.single.delivery, DeliveryState.failed);
      expect(state().error?.code, 'media_quota');
      expect(repo.media, isEmpty);
    });
  });
}
