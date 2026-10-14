import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/application/chat_controllers.dart';
import '../../features/notifications/push_service.dart';
import '../../features/profile/data/profile_repository.dart';

/// Bottom navigation: Discover · Likes · Matches · Chats · Profile.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _touch();
      ref.read(pushServiceProvider).registerForCurrentUser(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _touch();
      ref.read(inboxProvider.notifier).refresh();
    }
  }

  void _touch() => ref.read(profileRepositoryProvider).touchLastActive().ignore();

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(totalUnreadProvider);
    final newMatches = ref.watch(inboxProvider.select(
      (v) => v.valueOrNull?.where((c) => !c.hasMessages).length ?? 0,
    ));

    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: (i) => widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.local_fire_department_outlined),
            selectedIcon: Icon(Icons.local_fire_department_rounded),
            label: 'Discover',
          ),
          const NavigationDestination(
            icon: Icon(Icons.favorite_outline_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Likes',
          ),
          NavigationDestination(
            icon: Badge(isLabelVisible: newMatches > 0, child: const Icon(Icons.people_outline_rounded)),
            selectedIcon: const Icon(Icons.people_rounded),
            label: 'Matches',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: 'Chats',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
