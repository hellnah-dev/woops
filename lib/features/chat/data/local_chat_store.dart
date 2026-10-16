import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/chat_models.dart';

/// What the phone remembers about one conversation.
class LocalConversation {
  const LocalConversation({this.messages = const [], this.lastReadAt});

  /// Newest first.
  final List<ChatMessage> messages;

  /// When I last looked at this conversation (for unread counts).
  final DateTime? lastReadAt;

  ChatMessage? get last => messages.isEmpty ? null : messages.first;

  int unreadFor(String myId) =>
      messages.where((m) => m.senderId != myId && (lastReadAt == null || m.createdAt.isAfter(lastReadAt!))).length;
}

/// Chat history lives only on this phone, like WhatsApp. The server only
/// relays a message until it is saved here (see `ack_messages`).
///
/// One JSON file per conversation under `<app documents>/chats/<my user id>/`.
abstract class LocalChatStore {
  Future<LocalConversation> read(String conversationId);

  /// Adds or replaces messages (matched by client id) and saves.
  Future<LocalConversation> upsert(String conversationId, Iterable<ChatMessage> messages);

  Future<void> markRead(String conversationId, DateTime at);

  /// Removes one message (an unsent one the user discarded).
  Future<void> removeMessage(String conversationId, String clientId);

  Future<void> deleteConversation(String conversationId);

  /// Removes conversations that are no longer active (unmatched / blocked).
  Future<void> retainOnly(Set<String> conversationIds);

  /// Deletes every conversation of this user (account deletion).
  Future<void> wipe();

  /// Saves a chat photo on the phone and returns its file path.
  Future<String> saveMedia(String conversationId, String name, Uint8List bytes);

  /// Fires with a conversation id whenever that conversation changes.
  Stream<String> get changes;
}

class FileLocalChatStore implements LocalChatStore {
  FileLocalChatStore(this._userId, {Future<Directory> Function()? baseDir})
    : _baseDir = baseDir ?? getApplicationDocumentsDirectory;

  final String _userId;
  final Future<Directory> Function() _baseDir;
  final _cache = <String, LocalConversation>{};
  final _locks = <String, Future<void>>{};
  final _changes = StreamController<String>.broadcast();
  Directory? _dir;

  @override
  Stream<String> get changes => _changes.stream;

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await _baseDir();
    return _dir = await Directory('${base.path}/chats/$_userId').create(recursive: true);
  }

  Future<File> _file(String conversationId) async => File('${(await _folder()).path}/$conversationId.json');

  /// Runs [task] after any earlier write to the same conversation finished.
  Future<T> _serial<T>(String id, Future<T> Function() task) {
    final previous = _locks[id] ?? Future<void>.value();
    final result = previous.then((_) => task());
    _locks[id] = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<LocalConversation> read(String conversationId) async {
    final cached = _cache[conversationId];
    if (cached != null) return cached;
    final file = await _file(conversationId);
    if (!await file.exists()) return _cache[conversationId] = const LocalConversation();
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final conv = LocalConversation(
        messages: [
          for (final m in (json['messages'] as List? ?? const []))
            ChatMessage.fromLocalJson(Map<String, dynamic>.from(m as Map)),
        ],
        lastReadAt: json['last_read_at'] == null ? null : DateTime.parse(json['last_read_at'] as String),
      );
      return _cache[conversationId] = conv;
    } catch (e) {
      debugPrint('Unreadable chat file $conversationId: $e');
      return _cache[conversationId] = const LocalConversation();
    }
  }

  Future<void> _write(String conversationId, LocalConversation conv) async {
    _cache[conversationId] = conv;
    final file = await _file(conversationId);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'last_read_at': conv.lastReadAt?.toUtc().toIso8601String(),
        'messages': [for (final m in conv.messages) m.toLocalJson()],
      }),
      flush: true,
    );
    await tmp.rename(file.path); // atomic replace: never a half-written file
    _changes.add(conversationId);
  }

  @override
  Future<LocalConversation> upsert(String conversationId, Iterable<ChatMessage> messages) =>
      _serial(conversationId, () async {
        final current = await read(conversationId);
        final next = LocalConversation(
          messages: mergeMessages(current.messages, messages),
          lastReadAt: current.lastReadAt,
        );
        await _write(conversationId, next);
        return next;
      });

  @override
  Future<void> markRead(String conversationId, DateTime at) => _serial(conversationId, () async {
    final current = await read(conversationId);
    if (current.lastReadAt != null && !at.isAfter(current.lastReadAt!)) return;
    await _write(conversationId, LocalConversation(messages: current.messages, lastReadAt: at));
  });

  @override
  Future<void> removeMessage(String conversationId, String clientId) => _serial(conversationId, () async {
    final current = await read(conversationId);
    await _write(
      conversationId,
      LocalConversation(
        messages: current.messages.where((m) => m.clientId != clientId).toList(),
        lastReadAt: current.lastReadAt,
      ),
    );
  });

  @override
  Future<void> deleteConversation(String conversationId) => _serial(conversationId, () async {
    _cache.remove(conversationId);
    final file = await _file(conversationId);
    if (await file.exists()) await file.delete();
    final media = Directory('${(await _folder()).path}/media');
    if (await media.exists()) {
      await for (final f in media.list()) {
        if (f.uri.pathSegments.last.startsWith('${conversationId}_')) await f.delete();
      }
    }
    _changes.add(conversationId);
  });

  @override
  Future<void> retainOnly(Set<String> conversationIds) async {
    final dir = await _folder();
    await for (final entity in dir.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is! File || !name.endsWith('.json')) continue;
      final id = name.substring(0, name.length - 5);
      if (!conversationIds.contains(id)) await deleteConversation(id);
    }
  }

  @override
  Future<String> saveMedia(String conversationId, String name, Uint8List bytes) async {
    final dir = await Directory('${(await _folder()).path}/media').create(recursive: true);
    final file = File('${dir.path}/${conversationId}_$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<void> wipe() async {
    _cache.clear();
    final dir = await _folder();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
  }
}

/// In-memory store for tests and web (where there is no app documents folder).
class MemoryLocalChatStore implements LocalChatStore {
  final _data = <String, LocalConversation>{};
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get changes => _changes.stream;

  @override
  Future<LocalConversation> read(String conversationId) async => _data[conversationId] ?? const LocalConversation();

  @override
  Future<LocalConversation> upsert(String conversationId, Iterable<ChatMessage> messages) async {
    final current = await read(conversationId);
    final next = LocalConversation(messages: mergeMessages(current.messages, messages), lastReadAt: current.lastReadAt);
    _data[conversationId] = next;
    _changes.add(conversationId);
    return next;
  }

  @override
  Future<void> markRead(String conversationId, DateTime at) async {
    final current = await read(conversationId);
    _data[conversationId] = LocalConversation(messages: current.messages, lastReadAt: at);
    _changes.add(conversationId);
  }

  @override
  Future<void> removeMessage(String conversationId, String clientId) async {
    final current = await read(conversationId);
    _data[conversationId] = LocalConversation(
      messages: current.messages.where((m) => m.clientId != clientId).toList(),
      lastReadAt: current.lastReadAt,
    );
    _changes.add(conversationId);
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    _data.remove(conversationId);
    _changes.add(conversationId);
  }

  @override
  Future<void> retainOnly(Set<String> conversationIds) async =>
      _data.removeWhere((id, _) => !conversationIds.contains(id));

  @override
  Future<void> wipe() async => _data.clear();

  final media = <String, Uint8List>{};

  @override
  Future<String> saveMedia(String conversationId, String name, Uint8List bytes) async {
    final path = 'memory://${conversationId}_$name';
    media[path] = bytes;
    return path;
  }
}

final localChatStoreProvider = Provider<LocalChatStore>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (kIsWeb || uid == null) return MemoryLocalChatStore();
  return FileLocalChatStore(uid);
});
