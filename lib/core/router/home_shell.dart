import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../widgets/glass.dart';

import '../../features/ads/ads_service.dart';
import '../../features/chat/application/chat_controllers.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/notifications/notification_center.dart';
import '../../features/profile/application/profile_providers.dart';
import '../../features/notifications/push_service.dart';
import '../../features/permissions/permissions_screen.dart';
import '../../features/profile/data/location_service.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/moments/application/moments_controller.dart';
import '../../features/support/support_prompt.dart';
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
      // After a week with the app, a gentle "help the creator" (once).
      await noteSupportAppOpened();
      await Future<void>.delayed(const Duration(seconds: 4));
      if (mounted) await maybeAskForSupport(SupportMoment.regular);
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
      // New moments from matches (and expired ones gone).
      ref.read(momentsProvider.notifier).refresh().ignore();
    }
  }

  void _touch() => ref.read(profileRepositoryProvider).touchLastActive().ignore();

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(totalUnreadProvider);
    final newMatches = ref.watch(inboxProvider.select((v) => v.valueOrNull?.where((c) => !c.hasMessages).length ?? 0));

    final theme = Theme.of(context);
    // Tabs sit on the glowing glass backdrop: their own backgrounds and app
    // bars are transparent, and the tab bar is frosted glass over the content.
    final glassTheme = theme.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
    );
    return Scaffold(
      extendBody: true, // content scrolls behind the glass tab bar
      body: GlassBackground(
        child: Theme(data: glassTheme, child: widget.shell),
      ),
      bottomNavigationBar: GlassSurface(
        blur: 24,
        strength: 1.1,
        shadow: false,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
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
      ),
    );
  }
}

/// Keeps every tab alive (like an IndexedStack) but crossfades between them
/// instead of cutting. The active tab is always on top; a tab that has
/// finished fading out is taken offstage, so it neither paints nor gets taps.
class FadingBranchContainer extends StatelessWidget {
  const FadingBranchContainer({super.key, required this.currentIndex, required this.children});

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Inactive tabs first, active tab last (= on top). Keys keep each tab's state.
    final order = [
      for (var i = 0; i < children.length; i++)
        if (i != currentIndex) i,
      currentIndex,
    ];
    return Stack(
      fit: StackFit.expand,
      children: [for (final i in order) _Branch(key: ValueKey(i), active: i == currentIndex, child: children[i])],
    );
  }
}

class _Branch extends StatefulWidget {
  const _Branch({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_Branch> createState() => _BranchState();
}

class _BranchState extends State<_Branch> {
  /// False once an inactive tab has fully faded out.
  late bool _onstage = widget.active;

  @override
  void didUpdateWidget(_Branch old) {
    super.didUpdateWidget(old);
    if (widget.active) _onstage = true;
  }

  @override
  Widget build(BuildContext context) {
    // The fade lives OUTSIDE TickerMode: muting a hidden tab's animations must
    // never freeze its own fade-out (that left old tabs covering new ones).
    return Offstage(
      offstage: !_onstage,
      child: AnimatedOpacity(
        opacity: widget.active ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        onEnd: () {
          if (!widget.active && mounted) setState(() => _onstage = false);
        },
        child: IgnorePointer(
          ignoring: !widget.active,
          child: ExcludeFocus(
            excluding: !widget.active,
            child: TickerMode(enabled: widget.active, child: widget.child),
          ),
        ),
      ),
    );
  }
}
