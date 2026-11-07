import 'dart:typed_data';

import 'package:woops/core/supabase/supabase_providers.dart';
import 'package:woops/core/utils/image_processing.dart';
import 'package:woops/features/chat/application/chat_controllers.dart';
import 'package:woops/features/chat/data/chat_crypto.dart';
import 'package:woops/features/chat/data/chat_repository.dart';
import 'package:woops/core/utils/app_exception.dart';
import 'package:woops/features/chat/data/local_chat_store.dart';
import 'package:woops/features/chat/data/media_compressor.dart';
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
        mediaCompressorProvider.overrideWithValue(_FakeCompressor()),
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

  test('typing: the other person\'s "typing" shows and clears when their message arrives', () async {
    repo = FakeChatRepository();
    await start();
    repo.typing.other.add(true);
    await pumpEventQueue();
    expect(state().otherTyping, isTrue);
    repo.incoming.add(msg('x1', at: DateTime.now().toUtc()));
    await pumpEventQueue();
    expect(state().otherTyping, isFalse);
  });

  test('typing: I send "typing" once while typing fast, and "stopped" when I send', () async {
    repo = FakeChatRepository();
    final c = await start();
    c.setTyping(true);
    c.setTyping(true);
    c.setTyping(true);
    expect(repo.typing.sent, [true]);
    await c.send('hi');
    expect(repo.typing.sent, [true, false]);
    container.dispose();
    // The channel closes once the last "stopped typing" has gone out.
    await pumpEventQueue();
    expect(repo.typing.closed, isTrue);
  });

  test('chat search finds text saved on the phone, newest match per chat, any letter case', () async {
    final t = DateTime.utc(2026, 10, 21);
    await store.upsert('c1', [
      msg('1', at: t).copyWith(body: 'see you at the Cafe'),
      msg('2', at: t.add(const Duration(minutes: 1))).copyWith(body: 'cafe was great'),
    ]);
    await store.upsert('c2', [msg('3', at: t).copyWith(body: 'nothing here')]);
    final hits = await store.search(['c1', 'c2'], 'CAFE');
    expect(hits.keys, ['c1']);
    expect(hits['c1']!.body, 'cafe was great');
    expect(await store.search(['c1', 'c2'], '   '), isEmpty);
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
          mediaCompressorProvider.overrideWithValue(_FakeCompressor()),
          mediaCompressorProvider.overrideWithValue(_FakeCompressor()),
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

    test('reactions: shown at once, saved on the phone, sent encrypted; the same emoji again removes it', () async {
      final c = await startWithKeys();
      final target = msg('t1', at: DateTime.utc(2026, 10, 14));
      await store.upsert('c1', [target]);
      await pumpEventQueue();
      await c.react(state().messages.single, '❤️');
      expect(state().messages.single.reactions, {'me': '❤️'});
      expect((await store.read('c1')).messages.single.reactions, {'me': '❤️'});
      expect(repo.sentKinds, [MessageKind.reaction]);
      expect(repo.sentEncrypted, [true]);
      final wire = await theirCrypto.decrypt(repo.sentBodies.single, conversationId: 'c1');
      expect(ReactionPayload.tryParse(wire)!.targetClientId, target.clientId);
      // A reaction is not a message: the chat still has just the one.
      expect((await store.read('c1')).messages, hasLength(1));

      await c.react(state().messages.single, '❤️');
      expect(state().messages.single.reactions, isEmpty);
      expect(repo.sentEncrypted.last, isFalse, reason: 'removing names only a random id');
      expect(ReactionPayload.tryParse(repo.sentBodies.last)!.emoji, '');
    });

    test('an incoming reaction attaches to its message and is acknowledged', () async {
      await startWithKeys();
      final target = msg('t1', sender: 'me', at: DateTime.utc(2026, 10, 14));
      await store.upsert('c1', [target]);
      await pumpEventQueue();
      final sealed = await theirCrypto.encrypt(
        ReactionPayload(target.clientId, '😂').encode(),
        conversationId: 'c1',
        otherUserId: 'me',
      );
      repo.incoming.add(
        ChatMessage(
          id: 'r1',
          conversationId: 'c1',
          senderId: 'other',
          clientId: 'r1',
          kind: MessageKind.reaction,
          body: sealed,
          encrypted: true,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await pumpEventQueue();
      expect(state().messages.single.reactions, {'other': '😂'});
      expect((await store.read('c1')).messages.single.reactions, {'other': '😂'});
      expect(repo.ackedIds, ['r1']);
    });

    test('a reaction waiting on the relay finds a message that arrived in the same batch', () async {
      repo = FakeChatRepository();
      await withKeys();
      final m = msg('m1', at: DateTime.utc(2026, 10, 14));
      repo.pending = [
        m,
        ChatMessage(
          id: 'r1',
          conversationId: 'c1',
          senderId: 'other',
          clientId: 'r1',
          kind: MessageKind.reaction,
          body: ReactionPayload(m.clientId, '👍').encode(),
          createdAt: DateTime.utc(2026, 10, 14, 0, 1),
        ),
      ];
      final sync = ChatSync(repo, store, myCrypto, 'me');
      await sync.syncPending();
      final saved = (await store.read('c1')).messages;
      expect(saved.map((x) => x.id), ['m1']);
      expect(saved.single.reactions, {'other': '👍'});
      expect(repo.ackedIds, ['m1', 'r1']);
    });

    test('a reaction that can’t be sent is taken back', () async {
      final c = await startWithKeys();
      await store.upsert('c1', [msg('t1', at: DateTime.utc(2026, 10, 14))]);
      await pumpEventQueue();
      repo.failNextSends = 1;
      await c.react(state().messages.single, '😮');
      expect(state().messages.single.reactions, isEmpty);
      expect((await store.read('c1')).messages.single.reactions, isEmpty);
      expect(state().error, isNotNull);
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
      // View-once: the sender keeps no copy once it's sent.
      expect(mine.localPath, isNull);
      expect(store.media, isEmpty);

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
      expect(opened.viewed, isFalse);
    });

    test('view once: after the receiver views it, the file is gone and it can’t be opened again', () async {
      final c = await startWithKeys();
      final local = await store.saveMedia('c1', 'x.img', Uint8List.fromList([1, 2, 3]));
      final m = ChatMessage(
        id: 'm9',
        conversationId: 'c1',
        senderId: 'other',
        clientId: 'm9',
        kind: MessageKind.image,
        body: '📷 Photo',
        createdAt: DateTime.now().toUtc(),
        localPath: local,
        viewOnce: true,
      );
      await store.upsert('c1', [m]);
      await pumpEventQueue();
      await c.markViewed(state().messages.single);
      expect(store.media, isEmpty);
      final saved = (await store.read('c1')).messages.single;
      expect(saved.viewed, isTrue);
      expect(saved.localPath, isNull);
    });

    test('photos from before view-once stay on the phone after viewing', () async {
      final c = await startWithKeys();
      final local = await store.saveMedia('c1', 'old.img', Uint8List.fromList([4, 5, 6]));
      await store.upsert('c1', [
        ChatMessage(
          id: 'm8',
          conversationId: 'c1',
          senderId: 'other',
          clientId: 'm8',
          kind: MessageKind.image,
          body: '📷 Photo',
          createdAt: DateTime.now().toUtc(),
          localPath: local,
        ),
      ]);
      await pumpEventQueue();
      await c.markViewed(state().messages.single);
      expect(store.media, isNotEmpty);
      expect((await store.read('c1')).messages.single.localPath, local);
    });

    test('several photos and a video are compressed and sent in order', () async {
      final c = await startWithKeys();
      await c.sendMedia([
        OutgoingMedia.image(Uint8List(3000)),
        OutgoingMedia.image(Uint8List(2000)),
        OutgoingMedia.video('/tmp/clip.mp4'),
      ]);
      expect(repo.sentClientIds, hasLength(3));
      expect(state().messages.map((m) => m.kind).toList().reversed, [
        MessageKind.image,
        MessageKind.image,
        MessageKind.video,
      ]);
      expect(state().messages.every((m) => m.delivery == DeliveryState.sent && m.viewed), isTrue);
      expect(repo.media, hasLength(3)); // three encrypted files on the relay
      expect(store.media, isEmpty); // nothing kept on the sender's phone
    });

    test('a video that is still too big after compressing is refused with a clear message', () async {
      final c = await startWithKeys();
      await c.sendMedia([OutgoingMedia.video('/tmp/too-big.mp4')]);
      expect(state().error?.code, 'media_too_large');
      expect(repo.media, isEmpty);
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

/// Stands in for the phone's photo/video compression in tests.
class _FakeCompressor implements MediaCompressor {
  @override
  Future<Uint8List> image(Uint8List original) async => original;

  @override
  Future<Uint8List> video(String path) async {
    if (path.contains('too-big')) {
      throw const AppException('This video is still too big.', code: 'media_too_large');
    }
    return Uint8List.fromList(List.generate(4000, (i) => i % 256));
  }
}
