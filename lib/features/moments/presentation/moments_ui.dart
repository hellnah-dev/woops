import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/permissions/permission_gate.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/love_ui.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../../chat/application/chat_controllers.dart';
import '../../profile/application/profile_providers.dart';
import '../../safety/presentation/safety_actions.dart';
import '../application/moments_controller.dart';
import '../data/moments_repository.dart';

/// Backgrounds for text-only moments.
const momentStyles = <Gradient>[
  AppColors.brandGradient,
  LinearGradient(colors: [Color(0xFF7F5AF0), Color(0xFFFF7EB3)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  LinearGradient(colors: [Color(0xFFFF9A62), Color(0xFFFFD86F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  LinearGradient(colors: [Color(0xFF2CB67D), Color(0xFF7FDBDA)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  LinearGradient(colors: [Color(0xFF3A86FF), Color(0xFF8EC5FC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  LinearGradient(colors: [Color(0xFF232526), Color(0xFF414345)], begin: Alignment.topLeft, end: Alignment.bottomRight),
];

/// The strip of moments at the top of Discover: "Your moment" first, then
/// matches. Hidden until you have a match (moments are only for matches).
class MomentsRow extends ConsumerWidget {
  const MomentsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMatches = (ref.watch(inboxProvider).valueOrNull ?? const []).isNotEmpty;
    final groups = ref.watch(momentGroupsProvider);
    final seen = ref.watch(seenMomentsProvider);
    if (!hasMatches && groups.isEmpty) return const SizedBox.shrink();

    final mine = groups.where((g) => g.isMine).firstOrNull;
    final others = groups.where((g) => !g.isMine).toList();
    return SizedBox(
      height: 96,
      child: ListView(
        key: const Key('moments-row'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 4, vertical: 4),
        children: [
          _Bubble(
            label: 'Your moment',
            avatar: mine?.avatar ?? ref.watch(myAvatarProvider),
            ring: mine == null ? _Ring.none : _Ring.seen,
            showAdd: true,
            onTap: mine == null ? () => showNewMomentSheet(context) : () => openMoments(context, [mine], 0),
            onAdd: () => showNewMomentSheet(context),
          ),
          for (var i = 0; i < others.length; i++)
            _Bubble(
              label: others[i].name,
              avatar: others[i].avatar,
              ring: others[i].hasUnseen(seen) ? _Ring.unseen : _Ring.seen,
              onTap: () => openMoments(context, others, i),
            ),
        ],
      ),
    );
  }
}

/// My first profile photo, for "Your moment" before I've posted one.
final myAvatarProvider = Provider<String?>((ref) => ref.watch(myProfileProvider).valueOrNull?.primaryPhoto);

enum _Ring { none, unseen, seen }

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.label,
    required this.avatar,
    required this.ring,
    required this.onTap,
    this.showAdd = false,
    this.onAdd,
  });

  final String label;
  final String? avatar;
  final _Ring ring;
  final VoidCallback onTap;
  final bool showAdd;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: ring == _Ring.unseen ? '$label, new moment' : label,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: ring == _Ring.unseen ? AppColors.brandGradient : null,
                      color: ring == _Ring.seen ? theme.colorScheme.outlineVariant : null,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.scaffoldBackgroundColor),
                      child: ProfileAvatar(storagePath: avatar, size: 54),
                    ),
                  ),
                  if (showAdd)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: GestureDetector(
                        onTap: onAdd,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.brandGradient,
                            border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                          ),
                          child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: ring == _Ring.unseen ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Posting
// -----------------------------------------------------------------------------
Future<void> showNewMomentSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => const _NewMomentSheet(),
);

class _NewMomentSheet extends ConsumerStatefulWidget {
  const _NewMomentSheet();

  @override
  ConsumerState<_NewMomentSheet> createState() => _NewMomentSheetState();
}

class _NewMomentSheetState extends ConsumerState<_NewMomentSheet> {
  final _text = TextEditingController();
  int _style = 0;
  Uint8List? _photo;
  bool _posting = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final ok = await PermissionGate.request(
      context,
      source == ImageSource.camera ? AppPermission.camera : AppPermission.photos,
    );
    if (!ok || !mounted) return;
    try {
      final f = await ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 90);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {
      if (!mounted) return;
      showSnack(context, 'Couldn’t open your ${source == ImageSource.camera ? 'camera' : 'photos'}.', isError: true);
    }
  }

  Future<void> _post() async {
    final text = _text.text.trim();
    if (_photo == null && text.isEmpty) return;
    setState(() => _posting = true);
    try {
      final c = ref.read(momentsProvider.notifier);
      if (_photo != null) {
        await c.postPhoto(_photo!, caption: text);
      } else {
        await c.postText(text, style: _style);
      }
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, 'Shared with your matches for 24 hours');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        showSnack(context, AppException.from(e).message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New moment', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                'Only your matches see it. It disappears after 24 hours.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              AspectRatio(
                // Smaller while typing, so the button stays above the keyboard.
                aspectRatio: insets > 0 ? 2.4 : 4 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: _photo != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_photo!, fit: BoxFit.cover),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: IconButton.filledTonal(
                                tooltip: 'Remove photo',
                                onPressed: () => setState(() => _photo = null),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          ],
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(gradient: momentStyles[_style]),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _text,
                                builder: (context, v, _) => Text(
                                  v.text.trim().isEmpty ? 'What’s your vibe today?' : v.text,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: v.text.trim().isEmpty ? 0.7 : 1),
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_photo == null)
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      for (var i = 0; i < momentStyles.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Semantics(
                            button: true,
                            selected: i == _style,
                            label: 'Background ${i + 1}',
                            child: GestureDetector(
                              onTap: () => setState(() => _style = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: momentStyles[i],
                                  border: Border.all(
                                    color: i == _style ? theme.colorScheme.onSurface : Colors.transparent,
                                    width: 2.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Take a photo',
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                      ),
                      IconButton(
                        tooltip: 'Choose a photo',
                        onPressed: () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                key: const Key('moment-text'),
                controller: _text,
                maxLength: 200,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: _photo == null ? 'Say something…' : 'Add a caption (optional)'),
              ),
              const SizedBox(height: AppSpacing.xs),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _text,
                builder: (context, v, _) => FilledButton(
                  key: const Key('moment-post'),
                  onPressed: _posting || (_photo == null && v.text.trim().isEmpty) ? null : _post,
                  child: _posting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Share with my matches'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Viewing
// -----------------------------------------------------------------------------
/// Plays [groups] full screen, starting with [startGroup].
Future<void> openMoments(BuildContext context, List<MomentGroup> groups, int startGroup) =>
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => _MomentViewer(groups: groups, startGroup: startGroup),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
        ),
      ),
    );

class _MomentViewer extends ConsumerStatefulWidget {
  const _MomentViewer({required this.groups, required this.startGroup});
  final List<MomentGroup> groups;
  final int startGroup;

  @override
  ConsumerState<_MomentViewer> createState() => _MomentViewerState();
}

class _MomentViewerState extends ConsumerState<_MomentViewer> with SingleTickerProviderStateMixin {
  static const _duration = Duration(seconds: 6);
  late int _group = widget.startGroup;
  int _index = 0;
  late final AnimationController _progress = AnimationController(vsync: this, duration: _duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();

  MomentGroup get _current => widget.groups[_group];
  Moment get _moment => _current.moments[_index];

  @override
  void initState() {
    super.initState();
    // Start with the first one I haven't seen in this person's moments.
    final seen = ref.read(seenMomentsProvider);
    final firstUnseen = _current.moments.indexWhere((m) => !seen.contains(m.id));
    _index = firstUnseen < 0 ? 0 : firstUnseen;
    _replyFocus.addListener(() => _replyFocus.hasFocus ? _progress.stop() : _progress.forward());
    // After the first frame: providers can't change while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _show();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _show() {
    ref.read(seenMomentsProvider.notifier).markSeen(_moment.id);
    _progress.forward(from: 0);
  }

  void _next() {
    if (_index + 1 < _current.moments.length) {
      setState(() => _index++);
    } else if (_group + 1 < widget.groups.length) {
      setState(() {
        _group++;
        _index = 0;
      });
    } else {
      Navigator.pop(context);
      return;
    }
    _show();
  }

  void _previous() {
    if (_index > 0) {
      setState(() => _index--);
    } else if (_group > 0) {
      setState(() {
        _group--;
        _index = _current.moments.length - 1;
      });
    }
    _show();
  }

  Future<void> _menu() async {
    _progress.stop();
    final m = _moment;
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.isMine)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                title: const Text('Delete this moment'),
                onTap: () => Navigator.pop(context, 'delete'),
              )
            else
              ListTile(
                leading: Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.error),
                title: Text('Report ${m.displayName}'),
                onTap: () => Navigator.pop(context, 'report'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'delete') {
      final ok = await confirmAction(
        context,
        title: 'Delete this moment?',
        message: 'Your matches won’t see it any more.',
        confirmLabel: 'Delete',
        destructive: true,
      );
      if (!ok || !mounted) return _progress.forward();
      await ref.read(momentsProvider.notifier).delete(m).catchError((Object e) {
        if (mounted) showSnack(context, AppException.from(e).message, isError: true);
      });
      if (mounted) Navigator.pop(context);
    } else if (action == 'report') {
      final reported = await showReportSheet(
        context,
        ref,
        userId: m.userId,
        name: m.displayName,
        messageBody: 'Moment: ${m.body ?? '(photo)'}',
      );
      if (!mounted) return;
      if (reported) {
        Navigator.pop(context);
      } else {
        _progress.forward();
      }
    } else {
      _progress.forward();
    }
  }

  /// Replies go to the chat, quoting the moment, end-to-end encrypted like any message.
  void _sendReply() {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final m = _moment;
    final convo = (ref.read(inboxProvider).valueOrNull ?? const []).where((c) => c.otherUserId == m.userId).firstOrNull;
    if (convo == null) {
      showSnack(context, 'You’re no longer matched with ${m.displayName}.', isError: true);
      return;
    }
    final quote = m.body == null ? '📷 photo' : '“${m.body!.length > 60 ? '${m.body!.substring(0, 60)}…' : m.body}”';
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.push(
      Routes.chat(convo.conversationId),
      extra: ChatRouteArgs(
        matchId: convo.matchId,
        otherUserId: convo.otherUserId,
        otherName: convo.otherDisplayName,
        otherPhoto: convo.otherPhoto,
        draft: '↩️ Replied to your moment $quote\n$text',
        sendDraft: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _moment;
    final padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            if (_replyFocus.hasFocus) return _replyFocus.unfocus();
            d.localPosition.dx < MediaQuery.sizeOf(context).width / 3 ? _previous() : _next();
          },
          onLongPressStart: (_) => _progress.stop(),
          onLongPressEnd: (_) => _progress.forward(),
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(m.id),
                  child: _MomentContent(moment: m),
                ),
              ),
              // Top: progress, who and when, menu.
              Positioned(
                top: padding.top + 8,
                left: 10,
                right: 4,
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < _current.moments.length; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: i == _index
                                    ? AnimatedBuilder(
                                        animation: _progress,
                                        builder: (_, _) => LinearProgressIndicator(
                                          value: _progress.value,
                                          minHeight: 3,
                                          backgroundColor: Colors.white30,
                                          color: Colors.white,
                                        ),
                                      )
                                    : LinearProgressIndicator(
                                        value: i < _index ? 1 : 0,
                                        minHeight: 3,
                                        backgroundColor: Colors.white30,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ProfileAvatar(storagePath: m.avatar, size: 34),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            m.isMine ? 'Your moment' : m.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(shortTimeAgo(m.createdAt), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'More',
                          onPressed: _menu,
                          icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Bottom: reply (to someone else's moment) or who can see mine.
              Positioned(
                left: 12,
                right: 12,
                bottom: (MediaQuery.viewInsetsOf(context).bottom > 0 ? 0 : padding.bottom) + 12,
                child: m.isMine
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 14, color: Colors.white70),
                          SizedBox(width: 6),
                          Text(
                            'Only your matches can see this · gone in 24 h',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('moment-reply'),
                              controller: _reply,
                              focusNode: _replyFocus,
                              maxLength: 500,
                              style: const TextStyle(color: Colors.white),
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendReply(),
                              decoration: InputDecoration(
                                hintText: 'Reply to ${m.displayName}…',
                                hintStyle: const TextStyle(color: Colors.white70),
                                counterText: '',
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.14),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: const BorderSide(color: Colors.white54),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: const BorderSide(color: Colors.white54),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: const BorderSide(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Send reply',
                            onPressed: _sendReply,
                            icon: const Icon(Icons.send_rounded, color: Colors.white),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MomentContent extends ConsumerWidget {
  const _MomentContent({required this.moment});
  final Moment moment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caption = moment.body;
    if (!moment.hasPhoto) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: momentStyles[moment.style.clamp(0, momentStyles.length - 1)]),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              caption ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.25),
            ),
          ),
        ),
      );
    }
    final resolver = ref.watch(photoUrlResolverProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          key: ValueKey('${moment.photoPath}#${resolver.sessionTag}'),
          imageUrl: resolver.urlIn(MomentsRepository.bucket, moment.photoPath!),
          cacheKey: 'moment:${moment.photoPath}',
          httpHeaders: resolver.headers,
          fit: BoxFit.contain,
          placeholder: (_, _) => const LoadingView(),
          errorWidget: (_, _, _) => const Center(
            child: Text('This moment is no longer available', style: TextStyle(color: Colors.white70)),
          ),
        ),
        if (caption != null)
          Positioned(
            left: 20,
            right: 20,
            bottom: 110,
            child: Text(
              caption,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
              ),
            ),
          ),
      ],
    );
  }
}
