import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/uuid.dart';
import '../data/chat_repository.dart';
import '../domain/chat_models.dart';

// -----------------------------------------------------------------------------
// Inbox: matches + conversations, refreshed in real time.
// -----------------------------------------------------------------------------
class InboxController extends AsyncNotifier<List<ConversationSummary>> {
  Timer? _debounce;

  @override
  Future<List<ConversationSummary>> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const [];
    final repo = ref.read(chatRepositoryProvider);

    final sub = repo.watchInbox().listen((_) {
      // Coalesce bursts of events into a single refresh.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), refresh);
    });
    ref.onDispose(() {
      sub.cancel();
      _debounce?.cancel();
    });

    return repo.fetchConversations();
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(() => ref.read(chatRepositoryProvider).fetchConversations());
    // Keep showing old data if a background refresh fails.
    if (next.hasError && state.hasValue) return;
    state = next;
  }

  /// Optimistically clears the unread badge for a conversation.
  void markLocallyRead(String conversationId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final c in current)
        c.conversationId == conversationId
            ? ConversationSummary(
                matchId: c.matchId,
                conversationId: c.conversationId,
                matchedAt: c.matchedAt,
                otherUserId: c.otherUserId,
                otherDisplayName: c.otherDisplayName,
                otherPhoto: c.otherPhoto,
                lastMessageBody: c.lastMessageBody,
                lastMessageKind: c.lastMessageKind,
                lastMessageSenderId: c.lastMessageSenderId,
                lastMessageAt: c.lastMessageAt,
                unreadCount: 0,
              )
            : c,
    ]);
  }
}

final inboxProvider = AsyncNotifierProvider<InboxController, List<ConversationSummary>>(InboxController.new);

final totalUnreadProvider = Provider<int>((ref) {
  final list = ref.watch(inboxProvider).valueOrNull ?? const [];
  return list.fold(0, (sum, c) => sum + c.unreadCount);
});

// -----------------------------------------------------------------------------
// A single conversation
// -----------------------------------------------------------------------------
typedef ChatArgs = ({String conversationId, String otherUserId});

class ChatState {
  const ChatState({
    this.messages = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
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
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
        otherReadAt: otherReadAt ?? this.otherReadAt,
      );
}

class ChatController extends AutoDisposeFamilyNotifier<ChatState, ChatArgs> {
  static const pageSize = 30;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  Timer? _readDebounce;

  @override
  ChatState build(ChatArgs arg) {
    final repo = ref.read(chatRepositoryProvider);
    final msgSub = repo.watchMessages(arg.conversationId).listen(_onIncoming);
    final receiptSub = repo.watchReadReceipts(arg.conversationId, arg.otherUserId).listen((readAt) {
      state = state.copyWith(otherReadAt: readAt);
    });
    ref.onDispose(() {
      msgSub.cancel();
      receiptSub.cancel();
      _readDebounce?.cancel();
    });
    Future.microtask(_loadInitial);
    return const ChatState();
  }

  String? get myId => _repo.currentUserId;

  Future<void> _loadInitial() async {
    try {
      final results = await Future.wait([
        _repo.fetchMessages(arg.conversationId, limit: pageSize),
        _repo.fetchReadReceipt(arg.conversationId, arg.otherUserId),
      ]);
      final page = results[0] as List<ChatMessage>;
      state = state.copyWith(
        messages: mergeMessages(state.messages, page),
        isLoading: false,
        hasMore: page.length == pageSize,
        otherReadAt: results[1] as DateTime?,
        clearError: true,
      );
      _markRead();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: AppException.from(e));
    }
  }

  Future<void> retryInitial() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _loadInitial();
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    final oldest = state.messages.where((m) => m.delivery == DeliveryState.sent).lastOrNull;
    if (oldest == null) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.fetchMessages(arg.conversationId, before: oldest.createdAt, limit: pageSize);
      state = state.copyWith(
        messages: mergeMessages(state.messages, page),
        isLoadingMore: false,
        hasMore: page.length == pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: AppException.from(e));
    }
  }

  void _onIncoming(ChatMessage message) {
    state = state.copyWith(messages: mergeMessages(state.messages, [message]));
    if (message.senderId != myId) _markRead();
  }

  void _markRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _repo.markRead(arg.conversationId);
        ref.read(inboxProvider.notifier).markLocallyRead(arg.conversationId);
      } catch (_) {
        // Non-critical; the unread count will correct itself on next refresh.
      }
    });
  }

  /// Sends a text message with an optimistic bubble. Retrying a failed message
  /// reuses its client id, so the server never stores it twice.
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
      final saved = await _repo.sendMessage(arg.conversationId, body, clientId: id);
      state = state.copyWith(messages: mergeMessages(state.messages, [saved]));
    } catch (e) {
      state = state.copyWith(
        messages: [
          for (final m in state.messages) m.clientId == id && m.delivery != DeliveryState.sent ? m.copyWith(delivery: DeliveryState.failed) : m,
        ],
        error: AppException.from(e),
      );
    }
  }

  Future<void> retry(ChatMessage failed) => send(failed.body ?? '', clientId: failed.clientId);

  void discardFailed(ChatMessage failed) {
    state = state.copyWith(messages: state.messages.where((m) => m.clientId != failed.clientId).toList());
  }
}

final chatControllerProvider =
    NotifierProvider.autoDispose.family<ChatController, ChatState, ChatArgs>(ChatController.new);
