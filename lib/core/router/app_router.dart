import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/auth_screens.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/chat/presentation/conversations_screen.dart';
import '../../features/discovery/presentation/discover_screen.dart';
import '../../features/legal/legal_screen.dart';
import '../../features/likes/presentation/likes_screen.dart';
import '../../features/matches/presentation/matches_screen.dart';
import '../../features/notifications/activity_screen.dart';
import '../../features/permissions/permissions_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/application/profile_providers.dart';
import '../../features/profile/domain/profile_models.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/my_profile_screen.dart';
import '../../features/profile/presentation/profile_detail_screen.dart';
import '../../features/profile/presentation/verification_screen.dart';
import '../../features/settings/presentation/about_screen.dart';
import '../../features/settings/presentation/settings_screens.dart';
import '../supabase/supabase_providers.dart';
import 'home_shell.dart';

class Routes {
  const Routes._();
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const onboarding = '/onboarding';
  static const discover = '/discover';
  static const likes = '/likes';
  static const matches = '/matches';
  static const chats = '/chats';
  static const profile = '/profile';
  static const editProfile = '/profile/edit';
  static const verify = '/profile/verify';
  static const activity = '/activity';
  static const permissions = '/permissions';
  static const settings = '/settings';
  static const notificationSettings = '/settings/notifications';
  static const privacySettings = '/settings/privacy';
  static const blockedUsers = '/settings/blocked';
  static const about = '/settings/about';

  static String chat(String conversationId) => '/chat/$conversationId';
  static String user(String userId) => '/user/$userId';

  static const _signedOut = {welcome, signIn, signUp, forgotPassword};
}

/// Arguments passed to the chat route.
class ChatRouteArgs {
  const ChatRouteArgs({
    required this.matchId,
    required this.otherUserId,
    required this.otherName,
    this.otherPhoto,
    this.draft,
    this.sendDraft = false,
  });
  final String matchId;
  final String otherUserId;
  final String otherName;
  final String? otherPhoto;

  /// Text to start with in the message box (e.g. a reply to a moment).
  final String? draft;

  /// Send [draft] straight away instead of leaving it in the box.
  final bool sendDraft;
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Re-runs the router redirect whenever auth or profile state changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._ref) {
    _ref.listen(authStateProvider, (_, next) {
      if (next.valueOrNull?.event == AuthChangeEvent.passwordRecovery) recoveringPassword = true;
      if (next.valueOrNull?.event == AuthChangeEvent.signedOut) recoveringPassword = false;
      notifyListeners();
    });
    _ref.listen(myProfileProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
  bool recoveringPassword = false;

  void passwordResetDone() {
    recoveringPassword = false;
    notifyListeners();
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final loc = state.matchedLocation;
    // Legal documents are readable by everyone, signed in or not.
    if (loc.startsWith('/legal/')) return null;
    final signedIn = _ref.read(supabaseClientProvider).auth.currentSession != null;

    if (!signedIn) return Routes._signedOut.contains(loc) ? null : Routes.welcome;
    if (recoveringPassword) return loc == Routes.resetPassword ? null : Routes.resetPassword;

    final profile = _ref.read(myProfileProvider);
    // `isLoading` also covers a reload after switching accounts, so we never
    // route on the previous user's (stale) profile.
    if (profile.isLoading || !profile.hasValue) return loc == Routes.splash ? null : Routes.splash;

    final p = profile.value;
    if (p == null || !p.onboardingCompleted) return loc == Routes.onboarding ? null : Routes.onboarding;

    if (Routes._signedOut.contains(loc) ||
        loc == Routes.splash ||
        loc == Routes.onboarding ||
        loc == Routes.resetPassword) {
      return Routes.discover;
    }
    return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: refresh.redirect,
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.signUp, builder: (_, _) => const SignUpScreen()),
      GoRoute(path: Routes.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(
        path: Routes.resetPassword,
        builder: (_, _) => ResetPasswordScreen(onDone: refresh.passwordResetDone),
      ),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: '/legal/:doc',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => LegalScreen(doc: LegalDoc.fromSlug(state.pathParameters['doc']!) ?? LegalDoc.terms),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => HomeShell(shell: shell),
        navigatorContainerBuilder: (context, shell, children) =>
            FadingBranchContainer(currentIndex: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.discover, builder: (_, _) => const DiscoverScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.likes, builder: (_, _) => const LikesScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.matches, builder: (_, _) => const MatchesScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.chats, builder: (_, _) => const ConversationsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.profile, builder: (_, _) => const MyProfileScreen())],
          ),
        ],
      ),
      GoRoute(path: Routes.verify, parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const VerificationScreen()),
      GoRoute(path: Routes.activity, parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const ActivityScreen()),
      GoRoute(
        path: Routes.permissions,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, state) =>
            MaterialPage(key: state.pageKey, fullscreenDialog: true, child: const PermissionsScreen()),
      ),
      GoRoute(
        path: Routes.editProfile,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/chat/:conversationId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) =>
            ChatScreen(conversationId: state.pathParameters['conversationId']!, args: state.extra as ChatRouteArgs?),
      ),
      GoRoute(
        path: '/user/:userId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) {
          final extra = state.extra;
          return ProfileDetailScreen(
            userId: state.pathParameters['userId']!,
            initial: extra is ProfileDetailArgs ? extra.card : (extra is ProfileCard ? extra : null),
            actions: extra is ProfileDetailArgs ? extra.actions : ProfileDetailActions.none,
          );
        },
      ),
      GoRoute(
        path: Routes.settings,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const SettingsScreen(),
        routes: [
          GoRoute(path: 'notifications', builder: (_, _) => const NotificationSettingsScreen()),
          GoRoute(path: 'privacy', builder: (_, _) => const PrivacySettingsScreen()),
          GoRoute(path: 'blocked', builder: (_, _) => const BlockedUsersScreen()),
          GoRoute(path: 'about', builder: (_, _) => const AboutScreen()),
        ],
      ),
    ],
  );
});
