import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../../ads/ad_widgets.dart';
import '../../chat/application/chat_controllers.dart';
import '../../chat/domain/chat_models.dart';

void openConversation(BuildContext context, ConversationSummary c) {
  context.push(
    Routes.chat(c.conversationId),
    extra: ChatRouteArgs(
      matchId: c.matchId,
      otherUserId: c.otherUserId,
      otherName: c.otherDisplayName,
      otherPhoto: c.otherPhoto,
    ),
  );
}

/// All mutual matches. New ones (no messages yet) are highlighted first.
class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Matches')),
      bottomNavigationBar: const BannerAdSlot(),
      body: inbox.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(inboxProvider)),
        data: (all) {
          if (all.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.read(inboxProvider.notifier).refresh(),
              child: ListView(
                children: [
                  const SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'No matches yet',
                    message: 'When you and someone else like each other, you’ll match and can start chatting.',
                    actionLabel: 'Start discovering',
                    onAction: () => context.go(Routes.discover),
                  ),
                ],
              ),
            );
          }
          final fresh = all.where((c) => !c.hasMessages).toList()..sort((a, b) => b.matchedAt.compareTo(a.matchedAt));
          final talking = all.where((c) => c.hasMessages).toList();
          return RefreshIndicator(
            onRefresh: () => ref.read(inboxProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (fresh.isNotEmpty) ...[
                  _header(context, 'New matches', 'Say hi. They’re waiting!'),
                  _grid(fresh, isNew: true),
                ],
                if (talking.isNotEmpty) ...[_header(context, 'In conversation', null), _grid(talking, isNew: false)],
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, String title, String? subtitle) {
    final theme = Theme.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            if (subtitle != null)
              Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<ConversationSummary> items, {required bool isNew}) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    sliver: SliverGrid.builder(
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (context, i) => _MatchTile(summary: items[i], isNew: isNew),
    ),
  );
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.summary, required this.isNew});
  final ConversationSummary summary;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Chat with ${summary.otherDisplayName}',
      child: GestureDetector(
        onTap: () => openConversation(context, summary),
        child: Container(
          padding: isNew ? const EdgeInsets.all(2.5) : EdgeInsets.zero,
          decoration: BoxDecoration(
            gradient: isNew ? AppColors.brandGradient : null,
            borderRadius: BorderRadius.circular(AppRadius.md + 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ProfilePhoto(storagePath: summary.otherPhoto, thumbnail: true, memCacheWidth: 450),
                const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.photoScrim)),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.otherDisplayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                      ),
                      Text(
                        'Matched ${shortTimeAgo(summary.matchedAt)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
