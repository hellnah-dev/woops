import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../../ads/ad_widgets.dart';
import '../../ads/daily_unlock.dart';
import '../../chat/application/chat_controllers.dart';
import '../../chat/domain/chat_models.dart';
import '../../chat/presentation/conversation_actions.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/profile_enums.dart';
import '../application/match_insights.dart';

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

/// All mutual matches: new ones first, then the ones waiting on your reply,
/// then the rest. Filter by mode (long-term, dating, friends, open) and see
/// why you matched on each card.
class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final insights = ref.watch(matchInsightsProvider).valueOrNull ?? const <String, MatchInsight>{};
    final filter = ref.watch(matchModeFilterProvider);
    final myId = ref.watch(currentUserIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Matches'), actions: const [_MyModeButton(), SizedBox(width: 8)]),
      bottomNavigationBar: const BannerAdSlot(),
      body: inbox.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(inboxProvider)),
        data: (all) {
          Future<void> refresh() async {
            await ref.read(inboxProvider.notifier).refresh();
            ref.invalidate(matchInsightsProvider);
          }

          if (all.isEmpty) {
            return RefreshIndicator(
              onRefresh: refresh,
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

          // Modes present among my matches, with how many each.
          final counts = <MatchMode, int>{};
          for (final c in all) {
            final mode = insights[c.otherUserId]?.mode;
            if (mode != null) counts[mode] = (counts[mode] ?? 0) + 1;
          }
          final shown = filter == null ? all : all.where((c) => insights[c.otherUserId]?.mode == filter).toList();

          final fresh = shown.where((c) => !c.hasMessages).toList()..sort((a, b) => b.matchedAt.compareTo(a.matchedAt));
          // They wrote last: it's my turn to reply.
          final waiting = shown
              .where((c) => c.hasMessages && c.lastMessageSenderId != null && c.lastMessageSenderId != myId)
              .toList();
          final talking = shown.where((c) => c.hasMessages && !waiting.contains(c)).toList();

          // One short ad a day opens Matches (from day 3 of use).
          return DailyAdGate(
            feature: 'matches',
            icon: Icons.people_alt_rounded,
            title: 'You have ${all.length} ${all.length == 1 ? 'match' : 'matches'}',
            message: 'Watch one short ad to open your matches for today.',
            child: RefreshIndicator(
              onRefresh: refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (counts.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _ModeFilter(counts: counts, total: all.length, selected: filter),
                    ),
                  if (shown.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'No ${filter?.label.toLowerCase()} matches yet.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  if (fresh.isNotEmpty) ...[
                    _header(context, 'New matches', 'Say hi. They’re waiting!'),
                    ..._grid(fresh, insights, badge: _Badge.isNew),
                  ],
                  if (waiting.isNotEmpty) ...[
                    _header(context, 'Waiting on you', 'They wrote last. Your turn 💬'),
                    ..._grid(waiting, insights, badge: _Badge.waiting),
                  ],
                  if (talking.isNotEmpty) ...[
                    _header(context, 'In conversation', null),
                    ..._grid(talking, insights, badge: _Badge.none),
                  ],
                  // Room below the last row for the glass tab bar.
                  SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg + MediaQuery.paddingOf(context).bottom)),
                ],
              ),
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

  /// A grid of match cards, with a paced ad card after every 8.
  List<Widget> _grid(List<ConversationSummary> items, Map<String, MatchInsight> insights, {required _Badge badge}) =>
      adSpacedGrid(
        itemCount: items.length,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemBuilder: (context, i) =>
            _MatchTile(summary: items[i], insight: insights[items[i].otherUserId], badge: badge),
      );
}

/// "All · 💞 Long-term 3 · 👋 Friends 1"
class _ModeFilter extends ConsumerWidget {
  const _ModeFilter({required this.counts, required this.total, required this.selected});
  final Map<MatchMode, int> counts;
  final int total;
  final MatchMode? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void pick(MatchMode? m) => ref.read(matchModeFilterProvider.notifier).state = m;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 4),
        children: [
          ChoiceChip(label: Text('All $total'), selected: selected == null, onSelected: (_) => pick(null)),
          for (final m in MatchMode.values)
            if (counts[m] != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  key: Key('mode-${m.name}'),
                  label: Text('${m.emoji} ${m.label} ${counts[m]}'),
                  selected: selected == m,
                  onSelected: (on) => pick(on ? m : null),
                ),
              ),
        ],
      ),
    );
  }
}

/// My own mode (what I'm here for). Tap to switch; it's what others see.
class _MyModeButton extends ConsumerWidget {
  const _MyModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    if (me == null) return const SizedBox.shrink();
    final mode = MatchMode.of(me.intention);
    return ActionChip(
      key: const Key('my-mode'),
      avatar: Text(mode.emoji),
      label: Text(mode.label, semanticsLabel: 'You’re here for: ${mode.label}. Change it'),
      tooltip: 'Change what you’re looking for',
      onPressed: () => _chooseMode(context, ref, me.intention),
    );
  }

  Future<void> _chooseMode(BuildContext context, WidgetRef ref, Intention current) async {
    final picked = await showModalBottomSheet<Intention>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('What are you looking for?', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('Shown on your profile, so people know what you’re here for.'),
            ),
            for (final i in Intention.values)
              ListTile(
                leading: Text(i.emoji, style: const TextStyle(fontSize: 22)),
                title: Text(i.label),
                trailing: i == current ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(context, i),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current || !context.mounted) return;
    try {
      await ref.read(profileRepositoryProvider).updateProfile({'intention': picked.value});
      await ref.read(myProfileProvider.notifier).refresh();
      if (context.mounted) showSnack(context, 'You’re now here for: ${MatchMode.of(picked).label}');
    } catch (e) {
      if (context.mounted) showSnack(context, 'Couldn’t change it. Please try again.', isError: true);
    }
  }
}

enum _Badge { none, isNew, waiting }

class _MatchTile extends ConsumerWidget {
  const _MatchTile({required this.summary, required this.insight, required this.badge});
  final ConversationSummary summary;
  final MatchInsight? insight;
  final _Badge badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ring = badge != _Badge.none;
    final why = insight?.summary;
    return Semantics(
      button: true,
      label: 'Chat with ${summary.otherDisplayName}${why == null ? '' : ', $why'}',
      hint: 'Long press for more options',
      child: GestureDetector(
        onTap: () => openConversation(context, summary),
        onLongPress: () => showConversationActions(context, ref, summary),
        child: Container(
          padding: ring ? const EdgeInsets.all(2.5) : EdgeInsets.zero,
          decoration: BoxDecoration(
            gradient: ring ? AppColors.brandGradient : null,
            borderRadius: BorderRadius.circular(AppRadius.md + 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ProfilePhoto(storagePath: summary.otherPhoto, thumbnail: true, memCacheWidth: 450),
                const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.photoScrim)),
                if (insight != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${insight!.mode.emoji} ${insight!.mode.label}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
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
                        badge == _Badge.waiting
                            ? 'Waiting on you · ${shortTimeAgo(summary.sortTime)}'
                            : why ?? 'Matched ${shortTimeAgo(summary.matchedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      // The interests you share, so you know what to talk about.
                      if (badge != _Badge.waiting && (insight?.sharedInterests.isNotEmpty ?? false))
                        Text(
                          insight!.sharedInterests.take(2).join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
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
