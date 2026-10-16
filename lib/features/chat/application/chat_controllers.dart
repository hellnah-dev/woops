import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/image_processing.dart';
import '../../../core/utils/uuid.dart';
import '../data/chat_crypto.dart';
import '../data/chat_repository.dart';
import '../data/local_file.dart';
import '../data/local_chat_store.dart';
import '../domain/chat_models.dart';

// -----------------------------------------------------------------------------
// Relay sync: download waiting messages, save them on the phone, then tell the
// server to delete them. Saving happens before the ack, so nothing is lost.
// -----------------------------------------------------------------------------
class ChatSync {
  ChatSync(this._repo, this._store, this._crypto, this._myId);
  final ChatRepository _repo;
  final LocalChatStore _store;
  final ChatCrypto? _crypto;
  final String? _myId;
  Future<List<ChatMessage>>? _running;

  static const photoLabel = '📷 Photo';

  /// Turns a relayed message into what we keep on the phone: decrypted text,
  /// and for photos the decrypted image saved locally (and removed from the
  /// server). Throws if a photo couldn't be downloaded, so it isn't acked and
  /// is retried on the next sync.
  Future<ChatMessage> open(ChatMessage m) async {
    var out = m;
    if (m.encrypted && m.body != null) {
      final crypto = _crypto;
      try {
        if (crypto == null) throw StateError('no keys');
        out = out.copyWith(body: await crypto.decrypt(m.body!, conversationId: m.conversationId));
      } catch (_) {
        return m.copyWith(body: '🔒 This message couldn’t be decrypted on this phone.');
      }
    }
    if (m.kind == MessageKind.image && m.mediaPath != null) {
      final key = (jsonDecode(out.body ?? '{}') as Map)['k'] as String?;
      if (key == null || _crypto == null) return out.copyWith(body: photoLabel);
      final sealed = await _repo.downloadMedia(m.mediaPath!);
      final bytes = await _crypto.decryptBytes(sealed, key);
      final local = await _store.saveMedia(m.conversationId, '${m.clientId}.img', bytes);
      // Saved on this phone: the server copy is no longer needed.
      await _repo.deleteMedia(m.mediaPath!).catchError((_) {});
      out = out.copyWith(body: photoLabel, localPath: local);
    }
    return out;
  }

  /// Returns the newly saved messages. Concurrent calls share one run.
  Future<List<ChatMessage>> syncPending() => _running ??= _sync().whenComplete(() => _running = null);

  Future<List<ChatMessage>> _sync() async {
    final pending = await _repo.fetchPendingMessages();
    if (pending.isEmpty) return const [];
    final byConversation = <String, List<ChatMessage>>{};
    final saved = <ChatMessage>[];
    for (final m in pending) {
      try {
        final opened = await open(m);
        byConversation.putIfAbsent(m.conversationId, () => []).add(opened);
        saved.add(m);
      } catch (_) {
        // Photo download failed (offline?): leave it on the relay for next time.
      }
    }
    for (final entry in byConversation.entries) {
      await _store.upsert(entry.key, entry.value);
    }
    await _repo.ackMessages([for (final m in saved) m.id]);
    return saved;
  }

  /// Saves one message that arrived in real time and acknowledges it.
  /// Returns what was saved (decrypted), or null for my own echo.
  Future<ChatMessage?> saveIncoming(ChatMessage m) async {
    if (m.senderId == _myId) return null; // my own copy is saved when sending
    final opened = await open(m);
    await _store.upsert(m.conversationId, [opened]);
    await _repo.ackMessages([m.id]);
    return opened;
  }
}

/// This user's end-to-end encryption keys (null when signed out).
final chatCryptoProvider = Provider<ChatCrypto?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  final repo = ref.watch(chatRepositoryProvider);
  return ChatCrypto(
    vault: kIsWeb ? MemoryKeyVault() : const SecureKeyVault(),
    userId: uid,
    fetchPublicKey: repo.fetchChatKey,
  );
});

/// Publishes this phone's public key so matches can send it encrypted messages.
Future<void> publishMyChatKey(ChatCrypto? crypto, ChatRepository repo) async {
  if (crypto == null) return;
  await repo.publishChatKey(await crypto.myPublicKey());
}

final imageProcessorProvider = Provider<ImageProcessor>((ref) => ImageProcessor());

final chatSyncProvider = Provider<ChatSync>(
  (ref) => ChatSync(
    ref.watch(chatRepositoryProvider),
    ref.watch(localChatStoreProvider),
    ref.watch(chatCryptoProvider),
    ref.watch(currentUserIdProvider),
  ),
);

// -----------------------------------------------------------------------------
// Inbox: matches + conversations, refreshed in real time.
// -----------------------------------------------------------------------------
class InboxController extends AsyncNotifier<List<ConversationSummary>> {
  Timer? _debounce;
  List<ConversationSummary> _server = const [];

  @override
  Future<List<ConversationSummary>> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const [];
    final repo = ref.read(chatRepositoryProvider);
    final store = ref.watch(localChatStoreProvider);

    final sub = repo.watchInbox().listen((_) {
      // Coalesce bursts of events into a single refresh.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), refresh);
    });
    final localSub = store.changes.listen((_) => _recompute());
    ref.onDispose(() {
      sub.cancel();
      localSub.cancel();
      _debounce?.cancel();
    });

    return _load();
  }

  Future<List<ConversationSummary>> _load() async {
    final repo = ref.read(chatRepositoryProvider);
    final store = ref.read(localChatStoreProvider);
    await ref.read(chatSyncProvider).syncPending().catchError((_) => const <ChatMessage>[]);
    // Every page, so pruning below never removes a chat just past page one.
    final all = <ConversationSummary>[];
    while (true) {
      final page = await repo.fetchConversations(limit: 100, offset: all.length);
      all.addAll(page);
      if (page.length < 100) break;
    }
    _server = all;
    // Unmatched or blocked conversations disappear from the phone too.
    await store.retainOnly({for (final c in _server) c.conversationId});
    return _merge();
  }

  Future<List<ConversationSummary>> _merge() async {
    final store = ref.read(localChatStoreProvider);
    final myId = ref.read(currentUserIdProvider) ?? '';
    return [
      for (final c in _server)
        await store
            .read(c.conversationId)
            .then((local) => c.withLocal(last: local.last, unread: local.unreadFor(myId))),
    ];
  }

  Future<void> _recompute() async {
    if (!state.hasValue) return;
    state = AsyncData(await _merge());
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(_load);
    // Keep showing old data if a background refresh fails.
    if (next.hasError && state.hasValue) return;
    state = next;
  }

  /// Clears the unread badge for a conversation.
  Future<void> markLocallyRead(String conversationId) =>
      ref.read(localChatStoreProvider).markRead(conversationId, DateTime.now().toUtc());
}

final inboxProvider = AsyncNotifierProvider<InboxController, List<ConversationSummary>>(InboxController.new);

final totalUnreadProvider = Provider<int>((ref) {
  final list = ref.watch(inboxProvider).valueOrNull ?? const [];
  return list.fold(0, (sum, c) => sum + c.unreadCount);
});

// -----------------------------------------------------------------------------
// A single conversation (history comes from the phone)
// -----------------------------------------------------------------------------
typedef ChatArgs = ({String conversationId, String otherUserId});

class ChatState {
  const ChatState({
    this.messages = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
    this.otherReadAt,
  });

  /// Newest first.
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final AppException? error;
  final DateTime? otherReadAt;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    AppException? error,
    bool clearError = false,
    DateTime? otherReadAt,
  }) => ChatState(
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    otherReadAt: otherReadAt ?? this.otherReadAt,
  );
}

class ChatController extends AutoDisposeFamilyNotifier<ChatState, ChatArgs> {
  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  LocalChatStore get _store => ref.read(localChatStoreProvider);
  Timer? _readDebounce;

  @override
  ChatState build(ChatArgs arg) {
    final repo = ref.read(chatRepositoryProvider);
    final store = ref.read(localChatStoreProvider);
    final msgSub = repo.watchMessages(arg.conversationId).listen(_onIncoming);
    final receiptSub = repo.watchReadReceipts(arg.conversationId, arg.otherUserId).listen((readAt) {
      state = state.copyWith(otherReadAt: readAt);
    });
    final localSub = store.changes.where((id) => id == arg.conversationId).listen((_) => _reloadLocal());
    ref.read(chatCryptoProvider)?.forget(arg.otherUserId); // pick up a new phone's key
    ref.onDispose(() {
      msgSub.cancel();
      receiptSub.cancel();
      localSub.cancel();
      _readDebounce?.cancel();
    });
    Future.microtask(_loadInitial);
    return const ChatState();
  }

  String? get myId => _repo.currentUserId;

  Future<void> _reloadLocal() async {
    final local = await _store.read(arg.conversationId);
    // Keep in-flight optimistic bubbles that are not saved yet.
    state = state.copyWith(
      messages: mergeMessages(local.messages, state.messages.where((m) => m.delivery != DeliveryState.sent)),
    );
  }

  Future<void> _loadInitial() async {
    try {
      final local = await _store.read(arg.conversationId);
      state = state.copyWith(
        messages: mergeMessages(state.messages, local.messages),
        isLoading: false,
        clearError: true,
      );
      // Anything still waiting on the relay lands in local storage (and here).
      await ref.read(chatSyncProvider).syncPending().catchError((_) => const <ChatMessage>[]);
      final receipt = await _repo.fetchReadReceipt(arg.conversationId, arg.otherUserId);
      if (receipt != null) state = state.copyWith(otherReadAt: receipt);
      _markRead();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: AppException.from(e));
    }
  }

  Future<void> retryInitial() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _loadInitial();
  }

  /// History is fully local, so there is nothing more to page in.
  Future<void> loadMore() async {}

  Future<void> _onIncoming(ChatMessage message) async {
    if (message.senderId == myId) return; // my own echo: already saved when sent
    try {
      final opened = await ref.read(chatSyncProvider).saveIncoming(message);
      if (opened != null) state = state.copyWith(messages: mergeMessages(state.messages, [opened]));
    } catch (_) {
      // Stays on the relay; the next sync saves it.
    }
    _markRead();
  }

  void _markRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        await ref.read(inboxProvider.notifier).markLocallyRead(arg.conversationId);
        await _repo.markRead(arg.conversationId);
      } catch (_) {
        // Non-critical: only affects the other person's read receipt.
      }
    });
  }

  /// Sends a text message with an optimistic bubble. Retrying a failed message
  /// reuses its client id, so the other phone never shows it twice.
  Future<void> send(String text, {String? clientId}) async {
    final body = text.trim();
    final me = myId;
    if (body.isEmpty || me == null) return;
    final id = clientId ?? uuidV4();

    final optimistic = ChatMessage(
      id: id,
      conversationId: arg.conversationId,
      senderId: me,
      clientId: id,
      kind: MessageKind.text,
      body: body,
      createdAt: DateTime.now().toUtc(),
      delivery: DeliveryState.sending,
    );
    state = state.copyWith(
      messages: mergeMessages(state.messages.where((m) => m.clientId != id).toList(), [optimistic]),
      clearError: true,
    );

    try {
      // End-to-end encrypted whenever the other phone has published a key.
      final crypto = ref.read(chatCryptoProvider);
      final e2e = crypto != null && await crypto.canEncryptTo(arg.otherUserId).catchError((_) => false);
      final wire = e2e
          ? await crypto.encrypt(body, conversationId: arg.conversationId, otherUserId: arg.otherUserId)
          : body;
      final sent = await _repo.sendMessage(arg.conversationId, wire, clientId: id, encrypted: e2e);
      final saved = sent.copyWith(body: body, encrypted: e2e); // keep the readable copy locally
      state = state.copyWith(messages: mergeMessages(state.messages, [saved]));
      await _store.upsert(arg.conversationId, [saved]);
    } catch (e) {
      final failed = optimistic.copyWith(delivery: DeliveryState.failed);
      state = state.copyWith(
        messages: [for (final m in state.messages) m.clientId == id && m.delivery != DeliveryState.sent ? failed : m],
        error: AppException.from(e),
      );
      await _store.upsert(arg.conversationId, [failed]).catchError((_) => const LocalConversation());
    }
  }

  Future<void> retry(ChatMessage failed) => failed.kind == MessageKind.image && failed.localPath != null
      ? _sendPhoto(failed.localPath!, clientId: failed.clientId)
      : send(failed.body ?? '', clientId: failed.clientId);

  /// Sends a photo like WhatsApp: compressed and encrypted on the phone, kept
  /// on the phone, and only relayed (encrypted) until the other phone saves it.
  Future<void> sendPhoto(Uint8List original) async {
    final me = myId;
    if (me == null) return;
    final id = uuidV4();
    final processed = await ref.read(imageProcessorProvider).processProfilePhoto(original);
    final local = await _store.saveMedia(arg.conversationId, '$id.img', processed.full);
    await _sendPhoto(local, clientId: id, bytes: processed.full);
  }

  Future<void> _sendPhoto(String localPath, {required String clientId, Uint8List? bytes}) async {
    final me = myId!;
    final optimistic = ChatMessage(
      id: clientId,
      conversationId: arg.conversationId,
      senderId: me,
      clientId: clientId,
      kind: MessageKind.image,
      body: ChatSync.photoLabel,
      createdAt: DateTime.now().toUtc(),
      delivery: DeliveryState.sending,
      encrypted: true,
      localPath: localPath,
    );
    state = state.copyWith(
      messages: mergeMessages(state.messages.where((m) => m.clientId != clientId).toList(), [optimistic]),
      clearError: true,
    );
    try {
      final crypto = ref.read(chatCryptoProvider);
      if (crypto == null || !await crypto.canEncryptTo(arg.otherUserId)) {
        throw const AppException('Ask your match to update Woops to receive photos.', code: 'no_chat_key');
      }
      final data = bytes ?? await readLocalFile(localPath);
      final sealed = await crypto.encryptBytes(data);
      final usage = await _repo.mediaUsage();
      if (usage.used + sealed.bytes.length > usage.limit) {
        throw const AppException(
          'You’ve used your 5 MB of media. Wait until your matches receive your photos, or remove a profile photo.',
          code: 'media_quota',
        );
      }
      final path = '$me/${arg.conversationId}/$clientId.bin';
      try {
        await _repo.uploadMedia(path, sealed.bytes);
      } catch (e) {
        // A retry after a successful upload: the file is already there.
        if (!'$e'.toLowerCase().contains('exists')) rethrow;
      }
      final envelope = await crypto.encrypt(
        jsonEncode({'k': sealed.key}),
        conversationId: arg.conversationId,
        otherUserId: arg.otherUserId,
      );
      final sent = await _repo.sendMessage(
        arg.conversationId,
        envelope,
        clientId: clientId,
        kind: MessageKind.image,
        mediaPath: path,
        encrypted: true,
      );
      final saved = sent.copyWith(body: ChatSync.photoLabel, localPath: localPath, encrypted: true);
      state = state.copyWith(messages: mergeMessages(state.messages, [saved]));
      await _store.upsert(arg.conversationId, [saved]);
    } catch (e) {
      final failed = optimistic.copyWith(delivery: DeliveryState.failed);
      state = state.copyWith(
        messages: [
          for (final m in state.messages) m.clientId == clientId && m.delivery != DeliveryState.sent ? failed : m,
        ],
        error: AppException.from(e),
      );
      await _store.upsert(arg.conversationId, [failed]).catchError((_) => const LocalConversation());
    }
  }

  Future<void> discardFailed(ChatMessage failed) async {
    state = state.copyWith(messages: state.messages.where((m) => m.clientId != failed.clientId).toList());
    await _store.removeMessage(arg.conversationId, failed.clientId);
  }
}

final chatControllerProvider = NotifierProvider.autoDispose.family<ChatController, ChatState, ChatArgs>(
  ChatController.new,
);
