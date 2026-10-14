import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/utils/app_exception.dart';
import '../../ads/rewarded_likes.dart';
import '../../profile/domain/profile_models.dart';
import '../../profile/presentation/profile_detail_screen.dart';
import '../application/discovery_controller.dart';
import '../data/discovery_repository.dart';
import 'filters_sheet.dart';
import 'match_flow.dart';
import 'profile_card_view.dart';
import 'swipeable_card.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _cardKeys = <String, GlobalKey<SwipeableCardState>>{};

  GlobalKey<SwipeableCardState> _keyFor(String id) => _cardKeys.putIfAbsent(id, GlobalKey.new);

  Future<void> _onSwiped(ProfileCard card, SwipeAction action) async {
    _cardKeys.remove(card.id);
    try {
      final result = await ref.read(discoveryControllerProvider.notifier).swipe(card, action);
      if (result != null && result.matched && mounted) {
        await celebrateMatch(context, ref, result, card);
      }
    } catch (e) {
      if (!mounted) return;
      final error = AppException.from(e);
      if (error.code == 'rate_limited' && error.message.toLowerCase().contains('out of likes')) {
        await offerRewardedLikes(context, ref);
      } else {
        showSnack(context, error.message, isError: true);
      }
    }
  }

  Future<void> _undo() async {
    try {
      await ref.read(discoveryControllerProvider.notifier).undo();
    } catch (e) {
      if (mounted) showSnack(context, e);
    }
  }

  Future<void> _openDetails(ProfileCard card) async {
    final action = await context.push<SwipeAction>(
      Routes.user(card.id),
      extra: ProfileDetailArgs(card: card, actions: ProfileDetailActions.swipe),
    );
    if (action != null) _keyFor(card.id).currentState?.swipe(action);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoveryControllerProvider);
    final current = state.current;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: const Row(
          children: [
            AppLogo(size: 32),
            SizedBox(width: 10),
            Text(AppLogo.appName),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Filters',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showFiltersSheet(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Builder(builder: (context) {
          if (state.queue.isEmpty) {
            if (state.isLoading) return const LoadingView(message: 'Finding people for you…');
            if (state.error != null) {
              return ErrorView(
                error: state.error!,
                onRetry: () => ref.read(discoveryControllerProvider.notifier).load(reset: true),
              );
            }
            return EmptyState(
              icon: Icons.travel_explore_rounded,
              title: 'You’ve seen everyone for now',
              message: 'Check back later, or widen your filters to discover more people.',
              actionLabel: 'Adjust filters',
              onAction: () => showFiltersSheet(context),
            );
          }

          final visible = state.queue.take(2).toList();
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                  child: Stack(
                    children: [
                      // Render back-to-front so the current card is on top.
                      for (final card in visible.reversed)
                        Positioned.fill(
                          key: ValueKey(card.id),
                          child: card.id == current!.id
                              ? SwipeableCard(
                                  key: _keyFor(card.id),
                                  onSwiped: (a) => _onSwiped(card, a),
                                  child: ProfileCardView(card: card, onInfo: () => _openDetails(card)),
                                )
                              : Transform.scale(
                                  scale: 0.95,
                                  child: IgnorePointer(child: ProfileCardView(card: card)),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    RoundActionButton(
                      tooltip: 'Undo last pass',
                      icon: Icons.replay_rounded,
                      color: AppColors.undo,
                      size: 52,
                      onPressed: state.canUndo ? _undo : null,
                    ),
                    RoundActionButton(
                      tooltip: 'Pass',
                      icon: Icons.close_rounded,
                      color: AppColors.pass,
                      size: 68,
                      onPressed: () => _keyFor(current!.id).currentState?.swipe(SwipeAction.pass),
                    ),
                    RoundActionButton(
                      tooltip: 'Like',
                      icon: Icons.favorite_rounded,
                      color: AppColors.like,
                      size: 68,
                      onPressed: () => _keyFor(current!.id).currentState?.swipe(SwipeAction.like),
                    ),
                    RoundActionButton(
                      tooltip: 'View profile',
                      icon: Icons.info_outline_rounded,
                      color: AppColors.violet,
                      size: 52,
                      onPressed: () => _openDetails(current!),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
