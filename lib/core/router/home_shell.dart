import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ads/ads_service.dart';
import '../../features/chat/application/chat_controllers.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/notifications/notification_center.dart';
import '../../features/profile/application/profile_providers.dart';
import '../../features/notifications/push_service.dart';
import '../../features/permissions/permissions_screen.dart';
import '../../features/profile/data/location_service.dart';
import '../../features/profile/data/profile_repository.dart';
import 'app_router.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _touch();
      // Start listening for new matches/messages (top banners + bell).
      ref.read(notificationCenterProvider);
      // One prompt at a time: notifications + location first, then ad consent.
      if (await shouldShowPermissionsIntro() && mounted) await context.push(Routes.permissions);
      await ref.read(pushServiceProvider).registerForCurrentUser();
      // Keep "people near you" accurate: refresh the location if already allowed.
      ref.read(locationServiceProvider).refreshIfAllowed().ignore();
      // Publish this phone's public key so matches can send encrypted messages.
      publishMyChatKey(
        ref.read(chatCryptoProvider),
        ref.read(chatRepositoryProvider),
      ).catchError((Object e) => debugPrint('Chat key publish failed: $e'));
      if (mounted) await ref.read(adsReadyProvider.notifier).start();
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
      // Picks up approvals/rejections made while the app was in the background.
      ref.read(myProfileProvider.notifier).refresh().ignore();
    }
  }

  void _touch() => ref.read(profileRepositoryProvider).touchLastActive().ignore();

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(totalUnreadProvider);
    final newMatches = ref.watch(inboxProvider.select((v) => v.valueOrNull?.where((c) => !c.hasMessages).length ?? 0));

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

/// Keeps every tab alive (like an IndexedStack) but crossfades between them
/// instead of cutting.
class FadingBranchContainer extends StatelessWidget {
  const FadingBranchContainer({super.key, required this.currentIndex, required this.children});

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [for (var i = 0; i < children.length; i++) _Branch(active: i == currentIndex, child: children[i])],
    );
  }
}

class _Branch extends StatelessWidget {
  const _Branch({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeFocus(
        excluding: !active,
        child: TickerMode(
          // Hidden tabs pause their animations.
          enabled: active,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: child,
          ),
        ),
      ),
    );
  }
}
