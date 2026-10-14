import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/chat_models.dart';

abstract class ChatRepository {
  String? get currentUserId;
  Future<List<ConversationSummary>> fetchConversations({int limit = 50, int offset = 0});
  Future<List<ChatMessage>> fetchMessages(String conversationId, {DateTime? before, int limit = 30});
  Future<ChatMessage> sendMessage(String conversationId, String body, {required String clientId});
  Future<void> markRead(String conversationId);
  Future<DateTime?> fetchReadReceipt(String conversationId, String userId);

  /// New messages in one conversation, in real time.
  Stream<ChatMessage> watchMessages(String conversationId);

  /// Read-receipt updates from other members of a conversation.
  Stream<DateTime> watchReadReceipts(String conversationId, String otherUserId);

  /// Fires whenever any of my conversations or matches change.
  Stream<void> watchInbox();

  Future<void> unmatch(String matchId);
}

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._client);
  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<ConversationSummary>> fetchConversations({int limit = 50, int offset = 0}) async {
    final rows = await _client.rpc('get_my_conversations', params: {'p_limit': limit, 'p_offset': offset}) as List;
    return rows.map((r) => ConversationSummary.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId, {DateTime? before, int limit = 30}) async {
    var query = _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .isFilter('deleted_at', null);
    if (before != null) query = query.lt('created_at', before.toUtc().toIso8601String());
    final rows = await query.order('created_at', ascending: false).order('id', ascending: false).limit(limit);
    return rows.map(ChatMessage.fromJson).toList();
  }

  @override
  Future<ChatMessage> sendMessage(String conversationId, String body, {required String clientId}) async {
    final row = await _client.rpc('send_message', params: {
      'p_conversation_id': conversationId,
      'p_body': body,
      'p_client_id': clientId,
    });
    return ChatMessage.fromJson(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<void> markRead(String conversationId) =>
      _client.rpc('mark_conversation_read', params: {'p_conversation_id': conversationId});

  @override
  Future<DateTime?> fetchReadReceipt(String conversationId, String userId) async {
    final row = await _client
        .from('read_receipts')
        .select('read_at')
        .eq('conversation_id', conversationId)
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : DateTime.parse(row['read_at'] as String);
  }

  @override
  Stream<ChatMessage> watchMessages(String conversationId) {
    late final RealtimeChannel channel;
    final controller = StreamController<ChatMessage>(onCancel: () => _client.removeChannel(channel));
    channel = _client
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            if (!controller.isClosed) controller.add(ChatMessage.fromJson(payload.newRecord));
          },
        )
        .subscribe();
    return controller.stream;
  }

  @override
  Stream<DateTime> watchReadReceipts(String conversationId, String otherUserId) {
    late final RealtimeChannel channel;
    final controller = StreamController<DateTime>(onCancel: () => _client.removeChannel(channel));
    void handle(PostgresChangePayload payload) {
      final record = payload.newRecord;
      if (record['user_id'] == otherUserId && record['read_at'] != null && !controller.isClosed) {
        controller.add(DateTime.parse(record['read_at'] as String));
      }
    }

    channel = _client
        .channel('receipts:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'read_receipts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: handle,
        )
        .subscribe();
    return controller.stream;
  }

  @override
  Stream<void> watchInbox() {
    late final RealtimeChannel channel;
    final controller = StreamController<void>(onCancel: () => _client.removeChannel(channel));
    void ping(PostgresChangePayload _) {
      if (!controller.isClosed) controller.add(null);
    }

    // RLS limits these events to rows the user is allowed to see.
    channel = _client
        .channel('inbox:${currentUserId ?? 'anon'}')
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'messages', callback: ping)
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'matches', callback: ping)
        .subscribe();
    return controller.stream;
  }

  @override
  Future<void> unmatch(String matchId) => _client.rpc('unmatch', params: {'p_match_id': matchId});
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => SupabaseChatRepository(ref.watch(supabaseClientProvider)),
);
