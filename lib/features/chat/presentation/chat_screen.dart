import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/permissions/permission_gate.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/state_views.dart';
import '../../safety/presentation/safety_actions.dart';
import '../../notifications/notification_center.dart';
import '../application/chat_controllers.dart';
import 'conversation_actions.dart';
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
    // While this chat is open, new messages in it don't trigger a top banner.
    WidgetsBinding.instance.addPostFrameCallback((_) => _active.state = widget.conversationId);
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

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    ref.read(chatControllerProvider(_key).notifier).send(text);
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final permission = source == ImageSource.camera ? AppPermission.camera : AppPermission.photos;
    if (!await PermissionGate.request(context, permission) || !mounted) return;
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 90);
      if (file == null) return;
      await ref.read(chatControllerProvider(_key).notifier).sendPhoto(await file.readAsBytes());
      final error = ref.read(chatControllerProvider(_key)).error;
      if (error != null && mounted) showSnack(context, error.message, isError: true);
    } catch (e) {
      if (mounted) showSnack(context, e);
    }
  }

  void _openProfile() => context.push(Routes.user(widget.args.otherUserId));

  Future<void> _menu(String action) async {
    final name = widget.args.otherName;
    switch (action) {
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
        messageBody: m.body,
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
              const PopupMenuItem(value: 'delete', child: Text('Delete chat history')),
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
            const _LocalOnlyNotice(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Builder(
                  key: ValueKey(
                    state.messages.isNotEmpty
                        ? 'list'
                        : state.isLoading
                        ? 'loading'
                        : state.error != null
                        ? 'error'
                        : 'empty',
                  ),
                  builder: (context) {
                    if (state.isLoading && state.messages.isEmpty) return const LoadingView();
                    if (state.error != null && state.messages.isEmpty) {
                      return ErrorView(error: state.error!, onRetry: controller.retryInitial);
                    }
                    if (state.messages.isEmpty) {
                      return _Icebreakers(name: widget.args.otherName, onPick: (text) => controller.send(text));
                    }
                    return ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      itemCount: state.messages.length + (state.isLoadingMore ? 1 : 0),
                      // Keyed by clientId so a new message gets its own element
                      // instead of shifting every bubble's state by one.
                      findChildIndexCallback: (key) {
                        final id = (key as ValueKey<String>).value;
                        final i = state.messages.indexWhere((m) => m.clientId == id);
                        return i < 0 ? null : i;
                      },
                      itemBuilder: (context, i) {
                        if (i == state.messages.length) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          );
                        }
                        final m = state.messages[i];
                        final older = i + 1 < state.messages.length ? state.messages[i + 1] : null;
                        final showDay = older == null || dayLabel(older.createdAt) != dayLabel(m.createdAt);
                        final mine = m.senderId == myId;
                        final isRead =
                            mine &&
                            m.id == lastMine?.id &&
                            state.otherReadAt != null &&
                            !state.otherReadAt!.isBefore(m.createdAt);
                        return _MessageEntrance(
                          key: ValueKey(m.clientId),
                          animate: m.createdAt.isAfter(_openedAt),
                          mine: mine,
                          child: Column(
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
                                onDiscard: () async {
                                  final ok = await confirmAction(
                                    context,
                                    title: 'Delete this message?',
                                    message: 'It wasn’t sent, so only you can see it.',
                                    confirmLabel: 'Delete',
                                    destructive: true,
                                  );
                                  if (ok) controller.discardFailed(m);
                                },
                                onLongPress: m.delivery == DeliveryState.sent ? () => _messageActions(m, mine) : null,
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
            _Composer(controller: _input, onSend: _send, onPhoto: _pickPhoto),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-style reminder of where the chat lives.
class _LocalOnlyNotice extends StatelessWidget {
  const _LocalOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'End-to-end encrypted. Messages and photos are saved only on your phones.',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onPrimaryContainer),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// First-message helpers: one tap sends a friendly opener.
class _Icebreakers extends StatelessWidget {
  const _Icebreakers({required this.name, required this.onPick});
  final String name;
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: AppSpacing.sm),
            Text('Say hi to $name', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Tap an opener to send it, or write your own.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [for (final o in _openers) ActionChip(label: Text(o), onPressed: () => onPick(o))],
            ),
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
                        if (message.kind == MessageKind.image)
                          _PhotoContent(path: message.localPath)
                        else
                          Text(
                            message.body ?? '',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: failed
                                  ? theme.colorScheme.onErrorContainer
                                  : (mine ? Colors.white : theme.colorScheme.onSurface),
                            ),
                          ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.encrypted) ...[
                              Icon(
                                Icons.lock_rounded,
                                size: 10,
                                semanticLabel: 'End-to-end encrypted',
                                color: mine && !failed ? Colors.white70 : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                            ],
                            Text(
                              messageTime(message.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: mine && !failed ? Colors.white70 : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
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

/// A chat photo saved on this phone; tap for full screen.
class _PhotoContent extends StatelessWidget {
  const _PhotoContent({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final file = path == null || path!.startsWith('memory://') ? null : File(path!);
    if (file == null) {
      return const SizedBox(
        width: 200,
        height: 120,
        child: Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.white70)),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
            body: Center(child: InteractiveViewer(maxScale: 5, child: Image.file(file))),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 300),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: (240 * MediaQuery.devicePixelRatioOf(context)).round(),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                const SizedBox(width: 200, height: 120, child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend, required this.onPhoto});

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(tooltip: 'Send a photo', onPressed: onPhoto, icon: const Icon(Icons.add_photo_alternate_outlined)),
          Expanded(
            child: TextField(
              key: const Key('chat-input'),
              controller: controller,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Type a message',
                counterText: '',
                contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Only the send button rebuilds as you type.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => IconButton.filled(
              tooltip: 'Send',
              onPressed: value.text.trim().isNotEmpty ? onSend : null,
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.send_rounded),
            ),
          ),
        ],
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.animate ? 0 : 1,
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same tree shape before and after, so finishing never remounts the bubble.
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: Offset(widget.mine ? 0.08 : -0.08, 0.25), end: Offset.zero).animate(_curve),
        child: SizeTransition(sizeFactor: _curve, axisAlignment: -1, child: widget.child),
      ),
    );
  }
}
