import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../../ads/ad_widgets.dart';
import '../../discovery/application/discovery_controller.dart';
import '../../discovery/data/discovery_repository.dart';
import '../../discovery/presentation/match_flow.dart';
import '../../profile/domain/profile_models.dart';
import '../../profile/presentation/profile_detail_screen.dart';

/// People who liked you and are waiting for your answer.
class LikesScreen extends ConsumerWidget {
  const LikesScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, ProfileCard card) async {
    final action = await context.push<SwipeAction>(
      Routes.user(card.id),
      extra: ProfileDetailArgs(card: card, actions: ProfileDetailActions.swipe),
    );
    if (action == null || !context.mounted) return;
    try {
      final result = await ref.read(discoveryRepositoryProvider).swipe(card.id, action);
      ref.invalidate(likesReceivedProvider);
      if (context.mounted) await celebrateMatch(context, ref, result, card);
    } catch (e) {
      if (context.mounted) showSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likes = ref.watch(likesReceivedProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Likes')),
      bottomNavigationBar: const BannerAdSlot(),
      body: likes.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(likesReceivedProvider)),
        data: (cards) => RefreshIndicator(
          onRefresh: () => ref.refresh(likesReceivedProvider.future),
          child: cards.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.favorite_border_rounded,
                    title: 'No likes yet',
                    message: 'When someone likes you, they’ll show up here. '
                        'A complete profile with a few great photos helps.',
                  ),
                ])
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          '${cards.length} ${cards.length == 1 ? 'person likes' : 'people like'} you. '
                          'Like them back to match.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      sliver: SliverGrid.builder(
                        itemCount: cards.length,
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        itemBuilder: (context, i) => _LikeTile(card: cards[i], onTap: () => _open(context, ref, cards[i])),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _LikeTile extends StatelessWidget {
  const _LikeTile({required this.card, required this.onTap});
  final ProfileCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${card.displayName}, ${card.age}. Open profile',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ProfilePhoto(storagePath: card.primaryPhoto, thumbnail: true, memCacheWidth: 500),
              const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.photoScrim)),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  '${card.displayName}, ${card.age}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
