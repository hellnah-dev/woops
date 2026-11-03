import 'dart:async';

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
import '../../../core/widgets/glass.dart';
import '../application/chat_controllers.dart';
import '../data/local_chat_store.dart';
import 'conversation_actions.dart';
import '../domain/chat_models.dart';

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _search = TextEditingController();
  String _query = '';

  /// Conversation id -> newest message whose text matches the query.
  Map<String, ChatMessage> _messageHits = const {};
  Timer? _debounce;
  StreamSubscription<String>? _storeChanges;

  @override
  void initState() {
    super.initState();
    // New or deleted messages change what matches the current search.
    _storeChanges = ref.read(localChatStoreProvider).changes.listen((_) {
      if (_query.isNotEmpty) _searchMessages();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _storeChanges?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    // Old hits belong to the old query: drop them at once.
    setState(() {
      _query = q.trim();
      _messageHits = const {};
    });
    _searchMessages();
  }

  /// Message text lives on this phone: search it after a short pause.
  void _searchMessages() {
    _debounce?.cancel();
    final query = _query;
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      final ids = (ref.read(inboxProvider).valueOrNull ?? const []).map((c) => c.conversationId);
      final hits = await ref.read(localChatStoreProvider).search(ids, query);
      if (mounted && query == _query) setState(() => _messageHits = hits);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider);
    final myId = ref.watch(currentUserIdProvider) ?? '';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: inbox.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(inboxProvider)),
        data: (all) {
          final q = _query.toLowerCase();
          final searching = q.isNotEmpty;
          bool matches(ConversationSummary c) =>
              c.otherDisplayName.toLowerCase().contains(q) || _messageHits.containsKey(c.conversationId);
          final newMatches = all.where((c) => !c.hasMessages && (!searching || matches(c))).toList();
          final chats = all.where((c) => c.hasMessages && (!searching || matches(c))).toList()
            ..sort((a, b) => b.sortTime.compareTo(a.sortTime));

          return RefreshIndicator(
            onRefresh: () => ref.read(inboxProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (all.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                      child: GlassSurface(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        shadow: false,
                        child: TextField(
                          key: const Key('chat-search'),
                          controller: _search,
                          onChanged: _onQuery,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search names and messages',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () {
                                      _search.clear();
                                      _onQuery('');
                                    },
                                  ),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (newMatches.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
                      child: Text('New matches', style: theme.textTheme.titleMedium),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
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
                  ),
                  const SliverToBoxAdapter(child: Divider(height: 24)),
                ],
                if (chats.isEmpty && newMatches.isEmpty && searching)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No results for “$_query”',
                        message: 'Search looks through names and the messages saved on this phone.',
                      ),
                    ),
                  )
                else if (chats.isEmpty && !searching)
                  SliverToBoxAdapter(
                    child: Padding(
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
                    ),
                  )
                else
                  // Built lazily: only the rows on screen exist, so hundreds of chats stay smooth.
                  SliverList.builder(
                    itemCount: chats.length,
                    itemBuilder: (context, i) {
                      final c = chats[i];
                      // "Found in chat" only when the match is in a message, not the name.
                      final hit = searching && !c.otherDisplayName.toLowerCase().contains(q)
                          ? _messageHits[c.conversationId]
                          : null;
                      final tile = _ConversationTile(
                        summary: c,
                        myId: myId,
                        matchedMessage: hit?.body,
                        onLongPress: () => showConversationActions(context, ref, c),
                      );
                      // One paced "Sponsored" card after the third chat (not while searching).
                      if (i != 2 || searching) return tile;
                      return Column(
                        children: [
                          tile,
                          const NativeAdCard(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                          ),
                        ],
                      );
                    },
                  ),
                // Room for the glass tab bar.
                SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + AppSpacing.md)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.summary, required this.myId, this.onLongPress, this.matchedMessage});
  final ConversationSummary summary;
  final String myId;

  /// When searching: the message that matched, shown instead of the preview.
  final String? matchedMessage;
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
        matchedMessage == null ? summary.previewFor(myId) : 'Found in chat: $matchedMessage',
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
