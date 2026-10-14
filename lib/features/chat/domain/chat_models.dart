enum MessageKind {
  text,
  image,
  system;

  static MessageKind fromValue(String? v) =>
      MessageKind.values.firstWhere((k) => k.name == v, orElse: () => MessageKind.text);
}

/// Local delivery state of a message the current user sent.
enum DeliveryState { sending, sent, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.clientId,
    required this.kind,
    required this.createdAt,
    this.body,
    this.mediaPath,
    this.delivery = DeliveryState.sent,
  });

  /// Server id. For optimistic messages this equals [clientId] until the server responds.
  final String id;
  final String conversationId;
  final String senderId;
  final String clientId;
  final MessageKind kind;
  final String? body;
  final String? mediaPath;
  final DateTime createdAt;
  final DeliveryState delivery;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        clientId: json['client_id'] as String,
        kind: MessageKind.fromValue(json['kind'] as String?),
        body: json['body'] as String?,
        mediaPath: json['media_path'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  ChatMessage copyWith({DeliveryState? delivery}) => ChatMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        clientId: clientId,
        kind: kind,
        body: body,
        mediaPath: mediaPath,
        createdAt: createdAt,
        delivery: delivery ?? this.delivery,
      );
}

/// Merges [incoming] messages into [existing] (both newest-first), replacing
/// optimistic copies by `clientId` and dropping duplicates by `id`.
/// Result is sorted newest-first.
List<ChatMessage> mergeMessages(List<ChatMessage> existing, Iterable<ChatMessage> incoming) {
  final byClientId = <String, ChatMessage>{for (final m in existing) m.clientId: m};
  for (final m in incoming) {
    final current = byClientId[m.clientId];
    // A confirmed server copy always wins over an optimistic/failed one.
    if (current == null || current.delivery != DeliveryState.sent || m.delivery == DeliveryState.sent) {
      byClientId[m.clientId] = m;
    }
  }
  final seenIds = <String>{};
  final merged = byClientId.values.where((m) => seenIds.add(m.id)).toList()
    ..sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
  return merged;
}

class ConversationSummary {
  const ConversationSummary({
    required this.matchId,
    required this.conversationId,
    required this.matchedAt,
    required this.otherUserId,
    required this.otherDisplayName,
    required this.unreadCount,
    this.otherPhoto,
    this.lastMessageBody,
    this.lastMessageKind,
    this.lastMessageSenderId,
    this.lastMessageAt,
  });

  final String matchId;
  final String conversationId;
  final DateTime matchedAt;
  final String otherUserId;
  final String otherDisplayName;
  final String? otherPhoto;
  final String? lastMessageBody;
  final MessageKind? lastMessageKind;
  final String? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final int unreadCount;

  bool get hasMessages => lastMessageAt != null;
  DateTime get sortTime => lastMessageAt ?? matchedAt;

  String previewFor(String myUserId) {
    final prefix = lastMessageSenderId == myUserId ? 'You: ' : '';
    return switch (lastMessageKind) {
      MessageKind.image => '${prefix}Sent a photo',
      MessageKind.system => lastMessageBody ?? '',
      _ => '$prefix${lastMessageBody ?? ''}',
    };
  }

  factory ConversationSummary.fromJson(Map<String, dynamic> json) => ConversationSummary(
        matchId: json['match_id'] as String,
        conversationId: json['conversation_id'] as String,
        matchedAt: DateTime.parse(json['matched_at'] as String),
        otherUserId: json['other_user_id'] as String,
        otherDisplayName: json['other_display_name'] as String,
        otherPhoto: json['other_photo'] as String?,
        lastMessageBody: json['last_message_body'] as String?,
        lastMessageKind:
            json['last_message_kind'] == null ? null : MessageKind.fromValue(json['last_message_kind'] as String),
        lastMessageSenderId: json['last_message_sender_id'] as String?,
        lastMessageAt: json['last_message_at'] == null ? null : DateTime.parse(json['last_message_at'] as String),
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      );
}
