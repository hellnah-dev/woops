import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../../safety/presentation/safety_actions.dart';
import '../application/chat_controllers.dart';
import '../data/chat_repository.dart';
import '../domain/chat_models.dart';

/// Resolves route arguments (e.g. when opened from a push notification, only
/// the conversation id is known) and then shows the conversation.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.conversationId, this.args});

  final String conversationId;
  final ChatRouteArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (args != null) return _ChatView(conversationId: conversationId, args: args!);

    final inbox = ref.watch(inboxProvider);
    return inbox.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorView(error: e, onRetry: () => ref.invalidate(inboxProvider))),
      data: (all) {
        final match = all.where((c) => c.conversationId == conversationId).firstOrNull;
        if (match == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Conversation unavailable',
              message: 'This conversation is no longer available.',
            ),
          );
        }
        return _ChatView(
          conversationId: conversationId,
          args: ChatRouteArgs(
            matchId: match.matchId,
            otherUserId: match.otherUserId,
            otherName: match.otherDisplayName,
            otherPhoto: match.otherPhoto,
          ),
        );
      },
    );
  }
}

class _ChatView extends ConsumerStatefulWidget {
  const _ChatView({required this.conversationId, required this.args});

  final String conversationId;
  final ChatRouteArgs args;

  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  ChatArgs get _key => (conversationId: widget.conversationId, otherUserId: widget.args.otherUserId);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // List is reversed: "end" of the scroll is the oldest message.
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        ref.read(chatControllerProvider(_key).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    setState(() {});
    ref.read(chatControllerProvider(_key).notifier).send(text);
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _openProfile() => context.push(Routes.user(widget.args.otherUserId));

  Future<void> _menu(String action) async {
    final name = widget.args.otherName;
    switch (action) {
      case 'profile':
        _openProfile();
      case 'unmatch':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Unmatch $name?'),
            content: const Text('This removes the match and your conversation for both of you. It can’t be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Unmatch'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await ref.read(chatRepositoryProvider).unmatch(widget.args.matchId);
          await ref.read(inboxProvider.notifier).refresh();
          if (mounted) context.pop();
        } catch (e) {
          if (mounted) showSnack(context, e);
        }
      case 'block':
        if (await confirmAndBlock(context, ref, userId: widget.args.otherUserId, name: name) && mounted) context.pop();
      case 'report':
        if (await showReportSheet(context, ref, userId: widget.args.otherUserId, name: name) && mounted) context.pop();
    }
  }

  Future<void> _messageActions(ChatMessage m, bool mine) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy text'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (!mine)
              ListTile(
                leading: Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.error),
                title: const Text('Report this message'),
                onTap: () => Navigator.pop(context, 'report'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body ?? ''));
      if (mounted) showSnack(context, 'Copied');
    } else if (action == 'report') {
      final reported = await showReportSheet(
        context,
        ref,
        userId: widget.args.otherUserId,
        name: widget.args.otherName,
        messageId: m.id,
      );
      if (reported && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider(_key));
    final controller = ref.read(chatControllerProvider(_key).notifier);
    final myId = controller.myId;
    final theme = Theme.of(context);

    // Read receipt shows on my newest sent message only.
    final lastMine = state.messages.where((m) => m.senderId == myId && m.delivery == DeliveryState.sent).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _openProfile,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                ProfileAvatar(storagePath: widget.args.otherPhoto, size: 38),
                const SizedBox(width: 10),
                Flexible(child: Text(widget.args.otherName, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'profile', child: Text('View profile')),
              const PopupMenuItem(value: 'unmatch', child: Text('Unmatch')),
              const PopupMenuItem(value: 'block', child: Text('Block')),
              const PopupMenuItem(value: 'report', child: Text('Report')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Builder(builder: (context) {
                if (state.isLoading && state.messages.isEmpty) return const LoadingView();
                if (state.error != null && state.messages.isEmpty) {
                  return ErrorView(error: state.error!, onRetry: controller.retryInitial);
                }
                if (state.messages.isEmpty) {
                  return EmptyState(
                    icon: Icons.waving_hand_outlined,
                    title: 'Say hi to ${widget.args.otherName}',
                    message: 'Ask about something on their profile. Good openers are specific.',
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  itemCount: state.messages.length + (state.isLoadingMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == state.messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    final m = state.messages[i];
                    final older = i + 1 < state.messages.length ? state.messages[i + 1] : null;
                    final showDay = older == null || dayLabel(older.createdAt) != dayLabel(m.createdAt);
                    final mine = m.senderId == myId;
                    final isRead = mine &&
                        m.id == lastMine?.id &&
                        state.otherReadAt != null &&
                        !state.otherReadAt!.isBefore(m.createdAt);
                    return Column(
                      children: [
                        if (showDay)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(dayLabel(m.createdAt), style: theme.textTheme.labelMedium),
                          ),
                        _Bubble(
                          message: m,
                          mine: mine,
                          showStatus: mine && (m.id == lastMine?.id || m.delivery != DeliveryState.sent),
                          isRead: isRead,
                          onRetry: () => controller.retry(m),
                          onDiscard: () => controller.discardFailed(m),
                          onLongPress: m.delivery == DeliveryState.sent ? () => _messageActions(m, mine) : null,
                        ),
                      ],
                    );
                  },
                );
              }),
            ),
            _Composer(controller: _input, onSend: _send, onChanged: () => setState(() {})),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.showStatus,
    required this.isRead,
    required this.onRetry,
    required this.onDiscard,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool mine;
  final bool showStatus;
  final bool isRead;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = message.delivery == DeliveryState.failed;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(mine ? 20 : 6),
      bottomRight: Radius.circular(mine ? 6 : 20),
    );

    final status = switch (message.delivery) {
      DeliveryState.sending => 'Sending…',
      DeliveryState.failed => 'Not sent',
      DeliveryState.sent => isRead ? 'Read' : 'Sent',
    };

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: onLongPress,
                child: Opacity(
                  opacity: message.delivery == DeliveryState.sending ? 0.7 : 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: mine && !failed ? AppColors.brandGradient : null,
                      color: failed
                          ? theme.colorScheme.errorContainer
                          : (mine ? null : theme.colorScheme.surfaceContainerHighest),
                      borderRadius: radius,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          message.body ?? '',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: failed
                                ? theme.colorScheme.onErrorContainer
                                : (mine ? Colors.white : theme.colorScheme.onSurface),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          messageTime(message.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: mine && !failed ? Colors.white70 : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (showStatus)
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 4),
                  child: failed
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded, size: 14, color: theme.colorScheme.error),
                            const SizedBox(width: 4),
                            Text(status, style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                            TextButton(onPressed: onRetry, child: const Text('Retry')),
                            TextButton(onPressed: onDiscard, child: const Text('Delete')),
                          ],
                        )
                      : Text(status, style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend = controller.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('chat-input'),
              controller: controller,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                hintText: 'Type a message',
                counterText: '',
                contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: canSend ? onSend : null,
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}
