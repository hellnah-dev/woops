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
import '../data/media_compressor.dart';
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
  static const videoLabel = '🎥 Video';
  static String labelFor(MessageKind kind) => kind == MessageKind.video ? videoLabel : photoLabel;

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
    if (m.kind.isMedia && m.mediaPath != null) {
      final label = labelFor(m.kind);
      final envelope = jsonDecode(out.body ?? '{}') as Map;
      final key = envelope['k'] as String?;
      if (key == null || _crypto == null) return out.copyWith(body: label);
      final sealed = await _repo.downloadMedia(m.mediaPath!);
      final bytes = await _crypto.decryptBytes(sealed, key);
      final ext = m.kind == MessageKind.video ? 'mp4' : 'img';
      // Kept on this phone only until it is viewed once (see markViewed).
      final local = await _store.saveMedia(m.conversationId, '${m.clientId}.$ext', bytes);
      // Saved on this phone: the server copy is no longer needed.
      await _repo.deleteMedia(m.mediaPath!).catchError((_) {});
      out = out.copyWith(body: label, localPath: local, viewOnce: envelope['once'] == true);
    }
    return out;
  }

  /// Returns the newly saved messages. Concurrent calls share one run.
  Future<List<ChatMessage>> syncPending() => _running ??= _sync().whenComplete(() => _running = null);

  Future<List<ChatMessage>> _sync() async {
    final pending = await _repo.fetchPendingMessages();
    if (pending.isEmpty) return const [];
    final byConversation = <String, List<ChatMessage>>{};
    final reactions = <ChatMessage>[];
    final saved = <ChatMessage>[];
    for (final m in pending) {
      try {
        final opened = await open(m);
        if (m.kind == MessageKind.reaction) {
          reactions.add(opened);
        } else {
          byConversation.putIfAbsent(m.conversationId, () => []).add(opened);
        }
        saved.add(m);
      } catch (_) {
        // Photo download failed (offline?): leave it on the relay for next time.
      }
    }
    for (final entry in byConversation.entries) {
      await _store.upsert(entry.key, entry.value);
    }
    // After the messages, so a reaction finds a message that arrived with it.
    for (final r in reactions) {
      await applyReaction(r);
    }
    await _repo.ackMessages([for (final m in saved) m.id]);
    return saved;
  }

  /// Attaches a (decrypted) reaction to the message it is for, on this phone.
  /// Returns the updated message, or null if that message isn't here any more.
  Future<ChatMessage?> applyReaction(ChatMessage reaction) async {
    final payload = ReactionPayload.tryParse(reaction.body);
    if (payload == null) return null;
    // One locked step: never overwrites a reaction saved at the same moment.
    return _store.updateMessage(
      reaction.conversationId,
      payload.targetClientId,
      (m) => m.withReaction(reaction.senderId, payload.emoji),
    );
  }

  /// Saves one message that arrived in real time and acknowledges it.
  /// Returns what was saved (decrypted), or null for my own echo.
  Future<ChatMessage?> saveIncoming(ChatMessage m) async {
    if (m.senderId == _myId) return null; // my own copy is saved when sending
    final opened = await open(m);
    if (m.kind == MessageKind.reaction) {
      final updated = await applyReaction(opened);
      await _repo.ackMessages([m.id]);
      return updated;
    }
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
    this.otherTyping = false,
  });

  /// Newest first.
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final AppException? error;
  final DateTime? otherReadAt;

  /// The other person is typing right now.
  final bool otherTyping;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    AppException? error,
    bool clearError = false,
    DateTime? otherReadAt,
    bool? otherTyping,
  }) => ChatState(
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    otherReadAt: otherReadAt ?? this.otherReadAt,
    otherTyping: otherTyping ?? this.otherTyping,
  );
}

class ChatController extends AutoDisposeFamilyNotifier<ChatState, ChatArgs> {
  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  LocalChatStore get _store => ref.read(localChatStoreProvider);
  Timer? _readDebounce;
  late TypingChannel _typing;
  Timer? _otherTypingTimeout;
  Timer? _myTypingStop;
  DateTime? _myTypingSentAt;

  /// A "typing" signal older than this is treated as stopped (e.g. the other
  /// phone lost its connection mid-sentence).
  static const typingTimeout = Duration(seconds: 6);

  @override
  ChatState build(ChatArgs arg) {
    final repo = ref.read(chatRepositoryProvider);
    final store = ref.read(localChatStoreProvider);
    final msgSub = repo.watchMessages(arg.conversationId).listen(_onIncoming);
    final receiptSub = repo.watchReadReceipts(arg.conversationId, arg.otherUserId).listen((readAt) {
      state = state.copyWith(otherReadAt: readAt);
    });
    final localSub = store.changes.where((id) => id == arg.conversationId).listen((_) => _reloadLocal());
    _typing = repo.typingChannel(arg.conversationId);
    final typingSub = _typing.otherTyping.listen(_onOtherTyping);
    ref.read(chatCryptoProvider)?.forget(arg.otherUserId); // pick up a new phone's key
    ref.onDispose(() {
      msgSub.cancel();
      receiptSub.cancel();
      localSub.cancel();
      typingSub.cancel();
      _readDebounce?.cancel();
      _otherTypingTimeout?.cancel();
      _myTypingStop?.cancel();
      // Let "stopped typing" go out before the channel closes.
      final typing = _typing;
      (_myTypingSentAt != null ? typing.send(false) : Future<void>.value()).whenComplete(typing.close);
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

  void _onOtherTyping(bool typing) {
    _otherTypingTimeout?.cancel();
    if (typing) _otherTypingTimeout = Timer(typingTimeout, () => _onOtherTyping(false));
    if (state.otherTyping != typing) state = state.copyWith(otherTyping: typing);
  }

  /// Call as I type. Sends "typing" at most every 3 s, and "stopped" after a
  /// short pause or when the box is cleared.
  void setTyping(bool active) {
    _myTypingStop?.cancel();
    if (!active) {
      if (_myTypingSentAt != null) _typing.send(false);
      _myTypingSentAt = null;
      return;
    }
    final now = DateTime.now();
    if (_myTypingSentAt == null || now.difference(_myTypingSentAt!) > const Duration(seconds: 3)) {
      _myTypingSentAt = now;
      _typing.send(true);
    }
    _myTypingStop = Timer(const Duration(seconds: 4), () => setTyping(false));
  }

  Future<void> _onIncoming(ChatMessage message) async {
    if (message.senderId == myId) return; // my own echo: already saved when sent
    if (message.kind != MessageKind.reaction) _onOtherTyping(false);
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
  Future<void> send(String text, {String? clientId, MessageKind kind = MessageKind.text}) async {
    final body = text.trim();
    final me = myId;
    if (body.isEmpty || me == null) return;
    final id = clientId ?? uuidV4();
    setTyping(false);

    final optimistic = ChatMessage(
      id: id,
      conversationId: arg.conversationId,
      senderId: me,
      clientId: id,
      kind: kind,
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
      final sent = await _repo.sendMessage(arg.conversationId, wire, clientId: id, kind: kind, encrypted: e2e);
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

  Future<void> retry(ChatMessage failed) => failed.kind.isMedia && failed.localPath != null
      ? _sendMedia(failed.localPath!, kind: failed.kind, clientId: failed.clientId)
      : send(failed.body ?? '', clientId: failed.clientId, kind: failed.kind);

  /// Sends a GIF (its GIPHY link, end-to-end encrypted like text).
  Future<void> sendGif(GifPayload gif) => send(gif.encode(), kind: MessageKind.gif);

  /// Convenience for a single photo.
  Future<void> sendPhoto(Uint8List original) => sendMedia([OutgoingMedia.image(original)]);

  /// Sends photos and videos like WhatsApp's view-once: compressed and
  /// encrypted on this phone, relayed (encrypted) only until the other phone
  /// saves it, viewable once there, and not kept on this phone after sending.
  /// Several items are sent one after another, in order.
  Future<void> sendMedia(List<OutgoingMedia> items) async {
    final me = myId;
    if (me == null) return;
    final compressor = ref.read(mediaCompressorProvider);
    for (final item in items) {
      final id = uuidV4();
      try {
        final bytes = item.kind == MessageKind.video
            ? await compressor.video(item.path!)
            : await compressor.image(item.bytes ?? await readLocalFile(item.path!));
        final ext = item.kind == MessageKind.video ? 'mp4' : 'img';
        // Kept only while sending (for retries); deleted once it's sent.
        final local = await _store.saveMedia(arg.conversationId, '$id.$ext', bytes);
        await _sendMedia(local, kind: item.kind, clientId: id, bytes: bytes);
      } catch (e) {
        state = state.copyWith(error: AppException.from(e));
      }
    }
  }

  Future<void> _sendMedia(
    String localPath, {
    required MessageKind kind,
    required String clientId,
    Uint8List? bytes,
  }) async {
    final me = myId!;
    final label = ChatSync.labelFor(kind);
    final optimistic = ChatMessage(
      id: clientId,
      conversationId: arg.conversationId,
      senderId: me,
      clientId: clientId,
      kind: kind,
      body: label,
      createdAt: DateTime.now().toUtc(),
      delivery: DeliveryState.sending,
      encrypted: true,
      localPath: localPath,
      viewOnce: true,
    );
    state = state.copyWith(
      messages: mergeMessages(state.messages.where((m) => m.clientId != clientId).toList(), [optimistic]),
      clearError: true,
    );
    try {
      final crypto = ref.read(chatCryptoProvider);
      if (crypto == null || !await crypto.canEncryptTo(arg.otherUserId)) {
        throw const AppException('Ask your match to update Woops to receive photos and videos.', code: 'no_chat_key');
      }
      final data = bytes ?? await readLocalFile(localPath);
      final sealed = await crypto.encryptBytes(data);
      final usage = await _repo.mediaUsage();
      if (usage.used + sealed.bytes.length > usage.limit) {
        throw const AppException(
          'You’ve used your 3 MB of media. Wait until your matches open what you sent, or remove a profile photo.',
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
        jsonEncode({'k': sealed.key, 'once': true}),
        conversationId: arg.conversationId,
        otherUserId: arg.otherUserId,
      );
      final sent = await _repo.sendMessage(
        arg.conversationId,
        envelope,
        clientId: clientId,
        kind: kind,
        mediaPath: path,
        encrypted: true,
      );
      // View-once: the sender doesn't keep a copy either.
      await _store.deleteMedia(localPath).catchError((_) {});
      final saved = sent.copyWith(body: label, clearLocalPath: true, encrypted: true, viewed: true, viewOnce: true);
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

  /// View-once: called when the viewer closes. The file is deleted from this
  /// phone and the message can't be opened again.
  Future<void> markViewed(ChatMessage m) async {
    // Photos from before view-once stay on the phone.
    if (!m.kind.isMedia || m.viewed || !m.viewOnce) return;
    if (m.localPath != null) await _store.deleteMedia(m.localPath!).catchError((_) {});
    final done = m.copyWith(viewed: true, clearLocalPath: true);
    state = state.copyWith(messages: [for (final x in state.messages) x.clientId == m.clientId ? done : x]);
    await _store.upsert(arg.conversationId, [done]);
  }

  /// Reacts to a message like Instagram: the same emoji again removes it.
  /// Shown at once; undone if it can't be sent.
  Future<void> react(ChatMessage target, String emoji) async {
    final me = myId;
    if (me == null || target.delivery != DeliveryState.sent || target.kind == MessageKind.system) return;
    // A stale error from earlier must not make this reaction look failed.
    state = state.copyWith(clearError: true);
    final previous = target.reactions[me];
    final next = previous == emoji ? '' : emoji;
    // Change only my reaction, on the stored copy, so one that just arrived
    // from the other person is kept.
    final updated =
        await _store
            .updateMessage(arg.conversationId, target.clientId, (m) => m.withReaction(me, next))
            .catchError((_) => null) ??
        target.withReaction(me, next);
    _replace(updated);
    try {
      final payload = ReactionPayload(target.clientId, next).encode();
      // Encrypted when possible. Removing one says nothing worth hiding.
      final crypto = ref.read(chatCryptoProvider);
      final e2e =
          next.isNotEmpty && crypto != null && await crypto.canEncryptTo(arg.otherUserId).catchError((_) => false);
      final wire = e2e
          ? await crypto.encrypt(payload, conversationId: arg.conversationId, otherUserId: arg.otherUserId)
          : payload;
      await _repo.sendMessage(arg.conversationId, wire, clientId: uuidV4(), kind: MessageKind.reaction, encrypted: e2e);
    } catch (e) {
      final reverted =
          await _store
              .updateMessage(arg.conversationId, target.clientId, (m) => m.withReaction(me, previous ?? ''))
              .catchError((_) => null) ??
          updated.withReaction(me, previous ?? '');
      _replace(reverted);
      state = state.copyWith(error: AppException.from(e));
    }
  }

  void _replace(ChatMessage m) =>
      state = state.copyWith(messages: [for (final x in state.messages) x.clientId == m.clientId ? m : x]);

  Future<void> discardFailed(ChatMessage failed) async {
    state = state.copyWith(messages: state.messages.where((m) => m.clientId != failed.clientId).toList());
    await _store.removeMessage(arg.conversationId, failed.clientId);
    // An unsent photo/video was kept only for retrying.
    if (failed.kind.isMedia && failed.localPath != null) {
      await _store.deleteMedia(failed.localPath!).catchError((_) {});
    }
  }
}

/// A photo or video picked to send. Photos may come as bytes or a path.
class OutgoingMedia {
  const OutgoingMedia._(this.kind, {this.bytes, this.path});
  factory OutgoingMedia.image(Uint8List bytes) => OutgoingMedia._(MessageKind.image, bytes: bytes);
  factory OutgoingMedia.imageFile(String path) => OutgoingMedia._(MessageKind.image, path: path);
  factory OutgoingMedia.video(String path) => OutgoingMedia._(MessageKind.video, path: path);
  final MessageKind kind;
  final Uint8List? bytes;
  final String? path;
}

final chatControllerProvider = NotifierProvider.autoDispose.family<ChatController, ChatState, ChatArgs>(
  ChatController.new,
);
