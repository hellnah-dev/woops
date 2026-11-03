import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' show NativeAd;

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/love_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/utils/app_exception.dart';
import '../../ads/ad_pacer.dart';
import '../../ads/ad_widgets.dart';
import '../../ads/ads_config.dart';
import '../../ads/ads_service.dart';
import '../../ads/rewarded_likes.dart';
import '../../moments/presentation/moments_ui.dart';
import '../../notifications/activity_screen.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/profile_models.dart';
import '../../profile/presentation/profile_detail_screen.dart';
import '../../profile/presentation/readiness_card.dart';
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

  /// Live drag of the top card (-1 pass … 1 like): grows the next card and
  /// the matching button as you drag, like Tinder.
  final _dragProgress = ValueNotifier<double>(0);

  /// A card brought back by Undo flies in from the left.
  String? _rewindId;

  // Paced "Sponsored" card between profiles (see AdPacing): rare for new
  // users, at most one every 5 profiles and 5 ads per 5 minutes later on.
  int _sinceAd = 0;
  NativeAd? _deckAd;
  bool _loadingAd = false;
  bool _showAd = false;

  void _afterSwipe() {
    _sinceAd++;
    if (!AdsConfig.supported || !AdsConfig.deckEnabled || !ref.read(adsReadyProvider)) return;
    final pacing = ref.read(adPacerProvider);
    final every = pacing.swipesBetweenDeckAds;
    if (_deckAd == null && !_loadingAd && _sinceAd >= every - 2 && pacing.canShow) {
      _loadingAd = true;
      loadDeckAd(
        dark: Theme.of(context).brightness == Brightness.dark,
        onImpression: () => ref.read(adPacerProvider.notifier).recordImpression(),
      ).then((ad) {
        _loadingAd = false;
        if (!mounted) return ad?.dispose();
        _deckAd = ad;
      });
    }
    if (_deckAd != null && _sinceAd >= every && pacing.canShow) setState(() => _showAd = true);
  }

  void _dismissAd() {
    final ad = _deckAd;
    setState(() {
      _showAd = false;
      _deckAd = null;
      _sinceAd = 0;
    });
    // Dispose after the frame so the platform view is gone first.
    WidgetsBinding.instance.addPostFrameCallback((_) => ad?.dispose());
  }

  @override
  void dispose() {
    _dragProgress.dispose();
    _deckAd?.dispose();
    super.dispose();
  }

  Future<void> _onSwiped(ProfileCard card, SwipeAction action) async {
    _cardKeys.remove(card.id);
    _afterSwipe();
    try {
      final result = await ref.read(discoveryControllerProvider.notifier).swipe(card, action);
      if (result != null && result.matched && mounted) {
        await celebrateMatch(context, ref, result, card);
      }
    } catch (e) {
      if (!mounted) return;
      final error = AppException.from(e);
      if (error.code == 'profile_not_ready') {
        await ref.read(myProfileProvider.notifier).refresh();
        ref.read(discoveryControllerProvider.notifier).load(reset: true);
        if (mounted) showSnack(context, 'Finish your profile to start matching', isError: true);
      } else if (error.code == 'rate_limited' && error.message.toLowerCase().contains('out of likes')) {
        await offerRewardedLikes(context, ref);
      } else {
        showSnack(context, error.message, isError: true);
      }
    }
  }

  Future<void> _undo() async {
    final passed = ref.read(discoveryControllerProvider).lastPassed;
    // The previous top card gets a fresh state when it's no longer on top.
    final current = ref.read(discoveryControllerProvider).current;
    if (current != null) _cardKeys.remove(current.id);
    setState(() => _rewindId = passed?.id);
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
    final me = ref.watch(myProfileProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: const Row(
          children: [
            AppLogo(size: 32),
            SizedBox(width: 10),
            Wordmark(size: 26, text: AppLogo.appName),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Map', icon: const Icon(Icons.map_outlined), onPressed: () => context.push(Routes.map)),
          IconButton(
            tooltip: 'Filters',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showFiltersSheet(context),
          ),
          const ActivityBell(),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Your matches' 24-hour moments (only once you can date).
            if (me != null && me.isReadyToDate) const MomentsRow(),
            Expanded(
              child: Builder(
                builder: (context) {
                  // Incomplete profiles see what's missing (and why) instead of cards.
                  if (me != null && !me.isReadyToDate) return ProfileGate(profile: me);
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
                      message:
                          'New people join every day. Check back soon, or pull in more people by widening your filters.',
                      actionLabel: 'Adjust filters',
                      onAction: () => showFiltersSheet(context),
                    );
                  }

                  final visible = state.queue.take(2).toList();
                  return Column(
                    children: [
                      if (me != null && me.completeness < 1) _CompleteNudge(percent: me.completenessPercent),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                          child: _showAd && _deckAd != null
                              ? DeckAdCard(ad: _deckAd!, onContinue: _dismissAd)
                              : Stack(
                                  children: [
                                    // Render back-to-front so the current card is on top.
                                    // The same widget tree for both cards, so the next
                                    // card is promoted (scaled up) instead of rebuilt.
                                    for (final card in visible.reversed)
                                      Positioned.fill(
                                        key: ValueKey(card.id),
                                        // The next card grows from 95% to full size as
                                        // the top card is dragged away, so promotion
                                        // never jumps.
                                        child: ValueListenableBuilder<double>(
                                          valueListenable: _dragProgress,
                                          builder: (context, p, child) => Transform.scale(
                                            scale: card.id == current.id ? 1 : 0.95 + 0.05 * p.abs(),
                                            child: child,
                                          ),
                                          child: IgnorePointer(
                                            ignoring: card.id != current!.id,
                                            child: SwipeableCard(
                                              key: _keyFor(card.id),
                                              enabled: card.id == current.id,
                                              progress: card.id == current.id ? _dragProgress : null,
                                              enterFrom: card.id == _rewindId
                                                  ? Offset(-MediaQuery.sizeOf(context).width * 1.4, 0)
                                                  : null,
                                              onSwiped: (a) => _onSwiped(card, a),
                                              // Own layer: dragging moves the drawn card
                                              // instead of repainting photo and labels.
                                              child: RepaintBoundary(
                                                child: ProfileCardView(
                                                  card: card,
                                                  onInfo: card.id == current.id ? () => _openDetails(card) : null,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                      if (!(_showAd && _deckAd != null))
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
                              _GrowWithDrag(
                                progress: _dragProgress,
                                towards: -1,
                                child: RoundActionButton(
                                  tooltip: 'Pass',
                                  icon: Icons.close_rounded,
                                  color: AppColors.pass,
                                  size: 68,
                                  onPressed: () => _keyFor(current!.id).currentState?.swipe(SwipeAction.pass),
                                ),
                              ),
                              _GrowWithDrag(
                                progress: _dragProgress,
                                towards: 1,
                                child: HeartButton(
                                  tooltip: 'Like',
                                  size: 78,
                                  onPressed: () => _keyFor(current!.id).currentState?.swipe(SwipeAction.like),
                                ),
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim reminder above the cards until the profile is 100% complete.
class _CompleteNudge extends StatelessWidget {
  const _CompleteNudge({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      child: Material(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => context.go(Routes.profile),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(value: percent / 100, strokeWidth: 3)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Profile $percent% complete. Finish it for more matches',
                    style: theme.textTheme.labelLarge?.copyWith(color: fg),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Swells a button as the card is dragged towards its side ([towards] is -1
/// for pass, 1 for like).
class _GrowWithDrag extends StatelessWidget {
  const _GrowWithDrag({required this.progress, required this.towards, required this.child});
  final ValueNotifier<double> progress;
  final double towards;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: progress,
    builder: (context, p, child) => Transform.scale(scale: 1 + 0.18 * (p * towards).clamp(0.0, 1.0), child: child),
    child: child,
  );
}
