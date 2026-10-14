import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/data/auth_repository.dart';
import '../../discovery/application/discovery_controller.dart';
import '../../discovery/presentation/filters_sheet.dart';
import '../../legal/legal_screen.dart';
import '../../notifications/push_service.dart';
import '../../profile/data/location_service.dart';
import '../../safety/data/safety_repository.dart';
import '../data/settings_repository.dart';
import '../domain/settings_models.dart';

final privacySettingsProvider = FutureProvider.autoDispose<PrivacySettings>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(settingsRepositoryProvider).fetchPrivacy();
});

final notificationPreferencesProvider = FutureProvider.autoDispose<NotificationPreferences>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(settingsRepositoryProvider).fetchNotifications();
});

final blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUser>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(safetyRepositoryProvider).blockedUsers();
});

Future<void> _open(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showSnack(context, 'Couldn’t open $url', isError: true);
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(pushServiceProvider).unregister();
    await ref.read(authRepositoryProvider).signOut();
  }

  Future<void> _updateLocation(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(locationServiceProvider).updateMyLocation();
      ref.read(discoveryControllerProvider.notifier).load(reset: true);
      if (context.mounted) showSnack(context, 'Location updated');
    } catch (e) {
      if (context.mounted) showSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(supabaseClientProvider).auth.currentUser?.email;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          const _Header('Discovery'),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Discovery preferences'),
            subtitle: const Text('Age, distance, who you see'),
            onTap: () => showFiltersSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.my_location_rounded),
            title: const Text('Update my location'),
            subtitle: const Text('Stored approximately (about 1 km)'),
            onTap: () => _updateLocation(context, ref),
          ),
          const _Header('Account'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            onTap: () => context.push(Routes.notificationSettings),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Privacy'),
            onTap: () => context.push(Routes.privacySettings),
          ),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: const Text('Blocked people'),
            onTap: () => context.push(Routes.blockedUsers),
          ),
          if (email != null)
            ListTile(leading: const Icon(Icons.alternate_email_rounded), title: const Text('Email'), subtitle: Text(email)),
          const _Header('Safety & support'),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Community guidelines'),
            onTap: () => openLegal(context, LegalDoc.guidelines),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            onTap: () => openLegal(context, LegalDoc.privacy),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of service'),
            onTap: () => openLegal(context, LegalDoc.terms),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text('Help & support'),
            subtitle: const Text(Env.supportEmail),
            onTap: () => _open(context, 'mailto:${Env.supportEmail}?subject=Woops%20support'),
          ),
          const _Header(''),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Log out'),
            onTap: () => _logout(context, ref),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('Delete account', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => showDialog<void>(context: context, builder: (_) => const _DeleteAccountDialog()),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1,
              ),
        ),
      );
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _confirm = TextEditingController();
  bool _deleting = false;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() => _deleting = true);
    try {
      await ref.read(pushServiceProvider).unregister();
      await ref.read(settingsRepositoryProvider).deleteAccount();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        showSnack(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _confirm.text.trim().toUpperCase() == 'DELETE' && !_deleting;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This permanently deletes your profile, photos, matches and messages. '
              'It can’t be undone.\n\nIf you just need a break, you can pause your profile in Privacy settings.'),
          const SizedBox(height: 16),
          TextField(
            controller: _confirm,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Type DELETE to confirm'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _deleting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: canDelete ? _delete : null,
          child: _deleting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Delete forever'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, NotificationPreferences next) async {
    try {
      await ref.read(settingsRepositoryProvider).saveNotifications(next);
      ref.invalidate(notificationPreferencesProvider);
    } catch (e) {
      if (context.mounted) showSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: prefs.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(notificationPreferencesProvider)),
        data: (p) => ListView(
          children: [
            if (!PushService.isEnabled)
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('Push notifications aren’t set up in this build'),
                subtitle: Text('Your choices are saved and will apply once they are.'),
              ),
            SwitchListTile(
              title: const Text('New matches'),
              value: p.newMatches,
              onChanged: (v) => _save(context, ref, p.copyWith(newMatches: v)),
            ),
            SwitchListTile(
              title: const Text('New messages'),
              value: p.newMessages,
              onChanged: (v) => _save(context, ref, p.copyWith(newMessages: v)),
            ),
            SwitchListTile(
              title: const Text('New likes'),
              value: p.newLikes,
              onChanged: (v) => _save(context, ref, p.copyWith(newLikes: v)),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, PrivacySettings next) async {
    try {
      await ref.read(settingsRepositoryProvider).savePrivacy(next);
      ref.invalidate(privacySettingsProvider);
    } catch (e) {
      if (context.mounted) showSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(privacySettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: settings.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(privacySettingsProvider)),
        data: (s) => ListView(
          children: [
            SwitchListTile(
              title: const Text('Show me in Discover'),
              subtitle: const Text('Turn off to pause your profile. Existing matches can still chat with you.'),
              value: s.discoverable,
              onChanged: (v) => _save(context, ref, s.copyWith(discoverable: v)),
            ),
            SwitchListTile(
              title: const Text('Show my distance'),
              subtitle: const Text('Others see an approximate distance, never your location.'),
              value: s.showDistance,
              onChanged: (v) => _save(context, ref, s.copyWith(showDistance: v)),
            ),
            SwitchListTile(
              title: const Text('Read receipts'),
              subtitle: const Text('Let matches see when you’ve read their messages.'),
              value: s.readReceipts,
              onChanged: (v) => _save(context, ref, s.copyWith(readReceipts: v)),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked people')),
      body: blocked.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(blockedUsersProvider)),
        data: (users) => users.isEmpty
            ? const EmptyState(
                icon: Icons.block_rounded,
                title: 'No one blocked',
                message: 'People you block will appear here.',
              )
            : ListView(
                children: [
                  for (final u in users)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_off_outlined)),
                      title: Text(u.displayName),
                      trailing: TextButton(
                        onPressed: () async {
                          try {
                            await ref.read(safetyRepositoryProvider).unblock(u.id);
                            ref.invalidate(blockedUsersProvider);
                          } catch (e) {
                            if (context.mounted) showSnack(context, e);
                          }
                        },
                        child: const Text('Unblock'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
