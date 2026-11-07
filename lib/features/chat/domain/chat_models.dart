import 'dart:convert';

enum MessageKind {
  text,
  image,
  video,

  /// A GIF from GIPHY: the body is a small JSON with its link and size.
  gif,

  /// A reaction to another message. Relayed, then attached to that message on
  /// the phone; never shown as a message of its own.
  reaction,
  system;

  /// Photos and videos: always view-once.
  bool get isMedia => this == image || this == video;

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
    this.encrypted = false,
    this.localPath,
    this.viewed = false,
    this.viewOnce = false,
    this.reactions = const {},
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

  /// Sent end-to-end encrypted (the server only saw ciphertext).
  final bool encrypted;

  /// Photo/video saved on this phone (until it is viewed, for view-once media).
  final String? localPath;

  /// View-once media: true once opened (received) or sent. The file is gone.
  final bool viewed;

  /// Sent as view once (every photo/video since view-once was added). Older
  /// photos stay on the phone and can be opened any number of times.
  final bool viewOnce;

  /// Who reacted with what (user id → emoji), stored on the phone only.
  final Map<String, String> reactions;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    conversationId: json['conversation_id'] as String,
    senderId: json['sender_id'] as String,
    clientId: json['client_id'] as String,
    kind: MessageKind.fromValue(json['kind'] as String?),
    body: json['body'] as String?,
    mediaPath: json['media_path'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    encrypted: (json['metadata'] as Map?)?['e2e'] == true || json['encrypted'] == true,
    localPath: json['local_path'] as String?,
    viewed: json['viewed'] == true,
    viewOnce: json['view_once'] == true,
    reactions: json['reactions'] is Map ? Map<String, String>.from(json['reactions'] as Map) : const {},
  );

  /// Saved on the phone. A message still "sending" when the app closed is
  /// restored as "failed" so it can be retried.
  factory ChatMessage.fromLocalJson(Map<String, dynamic> json) {
    final delivery = DeliveryState.values.firstWhere(
      (d) => d.name == json['delivery'],
      orElse: () => DeliveryState.sent,
    );
    return ChatMessage.fromJson(
      json,
    ).copyWith(delivery: delivery == DeliveryState.sending ? DeliveryState.failed : delivery);
  }

  Map<String, dynamic> toLocalJson() => {
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'client_id': clientId,
    'kind': kind.name,
    'body': body,
    'media_path': mediaPath,
    'created_at': createdAt.toUtc().toIso8601String(),
    'delivery': delivery.name,
    'encrypted': encrypted,
    'local_path': localPath,
    'viewed': viewed,
    if (viewOnce) 'view_once': true,
    if (reactions.isNotEmpty) 'reactions': reactions,
  };

  ChatMessage copyWith({
    DeliveryState? delivery,
    String? body,
    String? localPath,
    bool clearLocalPath = false,
    bool? encrypted,
    bool? viewed,
    bool? viewOnce,
    Map<String, String>? reactions,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    clientId: clientId,
    kind: kind,
    body: body ?? this.body,
    mediaPath: mediaPath,
    createdAt: createdAt,
    delivery: delivery ?? this.delivery,
    encrypted: encrypted ?? this.encrypted,
    localPath: clearLocalPath ? null : (localPath ?? this.localPath),
    viewed: viewed ?? this.viewed,
    viewOnce: viewOnce ?? this.viewOnce,
    reactions: reactions ?? this.reactions,
  );

  /// This message with [userId]'s reaction set to [emoji] (empty removes it).
  ChatMessage withReaction(String userId, String emoji) => copyWith(
    reactions: {...reactions}
      ..remove(userId)
      ..addAll(emoji.isEmpty ? const {} : {userId: emoji}),
  );
}

/// What a reaction message carries: the reacted message and the emoji
/// (empty when the reaction is removed).
class ReactionPayload {
  const ReactionPayload(this.targetClientId, this.emoji);
  final String targetClientId;
  final String emoji;

  String encode() => jsonEncode({'to': targetClientId, 'e': emoji});

  static ReactionPayload? tryParse(String? body) {
    try {
      final j = jsonDecode(body ?? '') as Map;
      final to = j['to'], e = j['e'];
      if (to is! String || e is! String || to.isEmpty || e.length > 16) return null;
      return ReactionPayload(to, e);
    } catch (_) {
      return null;
    }
  }
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

  /// Fills in the last message and unread count from the phone's own storage.
  ConversationSummary withLocal({ChatMessage? last, required int unread}) => ConversationSummary(
    matchId: matchId,
    conversationId: conversationId,
    matchedAt: matchedAt,
    otherUserId: otherUserId,
    otherDisplayName: otherDisplayName,
    otherPhoto: otherPhoto,
    lastMessageBody: last?.body,
    lastMessageKind: last?.kind,
    lastMessageSenderId: last?.senderId,
    lastMessageAt: last?.createdAt ?? lastMessageAt,
    unreadCount: unread,
  );
  DateTime get sortTime => lastMessageAt ?? matchedAt;

  String previewFor(String myUserId) {
    final prefix = lastMessageSenderId == myUserId ? 'You: ' : '';
    return switch (lastMessageKind) {
      MessageKind.image => '$prefix📷 Photo',
      MessageKind.video => '$prefix🎥 Video',
      MessageKind.gif => '${prefix}GIF',
      MessageKind.system => lastMessageBody ?? '',
      null => 'Tap to keep chatting',
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
    lastMessageKind: json['last_message_kind'] == null
        ? null
        : MessageKind.fromValue(json['last_message_kind'] as String),
    lastMessageSenderId: json['last_message_sender_id'] as String?,
    lastMessageAt: json['last_message_at'] == null ? null : DateTime.parse(json['last_message_at'] as String),
    unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
  );
}

/// What a GIF message carries: GIPHY's link and the GIF's size.
class GifPayload {
  const GifPayload({required this.url, required this.width, required this.height, this.title = ''});
  final String url;
  final int width;
  final int height;
  final String title;

  double get aspectRatio => width > 0 && height > 0 ? width / height : 1;

  String encode() => jsonEncode({'url': url, 'w': width, 'h': height, 't': title});

  /// Only https links from GIPHY's media servers are ever shown.
  static GifPayload? tryParse(String? body) {
    try {
      final j = jsonDecode(body ?? '') as Map;
      final url = j['url'];
      if (url is! String) return null;
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || !(uri.host == 'giphy.com' || uri.host.endsWith('.giphy.com'))) {
        return null;
      }
      return GifPayload(
        url: url,
        width: (j['w'] as num?)?.toInt() ?? 0,
        height: (j['h'] as num?)?.toInt() ?? 0,
        title: j['t'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
