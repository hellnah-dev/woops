import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ads/ad_widgets.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../../matches/presentation/matches_screen.dart';
import '../application/chat_controllers.dart';
import 'conversation_actions.dart';
import '../domain/chat_models.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final myId = ref.watch(currentUserIdProvider) ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: inbox.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(inboxProvider)),
        data: (all) {
          final newMatches = all.where((c) => !c.hasMessages).toList();
          final chats = all.where((c) => c.hasMessages).toList()..sort((a, b) => b.sortTime.compareTo(a.sortTime));
          return RefreshIndicator(
            onRefresh: () => ref.read(inboxProvider.notifier).refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (newMatches.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
                    child: Text('New matches', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      itemCount: newMatches.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, i) {
                        final c = newMatches[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          onTap: () => openConversation(context, c),
                          onLongPress: () => showConversationActions(context, ref, c),
                          child: SizedBox(
                            width: 72,
                            child: Column(
                              children: [
                                ProfileAvatar(storagePath: c.otherPhoto, size: 64, ring: true),
                                const SizedBox(height: 6),
                                Text(c.otherDisplayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 24),
                ],
                if (chats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: EmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'No conversations yet',
                      message: newMatches.isEmpty
                          ? 'Match with someone to start chatting.'
                          : 'Tap a new match above to send the first message.',
                      actionLabel: newMatches.isEmpty ? 'Start discovering' : null,
                      onAction: newMatches.isEmpty ? () => context.go(Routes.discover) : null,
                    ),
                  )
                else
                  for (final (i, c) in chats.indexed) ...[
                    _ConversationTile(
                      summary: c,
                      myId: myId,
                      onLongPress: () => showConversationActions(context, ref, c),
                    ),
                    // One paced "Sponsored" card after the third chat, never between more.
                    if (i == 2)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                        child: NativeAdCard(),
                      ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.summary, required this.myId, this.onLongPress});
  final ConversationSummary summary;
  final String myId;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = summary.unreadCount > 0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      leading: ProfileAvatar(storagePath: summary.otherPhoto, size: 56),
      title: Text(
        summary.otherDisplayName,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
      ),
      subtitle: Text(
        summary.previewFor(myId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: unread ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
          fontWeight: unread ? FontWeight.w600 : null,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(shortTimeAgo(summary.sortTime), style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          if (unread)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(10)),
              child: Text(
                summary.unreadCount > 99 ? '99+' : '${summary.unreadCount}',
                semanticsLabel: '${summary.unreadCount} unread',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            )
          else
            const SizedBox(height: 18),
        ],
      ),
      onTap: () => openConversation(context, summary),
      onLongPress: onLongPress,
    );
  }
}
