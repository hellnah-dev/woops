import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_views.dart';
import '../../safety/presentation/safety_actions.dart';
import '../application/chat_controllers.dart';
import '../data/chat_repository.dart';
import '../data/local_chat_store.dart';
import '../domain/chat_models.dart';

/// Deletes the chat history saved on this phone (photos included). The match
/// stays, so you can keep chatting; the other phone keeps its own copy.
Future<bool> confirmDeleteHistory(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  required String name,
}) async {
  final ok = await confirmAction(
    context,
    icon: Icons.delete_sweep_outlined,
    destructive: true,
    title: 'Delete chat with $name?',
    message:
        'Messages and photos are removed from this phone. You stay matched and can keep chatting. '
        '$name keeps their own copy.',
    confirmLabel: 'Delete',
  );
  if (!ok) return false;
  await ref.read(localChatStoreProvider).deleteConversation(conversationId);
  if (context.mounted) showSnack(context, 'Chat deleted from this phone');
  return true;
}

/// Unmatch: removes the match for both, and the chat from both phones.
Future<bool> confirmUnmatch(
  BuildContext context,
  WidgetRef ref, {
  required String matchId,
  required String conversationId,
  required String name,
}) async {
  final ok = await confirmAction(
    context,
    icon: Icons.heart_broken_outlined,
    destructive: true,
    title: 'Unmatch $name?',
    message: 'This removes the match, and the chat is deleted from both phones. It can’t be undone.',
    confirmLabel: 'Unmatch',
  );
  if (!ok) return false;
  try {
    await ref.read(chatRepositoryProvider).unmatch(matchId);
    await ref.read(localChatStoreProvider).deleteConversation(conversationId);
    await ref.read(inboxProvider.notifier).refresh();
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, e);
    return false;
  }
}

/// Long-press menu for a chat in the Chats and Matches lists.
Future<void> showConversationActions(BuildContext context, WidgetRef ref, ConversationSummary c) async {
  final name = c.otherDisplayName;
  final action = await showModalBottomSheet<String>(
    // Over the whole screen, never under the glass tab bar.
    useRootNavigator: true,
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text('View $name’s profile'),
            onTap: () => Navigator.pop(context, 'profile'),
          ),
          if (c.hasMessages)
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Delete chat history'),
              subtitle: const Text('Only on this phone. You stay matched.'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ListTile(
            leading: const Icon(Icons.heart_broken_outlined),
            title: const Text('Unmatch'),
            onTap: () => Navigator.pop(context, 'unmatch'),
          ),
          ListTile(
            leading: Icon(Icons.block_rounded, color: Theme.of(context).colorScheme.error),
            title: Text('Block $name', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => Navigator.pop(context, 'block'),
          ),
          ListTile(
            leading: Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('Report $name', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => Navigator.pop(context, 'report'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'profile':
      context.push(Routes.user(c.otherUserId));
    case 'delete':
      await confirmDeleteHistory(context, ref, conversationId: c.conversationId, name: name);
    case 'unmatch':
      await confirmUnmatch(context, ref, matchId: c.matchId, conversationId: c.conversationId, name: name);
    case 'block':
      await confirmAndBlock(context, ref, userId: c.otherUserId, name: name);
    case 'report':
      await showReportSheet(context, ref, userId: c.otherUserId, name: name);
  }
}
