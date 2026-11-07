import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/love_ui.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_views.dart';
import '../../safety/presentation/safety_actions.dart';
import '../../notifications/notification_center.dart';
import '../../support/support_prompt.dart';
import '../application/chat_controllers.dart';
import '../data/local_chat_store.dart';
import 'chat_layout.dart';
import 'conversation_actions.dart';
import 'linkified_text.dart';
import 'gif_picker.dart';
import 'view_once_viewer.dart';
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

    // Once the inbox has data, keep using it through reloads and refresh
    // errors so the open chat is never swapped for a spinner/error screen.
    final inbox = ref.watch(inboxProvider);
    final all = inbox.valueOrNull;
    if (all == null) {
      if (inbox.hasError && !inbox.isLoading) {
        return Scaffold(
          appBar: AppBar(),
          body: ErrorView(error: inbox.error!, onRetry: () => ref.invalidate(inboxProvider)),
        );
      }
      return Scaffold(appBar: AppBar(), body: const LoadingView());
    }
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

  /// Messages created after this animate in; history appears instantly.
  final _openedAt = DateTime.now();

  ChatArgs get _key => (conversationId: widget.conversationId, otherUserId: widget.args.otherUserId);

  late final StateController<String?> _active = ref.read(activeConversationProvider.notifier);

  @override
  void initState() {
    super.initState();
    _loadMyFlag();
    // While this chat is open, new messages in it don't trigger a top banner.
    WidgetsBinding.instance.addPostFrameCallback((_) => _active.state = widget.conversationId);
    // Lets the other person see "typing…" (nothing is stored).
    _input.addListener(_onTyping);
    final draft = widget.args.draft?.trim();
    if (draft != null && draft.isNotEmpty) {
      if (widget.args.sendDraft) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(chatControllerProvider(_key).notifier).send(draft);
          noteSupportMessageSent();
        });
      } else {
        _input.text = draft;
      }
    }
    _scroll.addListener(() {
      // List is reversed: "end" of the scroll is the oldest message.
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        ref.read(chatControllerProvider(_key).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    if (_active.state == widget.conversationId) {
      Future.microtask(() => _active.state = null);
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTyping() => ref.read(chatControllerProvider(_key).notifier).setTyping(_input.text.trim().isNotEmpty);

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(chatControllerProvider(_key).notifier).send(text);
    noteSupportMessageSent();
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  /// Chats are GIF-only, like Tinder: no photos or videos.
  Future<void> _sendGif() async {
    final gif = await pickGif(context);
    if (gif == null || !mounted) return;
    await ref.read(chatControllerProvider(_key).notifier).sendGif(gif);
    noteSupportMessageSent();
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _openProfile() => context.push(Routes.user(widget.args.otherUserId));

  /// The green/red flag I gave this person (only I and the server know it).
  String? _myFlag;

  Future<void> _loadMyFlag() async {
    try {
      final flag = await ref
          .read(supabaseClientProvider)
          .rpc('get_my_flag_for', params: {'p_target': widget.args.otherUserId});
      if (mounted) setState(() => _myFlag = flag as String?);
    } catch (_) {}
  }

  Future<void> _setFlag(String? kind) async {
    final name = widget.args.otherName;
    try {
      await ref
          .read(supabaseClientProvider)
          .rpc('set_profile_flag', params: {'p_target': widget.args.otherUserId, 'p_kind': kind});
      if (!mounted) return;
      setState(() => _myFlag = kind);
      showSnack(context, switch (kind) {
        'green' => 'You gave $name a green flag 💚. Only they see the count.',
        'red' => 'You gave $name a red flag 🚩. Only they see the count. To report something serious, use Report.',
        _ => 'Your flag for $name was taken back.',
      });
    } catch (e) {
      if (mounted) showSnack(context, AppException.from(e).message, isError: true);
    }
  }

  Future<void> _menu(String action) async {
    final name = widget.args.otherName;
    switch (action) {
      case 'green':
        await _setFlag(_myFlag == 'green' ? null : 'green');
      case 'red':
        await _setFlag(_myFlag == 'red' ? null : 'red');
      case 'unflag':
        await _setFlag(null);
      case 'profile':
        _openProfile();
      case 'delete':
        await confirmDeleteHistory(context, ref, conversationId: widget.conversationId, name: name);
      case 'unmatch':
        final ok = await confirmUnmatch(
          context,
          ref,
          matchId: widget.args.matchId,
          conversationId: widget.conversationId,
          name: name,
        );
        if (ok && mounted) context.pop();
      case 'block':
        if (await confirmAndBlock(context, ref, userId: widget.args.otherUserId, name: name) && mounted) context.pop();
      case 'report':
        if (await showReportSheet(context, ref, userId: widget.args.otherUserId, name: name) && mounted) context.pop();
    }
  }

  Future<void> _messageActions(ChatMessage m, bool mine, String? myReaction) async {
    final action = await showModalBottomSheet<String>(
      // Over the whole screen, never under the glass tab bar.
      useRootNavigator: true,
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                '${mine ? 'Sent' : 'Received'} ${dayLabel(m.createdAt)} at ${messageTime(m.createdAt)}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            _ReactionPicker(selected: myReaction, onPick: (e) => Navigator.pop(context, 'react:$e')),
            if (m.kind == MessageKind.text)
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
    if (!mounted || action == null) return;
    if (action.startsWith('react:')) {
      await _react(m, action.substring(6));
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body ?? ''));
      if (mounted) showSnack(context, 'Copied');
    } else if (action == 'report') {
      final reported = await showReportSheet(
        context,
        ref,
        userId: widget.args.otherUserId,
        name: widget.args.otherName,
        messageBody: m.body,
      );
      if (reported && mounted) context.pop();
    }
  }

  Future<void> _react(ChatMessage m, String emoji) async {
    final controller = ref.read(chatControllerProvider(_key).notifier);
    await controller.react(m, emoji);
    final error = ref.read(chatControllerProvider(_key)).error;
    if (error != null && mounted) showSnack(context, 'Couldn’t send your reaction. ${error.message}', isError: true);
  }

  Future<void> _openMedia(ChatController controller, ChatMessage m) async {
    final saved = m.localPath;
    final path = saved == null ? null : await ref.read(localChatStoreProvider).resolveMedia(saved);
    if (!mounted) return;
    if (path == null) {
      final what = m.kind == MessageKind.video ? 'video' : 'photo';
      showSnack(context, 'This $what is no longer on this phone.', isError: true);
      return;
    }
    await openViewOnce(context, m, path: path, onViewed: () => controller.markViewed(m));
  }

  Future<void> _discard(ChatController controller, ChatMessage m) async {
    final ok = await confirmAction(
      context,
      title: 'Delete this message?',
      message: 'It wasn’t sent, so only you can see it.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) controller.discardFailed(m);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider(_key));
    final controller = ref.read(chatControllerProvider(_key).notifier);
    final myId = controller.myId;
    final messages = state.messages;

    // "Seen" / "Sent" shows under my newest delivered message only.
    final lastMine = messages.where((m) => m.senderId == myId && m.delivery == DeliveryState.sent).firstOrNull;
    final seen = lastMine != null && state.otherReadAt != null && !state.otherReadAt!.isBefore(lastMine.createdAt);
    final indexById = {for (var i = 0; i < messages.length; i++) messages[i].clientId: i};

    return PopScope(
      // Leaving a lively chat is a calm moment to ask for support (once).
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) Future.delayed(const Duration(milliseconds: 450), () => maybeAskForSupport(SupportMoment.chatting));
      },
      child: Scaffold(
        appBar: _ChatHeader(
          name: widget.args.otherName,
          photo: widget.args.otherPhoto,
          onTap: _openProfile,
          onMenu: _menu,
          myFlag: _myFlag,
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Builder(
                    key: ValueKey(
                      messages.isNotEmpty
                          ? 'list'
                          : state.isLoading
                          ? 'loading'
                          : state.error != null
                          ? 'error'
                          : 'empty',
                    ),
                    builder: (context) {
                      if (state.isLoading && messages.isEmpty) return const LoadingView();
                      if (state.error != null && messages.isEmpty) {
                        return ErrorView(error: state.error!, onRetry: controller.retryInitial);
                      }
                      if (messages.isEmpty) {
                        return _Icebreakers(
                          name: widget.args.otherName,
                          photo: widget.args.otherPhoto,
                          onViewProfile: _openProfile,
                          onPick: controller.send,
                        );
                      }
                      final atStart = !state.hasMore && !state.isLoadingMore;
                      return ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                        // The extra item is the profile intro (start of chat) or a loader.
                        itemCount: messages.length + 1,
                        // Keyed by clientId so a new message gets its own element
                        // instead of shifting every bubble's state by one.
                        findChildIndexCallback: (key) => key is ValueKey<String> ? indexById[key.value] : null,
                        itemBuilder: (context, i) {
                          if (i == messages.length) {
                            if (atStart) {
                              return _ConversationIntro(
                                name: widget.args.otherName,
                                photo: widget.args.otherPhoto,
                                onViewProfile: _openProfile,
                              );
                            }
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          final m = messages[i];
                          final older = i + 1 < messages.length ? messages[i + 1] : null;
                          final newer = i > 0 ? messages[i - 1] : null;
                          final mine = m.senderId == myId;
                          final timeHeader = needsTimeHeader(older, m);
                          final joinedAbove = !timeHeader && isSameGroup(older, m);
                          final joinedBelow = newer != null && !needsTimeHeader(m, newer) && isSameGroup(m, newer);
                          return _MessageEntrance(
                            key: ValueKey(m.clientId),
                            animate: m.createdAt.isAfter(_openedAt),
                            mine: mine,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (timeHeader) _TimeHeader(time: m.createdAt),
                                if (m.kind == MessageKind.system)
                                  _SystemLine(text: m.body ?? '')
                                else
                                  _MessageRow(
                                    message: m,
                                    mine: mine,
                                    joinedAbove: joinedAbove,
                                    joinedBelow: joinedBelow,
                                    avatar: widget.args.otherPhoto,
                                    status: !mine
                                        ? null
                                        : m.delivery == DeliveryState.failed
                                        ? _Status.failed
                                        : m.clientId == lastMine?.clientId
                                        ? (seen ? _Status.seen : _Status.sent)
                                        : null,
                                    onRetry: () => controller.retry(m),
                                    onDiscard: () => _discard(controller, m),
                                    myId: myId,
                                    onLongPress: m.delivery == DeliveryState.sent
                                        ? () => _messageActions(m, mine, m.reactions[myId])
                                        : null,
                                    // Double-tap a message to ❤️ it, like Instagram.
                                    onDoubleTap: m.delivery == DeliveryState.sent && !m.kind.isMedia
                                        ? () {
                                            HapticFeedback.lightImpact();
                                            _react(m, '❤️');
                                          }
                                        : null,
                                    onReact: (e) => _react(m, e),
                                    onOpenMedia: () => _openMedia(controller, m),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.bottomCenter,
                child: state.otherTyping && messages.isNotEmpty
                    ? _TypingBubble(photo: widget.args.otherPhoto, name: widget.args.otherName)
                    : const SizedBox(width: double.infinity),
              ),
              _Composer(controller: _input, onSend: _send, onGif: _sendGif),
            ],
          ),
        ),
      ),
    );
  }
}

/// Instagram-style top bar: avatar, name and a quiet encryption note.
class _ChatHeader extends StatelessWidget implements PreferredSizeWidget {
  const _ChatHeader({required this.name, required this.photo, required this.onTap, required this.onMenu, this.myFlag});

  /// 'green', 'red' or null: the flag I gave this person.
  final String? myFlag;
  final String name;
  final String? photo;
  final VoidCallback onTap;
  final ValueChanged<String> onMenu;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return AppBar(
      toolbarHeight: 60,
      titleSpacing: 0,
      shape: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4), width: 0.5)),
      title: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            children: [
              ProfileAvatar(storagePath: photo, size: 36),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, size: 11, color: muted),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            'End-to-end encrypted',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(color: muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: onMenu,
          itemBuilder: (_) => [
            CheckedPopupMenuItem(value: 'green', checked: myFlag == 'green', child: const Text('Give a green flag 💚')),
            CheckedPopupMenuItem(value: 'red', checked: myFlag == 'red', child: const Text('Give a red flag 🚩')),
            if (myFlag != null) const PopupMenuItem(value: 'unflag', child: Text('Take back my flag')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'profile', child: Text('View profile')),
            const PopupMenuItem(value: 'delete', child: Text('Delete chat history')),
            const PopupMenuItem(value: 'unmatch', child: Text('Unmatch')),
            const PopupMenuItem(value: 'block', child: Text('Block')),
            const PopupMenuItem(value: 'report', child: Text('Report')),
          ],
        ),
      ],
    );
  }
}

/// Top of the conversation: who this is, and where the chat lives.
class _ConversationIntro extends StatelessWidget {
  const _ConversationIntro({required this.name, required this.photo, required this.onViewProfile});
  final String name;
  final String? photo;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProfileAvatar(storagePath: photo, size: 92),
          const SizedBox(height: 10),
          Text(
            name,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text('You matched on Woops', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onViewProfile,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), visualDensity: VisualDensity.compact),
            child: const Text('View profile'),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 13, color: muted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  'Messages stay on your phones. Photos and videos are view once.',
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// First-message helpers: one tap sends a friendly opener.
class _Icebreakers extends StatelessWidget {
  const _Icebreakers({required this.name, required this.photo, required this.onViewProfile, required this.onPick});
  final String name;
  final String? photo;
  final VoidCallback onViewProfile;
  final ValueChanged<String> onPick;

  static const _openers = [
    'Hey! Your profile made me smile 😊',
    'What does your perfect weekend look like?',
    'Coffee, tea or bubble tea? ☕️',
    'What’s the best trip you’ve ever taken?',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConversationIntro(name: name, photo: photo, onViewProfile: onViewProfile),
            Text(
              'Say hi to $name 👋',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [for (final o in _openers) ActionChip(label: Text(o), onPressed: () => onPick(o))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Today 3:45 PM" between bursts of messages.
class _TimeHeader extends StatelessWidget {
  const _TimeHeader({required this.time});
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        '${dayLabel(time)} ${messageTime(time)}',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: AppSpacing.lg),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

enum _Status { sent, seen, failed }

/// One message: bubble, the sender's avatar at the end of their group,
/// and my delivery status underneath.
class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.mine,
    required this.joinedAbove,
    required this.joinedBelow,
    required this.avatar,
    required this.status,
    required this.onRetry,
    required this.onDiscard,
    required this.myId,
    this.onLongPress,
    this.onDoubleTap,
    this.onReact,
    this.onOpenMedia,
  });

  final ChatMessage message;
  final bool mine;
  final String? myId;
  final VoidCallback? onDoubleTap;
  final ValueChanged<String>? onReact;

  /// Same sender's message right above / below: corners on that side join.
  final bool joinedAbove;
  final bool joinedBelow;
  final String? avatar;
  final _Status? status;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;
  final VoidCallback? onLongPress;
  final VoidCallback? onOpenMedia;

  static const _avatarSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = message.delivery == DeliveryState.failed;
    const big = Radius.circular(22);
    const small = Radius.circular(5);
    final radius = mine
        ? BorderRadius.only(
            topLeft: big,
            bottomLeft: big,
            topRight: joinedAbove ? small : big,
            bottomRight: joinedBelow ? small : big,
          )
        : BorderRadius.only(
            topRight: big,
            bottomRight: big,
            topLeft: joinedAbove ? small : big,
            bottomLeft: joinedBelow ? small : big,
          );

    final emoji = message.kind == MessageKind.text && isBigEmoji(message.body);
    final gif = message.kind == MessageKind.gif ? GifPayload.tryParse(message.body) : null;
    final fg = failed ? theme.colorScheme.onErrorContainer : (mine ? Colors.white : theme.colorScheme.onSurface);

    Widget bubble;
    if (gif != null) {
      // A GIF shows on its own, like a big emoji, with the bubble's corners.
      bubble = ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: 220,
          child: AspectRatio(
            aspectRatio: gif.aspectRatio,
            child: CachedNetworkImage(
              imageUrl: gif.url,
              fit: BoxFit.cover,
              placeholder: (_, _) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
              errorWidget: (_, _, _) => ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(child: Text('GIF')),
              ),
            ),
          ),
        ),
      );
    } else if (emoji) {
      bubble = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(message.body!.trim(), style: const TextStyle(fontSize: 42, height: 1.15)),
      );
    } else {
      bubble = DecoratedBox(
        decoration: BoxDecoration(
          gradient: mine && !failed ? AppColors.brandGradient : null,
          color: failed ? theme.colorScheme.errorContainer : (mine ? null : theme.colorScheme.surfaceContainerHighest),
          borderRadius: radius,
        ),
        child: Padding(
          padding: message.kind.isMedia
              ? const EdgeInsets.fromLTRB(10, 8, 16, 8)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: message.kind.isMedia
              ? _ViewOnceTile(message: message, mine: mine, onOpen: onOpenMedia)
              : LinkifiedText(
                  message.body ?? '',
                  linkColor: mine ? Colors.white : theme.colorScheme.primary,
                  style: theme.textTheme.bodyLarge?.copyWith(color: fg, height: 1.3),
                ),
        ),
      );
    }
    bubble = GestureDetector(
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onLongPress!();
            },
      child: Opacity(opacity: message.delivery == DeliveryState.sending ? 0.6 : 1, child: bubble),
    );
    if (message.reactions.isNotEmpty) {
      final mineEmoji = message.reactions[myId];
      bubble = Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 16), child: bubble),
          Positioned(
            bottom: 0,
            left: mine ? null : 10,
            right: mine ? 10 : null,
            child: _ReactionBadge(
              reactions: message.reactions,
              // Tapping my own reaction takes it back.
              onTap: mineEmoji == null || onReact == null ? null : () => onReact!(mineEmoji),
            ),
          ),
        ],
      );
    }

    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;
    final row = Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[
          // Avatar only on the newest message of their group, like Instagram.
          joinedBelow ? const SizedBox(width: _avatarSize) : ProfileAvatar(storagePath: avatar, size: _avatarSize),
          const SizedBox(width: 8),
        ],
        if (failed) ...[
          Icon(Icons.error_rounded, size: 20, color: theme.colorScheme.error, semanticLabel: 'Not sent'),
          const SizedBox(width: 6),
        ],
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: bubble,
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(top: joinedAbove ? 2 : 8),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          row,
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 6),
              child: status == _Status.failed
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Not sent', style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                        TextButton(
                          onPressed: onRetry,
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: const Text('Retry'),
                        ),
                        TextButton(
                          onPressed: onDiscard,
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: const Text('Delete'),
                        ),
                      ],
                    )
                  : Text(
                      status == _Status.seen ? 'Seen' : 'Sent',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
            ),
        ],
      ),
    );
  }
}

/// A view-once photo/video: no preview, just what it is and its state.
class _ViewOnceTile extends StatelessWidget {
  const _ViewOnceTile({required this.message, required this.mine, this.onOpen});
  final ChatMessage message;
  final bool mine;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final video = message.kind == MessageKind.video;
    // Photos from before view-once stay on the phone and open any time.
    final legacy = !message.viewOnce && message.localPath != null && message.delivery == DeliveryState.sent;
    final canOpen = legacy || (!mine && !message.viewed && message.localPath != null);
    final fg = mine ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final label = video ? 'Video' : 'Photo';
    final state = legacy
        ? 'Tap to view'
        : mine
        ? switch (message.delivery) {
            DeliveryState.sending => 'Sending…',
            DeliveryState.failed => 'Not sent',
            DeliveryState.sent => 'View once',
          }
        : message.viewed
        ? 'Opened'
        : (message.localPath == null ? 'Not available' : 'Tap to view');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: canOpen ? onOpen : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: fg.withValues(alpha: canOpen || mine ? 1 : 0.5), width: 2),
            ),
            child: Icon(
              !legacy && (message.viewed || mine)
                  ? Icons.looks_one_outlined
                  : (video ? Icons.play_arrow_rounded : Icons.photo_outlined),
              color: fg.withValues(alpha: canOpen || mine ? 1 : 0.6),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15),
              ),
              Text(state, style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Instagram-style pill: camera on the left, gallery or "Send" on the right.
class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend, required this.onGif});

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onGif;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Semantics(
                button: true,
                label: 'Send a GIF',
                child: Tooltip(
                  message: 'Send a GIF',
                  child: PressableScale(
                    key: const Key('chat-gif'),
                    onTap: onGif,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
                      child: const Text(
                        'GIF',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const Key('chat-input'),
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: 'Message…',
                    counterText: '',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  ),
                ),
              ),
              // Only this part rebuilds as you type.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: hasText
                        ? TextButton(
                            key: const ValueKey('send'),
                            onPressed: onSend,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(56, 40),
                              foregroundColor: theme.colorScheme.primary,
                              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            child: const Text('Send', semanticsLabel: 'Send'),
                          )
                        : const SizedBox(key: ValueKey('idle'), width: 8, height: 40),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slides and fades in a message that arrived while the chat is open.
class _MessageEntrance extends StatefulWidget {
  const _MessageEntrance({super.key, required this.animate, required this.mine, required this.child});
  final bool animate;
  final bool mine;
  final Widget child;

  @override
  State<_MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<_MessageEntrance> with SingleTickerProviderStateMixin {
  // Only new messages animate; history never creates a controller (creating
  // one later, e.g. in dispose, would look up a ticker on a dead element).
  AnimationController? _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      final c = _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
      _curve = CurvedAnimation(parent: c, curve: Curves.easeOutCubic);
      c.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // History never animates, so skip the transition layers for it entirely.
    // (animate is fixed per message, so the tree shape never changes.)
    if (_controller == null) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: Offset(widget.mine ? 0.06 : -0.06, 0.2), end: Offset.zero).animate(_curve),
        child: SizeTransition(sizeFactor: _curve, axisAlignment: -1, child: widget.child),
      ),
    );
  }
}

/// Quick reactions shown when you long-press a message.
const quickReactions = ['❤️', '😂', '😮', '😢', '😡', '👍'];

class _ReactionPicker extends StatelessWidget {
  const _ReactionPicker({required this.selected, required this.onPick});
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final e in quickReactions)
            Semantics(
              button: true,
              selected: e == selected,
              label: 'React $e',
              child: PressableScale(
                onTap: () => onPick(e),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: e == selected ? theme.colorScheme.primaryContainer : Colors.transparent,
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 28)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The little pill under a bubble with who reacted. Pops in when it changes.
class _ReactionBadge extends StatelessWidget {
  const _ReactionBadge({required this.reactions, this.onTap});
  final Map<String, String> reactions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emojis = reactions.values.toSet().toList();
    final label = emojis.join() + (reactions.length > 1 && emojis.length == 1 ? ' ${reactions.length}' : '');
    return TweenAnimationBuilder<double>(
      key: ValueKey(label),
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))],
          ),
          child: Text(
            label,
            semanticsLabel: 'Reactions: $label',
            style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// "…" bubble while the other person types.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble({required this.photo, required this.name});
  final String? photo;
  final String name;

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dot = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      liveRegion: true,
      label: '${widget.name} is typing',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 12, 6),
        child: Row(
          children: [
            ProfileAvatar(storagePath: widget.photo, size: 28),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22),
              ),
              child: AnimatedBuilder(
                animation: _dots,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                        child: Transform.translate(
                          // Each dot bobs a little after the one before it.
                          offset: Offset(0, -3 * _bob((_dots.value - i * 0.18) % 1)),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _bob(double t) => t < 0.4 ? (t < 0.2 ? t / 0.2 : (0.4 - t) / 0.2) : 0;
}
