import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/app_router.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/profile_photo.dart';
import '../chat/application/chat_controllers.dart';
import '../chat/domain/chat_models.dart';
import '../profile/application/profile_providers.dart';
import '../profile/domain/profile_models.dart';

enum ActivityType {
  message(Icons.chat_bubble_rounded),
  match(Icons.favorite_rounded),
  like(Icons.volunteer_activism_rounded),
  system(Icons.notifications_rounded);

  const ActivityType(this.icon);
  final IconData icon;
}

/// One entry in the notification list (kept on the phone, last 50).
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.at,
    this.route,
    this.photo,
    this.read = false,
  });

  final String id;
  final ActivityType type;
  final String title;
  final String body;
  final DateTime at;
  final String? route;
  final String? photo;
  final bool read;

  ActivityItem asRead() =>
      ActivityItem(id: id, type: type, title: title, body: body, at: at, route: route, photo: photo, read: true);

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'body': body,
    'at': at.toIso8601String(),
    'route': route,
    'photo': photo,
    'read': read,
  };

  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
    id: j['id'] as String,
    type: ActivityType.values.firstWhere((t) => t.name == j['type'], orElse: () => ActivityType.system),
    title: j['title'] as String,
    body: j['body'] as String,
    at: DateTime.parse(j['at'] as String),
    route: j['route'] as String?,
    photo: j['photo'] as String?,
    read: j['read'] as bool? ?? false,
  );
}

/// The chat currently on screen, so we don't announce messages you're reading.
final activeConversationProvider = StateProvider<String?>((ref) => null);

class NotificationCenter extends Notifier<List<ActivityItem>> {
  static const _max = 50;
  Map<String, int> _lastUnread = {};
  bool _primed = false;

  String get _key => 'activity_${ref.read(currentUserIdProvider) ?? 'anon'}';

  @override
  List<ActivityItem> build() {
    ref.watch(currentUserIdProvider);
    _primed = false;
    _lastUnread = {};
    _restore();
    // New matches and messages come from the inbox (relay + local storage).
    ref.listen(inboxProvider, (_, next) {
      final list = next.valueOrNull;
      if (list != null) _onInbox(list);
    }, fireImmediately: true);
    // Review results (ID age check, selfie verification).
    ref.listen(myProfileProvider, (_, next) {
      final p = next.valueOrNull;
      if (p != null) _onProfile(p);
    }, fireImmediately: true);
    _watchReviews();
    return const [];
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final items = (jsonDecode(raw) as List).map((e) => ActivityItem.fromJson(Map<String, dynamic>.from(e as Map)));
      state = [...state, ...items.where((i) => state.every((s) => s.id != i.id))];
    } catch (_) {
      // A corrupt cache just starts empty.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([for (final i in state) i.toJson()]));
    } catch (_) {}
  }

  /// Live updates when a moderator approves or rejects something of mine.
  void _watchReviews() {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final SupabaseClient client;
    try {
      client = ref.read(supabaseClientProvider);
    } catch (_) {
      return; // no backend (tests / misconfigured build): results still arrive on refresh
    }
    void refresh(PostgresChangePayload _) => ref.read(myProfileProvider.notifier).refresh();
    final filter = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid);
    _loadNotices(client);
    final channel = client
        .channel('reviews:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_notices',
          filter: filter,
          callback: (_) => _loadNotices(client),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'verification_requests',
          filter: filter,
          callback: refresh,
        )
        .subscribe();
    ref.onDispose(() => client.removeChannel(channel));
  }

  /// Messages from the safety team (e.g. why a photo was removed).
  Future<void> _loadNotices(SupabaseClient client) async {
    try {
      final rows = (await client.rpc('get_my_notices') as List).map((r) => Map<String, dynamic>.from(r as Map));
      final ids = <String>[];
      for (final r in rows) {
        ids.add(r['id'] as String);
        add(
          ActivityItem(
            id: 'notice-${r['id']}',
            type: ActivityType.system,
            title: r['title'] as String,
            body: r['body'] as String,
            at: DateTime.parse(r['created_at'] as String),
            route: Routes.editProfile,
          ),
        );
      }
      if (ids.isNotEmpty) {
        await client.rpc('mark_notices_read', params: {'p_ids': ids});
        ref.read(myProfileProvider.notifier).refresh().ignore();
      }
    } catch (_) {
      // Older database or offline: try again next launch.
    }
  }

  /// Compares review results with what this phone last saw, so results that
  /// arrived while the app was closed are announced on the next launch.
  Future<void> _onProfile(MyProfile p) async {
    final key = 'reviews_${p.id}';
    final now = {'selfie': p.selfieStatus, 'verified': p.isVerified};
    Map<String, dynamic>? before;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      before = raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      await prefs.setString(key, jsonEncode(now));
    } catch (_) {
      return;
    }
    if (before == null) return; // first run on this phone: nothing to announce

    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (before['verified'] != true && p.isVerified) {
      add(
        ActivityItem(
          id: 'verified-$stamp',
          type: ActivityType.system,
          title: 'You’re verified 💙',
          body: 'Your profile now shows the blue verified badge.',
          at: DateTime.now(),
          route: Routes.profile,
        ),
      );
    } else if (before['selfie'] == 'pending' && p.selfieStatus == 'rejected') {
      add(
        ActivityItem(
          id: 'selfie-no-$stamp',
          type: ActivityType.system,
          title: 'Selfie not approved',
          body: p.selfieRejectReason ?? 'Please try again with good light and your face clearly visible.',
          at: DateTime.now(),
          route: Routes.verify,
        ),
      );
    }
  }

  void _onInbox(List<ConversationSummary> list) {
    final current = {for (final c in list) c.conversationId: c.unreadCount};
    _remind(list);
    if (!_primed) {
      // First load: remember the starting point, don't announce old things.
      _primed = true;
      _lastUnread = current;
      return;
    }
    final active = ref.read(activeConversationProvider);
    for (final c in list) {
      final before = _lastUnread[c.conversationId];
      if (before == null) {
        add(
          ActivityItem(
            id: 'match-${c.matchId}',
            type: ActivityType.match,
            title: 'It’s a match! 💞',
            body: 'You and ${c.otherDisplayName} liked each other. Say hi!',
            at: DateTime.now(),
            route: Routes.chat(c.conversationId),
            photo: c.otherPhoto,
          ),
        );
      } else if (c.unreadCount > before && c.conversationId != active) {
        add(
          ActivityItem(
            id: 'msg-${c.conversationId}-${c.lastMessageAt?.microsecondsSinceEpoch}',
            type: ActivityType.message,
            title: c.otherDisplayName,
            body: c.lastMessageBody == null ? 'New message' : c.previewFor(''),
            at: DateTime.now(),
            route: Routes.chat(c.conversationId),
            photo: c.otherPhoto,
          ),
        );
      }
    }
    _lastUnread = current;
  }

  /// Gentle chat reminders, each sent once: a match nobody has messaged for a
  /// day, or a message from them that has waited a day for my reply. Nothing
  /// older than a week, and at most one banner per check.
  Future<void> _remind(List<ConversationSummary> list) async {
    final myId = ref.read(currentUserIdProvider);
    if (myId == null) return;
    final now = DateTime.now();
    bool due(DateTime t) =>
        now.difference(t) > const Duration(hours: 24) && now.difference(t) < const Duration(days: 7);
    final candidates = <ActivityItem>[];
    for (final c in list) {
      if (!c.hasMessages && due(c.matchedAt)) {
        candidates.add(
          ActivityItem(
            id: 'remind-hi-${c.matchId}',
            type: ActivityType.message,
            title: 'Say hi to ${c.otherDisplayName} 👋',
            body: 'You matched ${shortTimeAgo(c.matchedAt)} ago. A quick hello goes a long way.',
            at: now,
            route: Routes.chat(c.conversationId),
            photo: c.otherPhoto,
          ),
        );
      } else if (c.lastMessageAt != null &&
          c.lastMessageSenderId != null &&
          c.lastMessageSenderId != myId &&
          due(c.lastMessageAt!)) {
        candidates.add(
          ActivityItem(
            id: 'remind-reply-${c.conversationId}-${c.lastMessageAt!.millisecondsSinceEpoch}',
            type: ActivityType.message,
            title: '${c.otherDisplayName} is waiting for your reply',
            body: c.lastMessageBody == null ? 'Pick up where you left off.' : c.previewFor(''),
            at: now,
            route: Routes.chat(c.conversationId),
            photo: c.otherPhoto,
          ),
        );
      }
    }
    if (candidates.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'reminded_$myId';
      final sent = (prefs.getStringList(key) ?? const []).toSet();
      final fresh = candidates.where((i) => !sent.contains(i.id)).toList();
      if (fresh.isEmpty) return; // nothing new: no disk write
      var banner = true;
      for (final item in fresh) {
        add(item, banner: banner);
        banner = false;
        sent.add(item.id);
      }
      // Keep the list small: only recent reminder ids matter.
      await prefs.setStringList(key, sent.toList().reversed.take(200).toList());
    } catch (_) {}
  }

  /// Adds an item and, by default, slides a banner in at the top.
  void add(ActivityItem item, {bool banner = true}) {
    if (state.any((i) => i.id == item.id)) return;
    state = [item, ...state].take(_max).toList();
    _save();
    if (banner) TopBanner.show(item);
  }

  void markAllRead() {
    state = [for (final i in state) i.read ? i : i.asRead()];
    _save();
  }

  void clear() {
    state = const [];
    _save();
  }
}

final notificationCenterProvider = NotifierProvider<NotificationCenter, List<ActivityItem>>(NotificationCenter.new);

final unreadActivityProvider = Provider<int>(
  (ref) => ref.watch(notificationCenterProvider).where((i) => !i.read).length,
);

/// In-app notification that slides down from the top of the screen.
class TopBanner {
  TopBanner._();
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(ActivityItem item) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    hide();
    HapticFeedback.lightImpact();
    final key = GlobalKey<_BannerViewState>();
    late final OverlayEntry entry;
    // Only removes its own entry, so a banner that finishes closing after a
    // newer one appeared never takes the new one down with it.
    entry = OverlayEntry(
      builder: (_) => _BannerView(
        key: key,
        item: item,
        onClose: () {
          if (_entry == entry) hide();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    // Slide back up rather than vanishing.
    _timer = Timer(const Duration(seconds: 4), () => key.currentState?._close() ?? hide());
  }

  static void hide() {
    _timer?.cancel();
    _entry?.remove();
    _entry = null;
  }
}

class _BannerView extends StatefulWidget {
  const _BannerView({super.key, required this.item, required this.onClose});
  final ActivityItem item;
  final VoidCallback onClose;

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))..forward();
  late final _slide = Tween(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _closing = false;

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _c.reverse();
    if (mounted) widget.onClose();
  }

  void _open() {
    final route = widget.item.route;
    widget.onClose();
    final context = rootNavigatorKey.currentContext;
    if (route == null || context == null) return;
    ProviderScope.containerOf(context, listen: false).read(routerProvider).push(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: _slide,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: GestureDetector(
              onTap: _open,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < 0) _close();
              },
              child: Material(
                elevation: 10,
                shadowColor: AppColors.rose.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppRadius.md),
                color: theme.brightness == Brightness.dark ? const Color(0xFF2E1A28) : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (item.photo != null)
                        ProfileAvatar(storagePath: item.photo, size: 42)
                      else
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
                          child: Icon(item.type.icon, color: Colors.white, size: 22),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(item.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            Text(
                              item.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(item.type.icon, color: AppColors.rose, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
