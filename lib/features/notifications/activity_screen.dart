import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/love_ui.dart';
import '../../core/widgets/profile_photo.dart';
import '../../core/widgets/state_views.dart';
import 'notification_center.dart';

/// Bell icon with an unread dot, for app bars.
class ActivityBell extends ConsumerWidget {
  const ActivityBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadActivityProvider);
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.push(Routes.activity),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  late final NotificationCenter _center = ref.read(notificationCenterProvider.notifier);

  @override
  void initState() {
    super.initState();
    _center; // read while the widget is mounted
  }

  @override
  void dispose() {
    // Opening the list counts as seeing everything in it.
    _center.markAllRead();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(notificationCenterProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: const Text('Notifications'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(notificationCenterProvider.notifier).clear(),
              child: const Text('Clear'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'All caught up',
              message: 'New matches, likes and messages will show up here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = items[i];
                return SoftCard(
                  padding: const EdgeInsets.all(12),
                  onTap: item.route == null ? null : () => context.push(item.route!),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (item.photo != null)
                            ProfileAvatar(storagePath: item.photo, size: 44)
                          else
                            Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppColors.brandGradient,
                              ),
                              child: Icon(item.type.icon, color: Colors.white, size: 22),
                            ),
                          if (!item.read)
                            Positioned(
                              right: -1,
                              top: -1,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: AppColors.rose,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: theme.colorScheme.surface, width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            Text(
                              item.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(shortTimeAgo(item.at), style: theme.textTheme.labelSmall),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
