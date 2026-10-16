import 'dart:async';
import 'dart:typed_data';

import 'package:woops/features/chat/data/chat_repository.dart';
import 'package:woops/features/chat/domain/chat_models.dart';
import 'package:woops/features/discovery/data/discovery_repository.dart';
import 'package:woops/features/profile/domain/profile_enums.dart';
import 'package:woops/features/profile/domain/profile_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

ProfileCard card(String id, {String? name, int age = 27, bool random = false}) => ProfileCard(
  id: id,
  isRandom: random,
  displayName: name ?? 'User $id',
  age: age,
  gender: Gender.woman,
  bio: 'Bio of $id',
  intention: Intention.longTerm,
  photos: const [],
  interests: const ['Hiking'],
  prompts: const [],
  distanceKm: 3,
);

class FakeDiscoveryRepository implements DiscoveryRepository {
  FakeDiscoveryRepository(this.pages);

  /// Each call to fetchFeed returns the next page (then empty lists).
  final List<List<ProfileCard>> pages;
  int feedCalls = 0;
  final swipes = <(String, SwipeAction)>[];
  Set<String> matchOnLike = {};
  Object? swipeError;
  String? undoResult;

  @override
  Future<List<ProfileCard>> fetchFeed({int limit = 20}) async {
    final i = feedCalls++;
    return i < pages.length ? pages[i] : const [];
  }

  @override
  Future<SwipeResult> swipe(String targetId, SwipeAction action) async {
    if (swipeError != null) throw swipeError!;
    swipes.add((targetId, action));
    final matched = action == SwipeAction.like && matchOnLike.contains(targetId);
    return SwipeResult(
      matched: matched,
      matchId: matched ? 'm-$targetId' : null,
      conversationId: matched ? 'c-$targetId' : null,
    );
  }

  @override
  Future<String> undoLastPass() async {
    if (undoResult == null) throw const PostgrestException(message: 'nothing_to_undo');
    return undoResult!;
  }

  @override
  Future<List<ProfileCard>> fetchLikesReceived({int limit = 30, int offset = 0}) async => const [];
}

class FakeChatRepository implements ChatRepository {
  FakeChatRepository({this.myId = 'me'});

  final String myId;
  final incoming = StreamController<ChatMessage>.broadcast();
  final receipts = StreamController<DateTime>.broadcast();
  final inbox = StreamController<void>.broadcast();
  final sentClientIds = <String>[];
  int failNextSends = 0;
  int markReadCalls = 0;

  @override
  String? get currentUserId => myId;

  @override
  Future<List<ConversationSummary>> fetchConversations({int limit = 50, int offset = 0}) async => const [];

  /// Messages waiting on the fake relay.
  List<ChatMessage> pending = [];
  final ackedIds = <String>[];

  @override
  Future<List<ChatMessage>> fetchPendingMessages() async => [...pending];

  @override
  Future<void> ackMessages(List<String> ids) async {
    ackedIds.addAll(ids);
    pending.removeWhere((m) => ids.contains(m.id));
  }

  /// What actually went over the wire (ciphertext when encrypted).
  final sentBodies = <String>[];
  final sentEncrypted = <bool>[];
  final chatKeys = <String, String>{};
  final media = <String, Uint8List>{};
  int mediaUsed = 0;
  int mediaLimit = 5 * 1024 * 1024;

  @override
  Future<ChatMessage> sendMessage(
    String conversationId,
    String body, {
    required String clientId,
    MessageKind kind = MessageKind.text,
    String? mediaPath,
    bool encrypted = false,
  }) async {
    if (failNextSends > 0) {
      failNextSends--;
      throw const PostgrestException(message: 'rate_limited: slow down');
    }
    sentClientIds.add(clientId);
    sentBodies.add(body);
    sentEncrypted.add(encrypted);
    return ChatMessage(
      id: 'srv-$clientId',
      conversationId: conversationId,
      senderId: myId,
      clientId: clientId,
      kind: kind,
      body: body,
      mediaPath: mediaPath,
      encrypted: encrypted,
      createdAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> publishChatKey(String publicKey) async => chatKeys[myId] = publicKey;

  @override
  Future<String?> fetchChatKey(String userId) async => chatKeys[userId];

  @override
  Future<void> uploadMedia(String path, Uint8List bytes) async => media[path] = bytes;

  @override
  Future<Uint8List> downloadMedia(String path) async => media[path] ?? (throw Exception('not found'));

  @override
  Future<void> deleteMedia(String path) async => media.remove(path);

  @override
  Future<({int used, int limit})> mediaUsage() async => (used: mediaUsed, limit: mediaLimit);

  @override
  Future<void> markRead(String conversationId) async => markReadCalls++;

  @override
  Future<DateTime?> fetchReadReceipt(String conversationId, String userId) async => null;

  @override
  Stream<ChatMessage> watchMessages(String conversationId) => incoming.stream;

  @override
  Stream<DateTime> watchReadReceipts(String conversationId, String otherUserId) => receipts.stream;

  @override
  Stream<void> watchInbox() => inbox.stream;

  @override
  Future<void> unmatch(String matchId) async {}
}

ChatMessage msg(String id, {String sender = 'other', required DateTime at, String? clientId}) => ChatMessage(
  id: id,
  conversationId: 'c1',
  senderId: sender,
  clientId: clientId ?? 'client-$id',
  kind: MessageKind.text,
  body: 'message $id',
  createdAt: at,
);
