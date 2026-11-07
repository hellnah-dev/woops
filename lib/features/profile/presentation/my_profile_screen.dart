import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/love_ui.dart';
import '../../../core/widgets/photo_viewer.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../../ads/ad_widgets.dart';
import '../../chat/application/chat_controllers.dart';
import '../../discovery/application/discovery_controller.dart';
import '../application/profile_providers.dart';
import '../domain/profile_models.dart';
import 'readiness_card.dart';

class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: profile.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myProfileProvider)),
        data: (p) {
          if (p == null) return const LoadingView();
          return RefreshIndicator(
            onRefresh: () => ref.read(myProfileProvider.notifier).refresh(),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _Header(profile: p),
                const SizedBox(height: AppSpacing.md),
                if (!p.isReadyToDate) ...[ReadinessCard(profile: p), const SizedBox(height: AppSpacing.md)],
                _QuickTile(
                  icon: p.isVerified ? Icons.verified_rounded : Icons.verified_outlined,
                  color: Colors.blue,
                  title: p.isVerified ? 'Verified' : 'Get verified',
                  subtitle: p.isVerified ? 'Blue badge on' : 'A quick selfie adds a blue badge',
                  onTap: p.isVerified ? null : () => context.push(Routes.verify),
                ),
                const SizedBox(height: 12),
                const _StatsRow(),
                const SizedBox(height: 12),
                const _FeedbackCard(),
                const SizedBox(height: 12),
                if (p.completeness < 1) ...[CompletionCard(profile: p), const SizedBox(height: 12)],
                _PhotosCard(profile: p),
                const SizedBox(height: 12),
                _AboutCard(profile: p),
                const SizedBox(height: 12),
                SoftCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _Row(
                        icon: Icons.tune_rounded,
                        label: 'Settings & privacy',
                        onTap: () => context.push(Routes.settings),
                      ),
                    ],
                  ),
                ),
                const NativeAdCard(padding: EdgeInsets.only(top: AppSpacing.md)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Compact header: avatar with completeness ring and a pen to edit.
class _Header extends StatelessWidget {
  const _Header({required this.profile});
  final MyProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = profile;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Semantics(
              button: true,
              label: 'View your photos',
              child: GestureDetector(
                onTap: p.photos.isEmpty
                    ? null
                    : () => showPhotoViewer(context, photos: [for (final ph in p.photos) ph.storagePath]),
                child: GradientRing(
                  value: p.completeness,
                  size: 84,
                  child: ProfileAvatar(storagePath: p.primaryPhoto, size: 70),
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: TintedIconButton(
                icon: Icons.edit_rounded,
                tooltip: 'Edit profile',
                size: 32,
                filled: true,
                onPressed: () => context.push(Routes.editProfile),
              ),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '${p.displayName}, ${ageFromBirthdate(p.birthdate)}',
                      style: theme.textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (p.isVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified_rounded, color: Colors.blue, size: 18),
                  ],
                ],
              ),
              Text(
                [if (p.username != null) '@${p.username}', '${p.zodiac.symbol} ${p.zodiac.label}'].join('  ·  '),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _Pill(text: '${p.completenessPercent}% complete'),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    onTap: () => context.push(Routes.user(p.id)),
                    child: const _Pill(text: 'Preview', icon: Icons.visibility_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: scheme.onPrimaryContainer), const SizedBox(width: 4)],
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.color, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

/// "Complete your profile to 100%": every missing item and what it adds.
class CompletionCard extends StatelessWidget {
  const CompletionCard({super.key, required this.profile});
  final MyProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = profile;
    final todo = p.completionItems.where((i) => !i.done).toList();
    if (todo.isEmpty) return const SizedBox.shrink();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: AppColors.apricot),
              const SizedBox(width: 8),
              Expanded(child: Text('Complete your profile to 100%', style: theme.textTheme.titleMedium)),
              Text('${p.completenessPercent}%', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.rose)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Complete profiles get far more matches. Here’s what’s left:',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          for (final item in todo)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => context.push(item.label.startsWith('Verify') ? Routes.verify : Routes.editProfile),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppColors.rose),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item.label, style: theme.textTheme.bodyMedium)),
                    Text(
                      '+${item.remainingPercent}%',
                      style: theme.textTheme.labelMedium?.copyWith(color: AppColors.rose, fontWeight: FontWeight.w800),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Likes · Matches · Chats at a glance; each opens its tab.
class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likes = ref.watch(likesReceivedProvider).valueOrNull;
    final inbox = ref.watch(inboxProvider).valueOrNull;
    String count(int? n, {int cap = 999}) => n == null ? '–' : (n >= cap ? '$cap+' : '$n');
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _Stat(
            value: count(likes?.length, cap: 60),
            label: 'Likes',
            icon: Icons.favorite_rounded,
            onTap: () => context.go(Routes.likes),
          ),
          const _StatDivider(),
          _Stat(
            value: count(inbox?.length),
            label: 'Matches',
            icon: Icons.people_rounded,
            onTap: () => context.go(Routes.matches),
          ),
          const _StatDivider(),
          _Stat(
            value: count(inbox?.where((c) => c.hasMessages).length),
            label: 'Chats',
            icon: Icons.chat_bubble_rounded,
            onTap: () => context.go(Routes.chats),
          ),
        ],
      ),
    );
  }
}

/// My green/red flags and all likes ever received. Private: only I see them.
final myFeedbackProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  ref.watch(currentUserIdProvider);
  final j = Map<String, dynamic>.from(await ref.read(supabaseClientProvider).rpc('get_my_profile_feedback') as Map);
  return {for (final e in j.entries) e.key: (e.value as num).toInt()};
});

class _FeedbackCard extends ConsumerWidget {
  const _FeedbackCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(myFeedbackProvider).valueOrNull;
    if (f == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    Widget item(String emoji, int value, String label) => Expanded(
      child: Column(
        children: [
          Text('$emoji $value', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('How people see you', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Icon(Icons.lock_outline_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('Only you can see this', style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              item('💚', f['green_flags'] ?? 0, 'Green flags'),
              item('🚩', f['red_flags'] ?? 0, 'Red flags'),
              item('❤️', f['likes'] ?? 0, 'Likes received'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'People you’ve chatted with can give you a flag. Kind, honest chats earn green ones.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon, required this.onTap});
  final String value;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              // Numbers count up smoothly instead of jumping when data arrives.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  value,
                  key: ValueKey(value),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: AppColors.rose),
                  const SizedBox(width: 4),
                  Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5));
}

/// Card with a title row and an optional "Edit" action.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.onEdit});
  final String title;
  final Widget child;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (onEdit != null)
                TextButton.icon(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 36), visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// My photos in a strip, with an "add" tile while there's room for more.
class _PhotosCard extends StatelessWidget {
  const _PhotosCard({required this.profile});
  final MyProfile profile;

  static const _maxPhotos = 6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photos = profile.photos;
    void edit() => context.push(Routes.editProfile);
    return _Section(
      title: 'My photos  ·  ${photos.length}/$_maxPhotos',
      onEdit: edit,
      child: SizedBox(
        height: 120,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length + (photos.length < _maxPhotos ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            if (i == photos.length) {
              return InkWell(
                onTap: edit,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  width: 90,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.rose.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined, color: AppColors.rose),
                ),
              );
            }
            return GestureDetector(
              onTap: () => context.push(Routes.user(profile.id)),
              child: SizedBox(
                width: 90,
                child: ProfilePhoto(
                  storagePath: photos[i].storagePath,
                  thumbnail: true,
                  memCacheWidth: 270,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// What others read about me: intention, basics, bio, interests and prompts.
class _AboutCard extends ConsumerWidget {
  const _AboutCard({required this.profile});
  final MyProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = profile;
    final muted = theme.colorScheme.onSurfaceVariant;
    final allInterests = ref.watch(interestsProvider).valueOrNull ?? const [];
    final interests = allInterests.where((i) => p.interestIds.contains(i.id)).toList();
    void edit() => context.push(Routes.editProfile);

    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(text, style: theme.textTheme.labelMedium),
    );

    Widget missing(String text) => InkWell(
      onTap: edit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.rose)),
      ),
    );

    return _Section(
      title: 'About me',
      onEdit: edit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chip('${p.intention.emoji} ${p.intention.label}'),
              if ((p.jobTitle ?? '').isNotEmpty) chip('💼 ${p.jobTitle}'),
              if ((p.city ?? '').isNotEmpty) chip('📍 ${p.city}'),
            ],
          ),
          const SizedBox(height: 10),
          if (p.bio.trim().isNotEmpty) Text(p.bio, style: theme.textTheme.bodyMedium) else missing('+ Add a short bio'),
          const SizedBox(height: 12),
          Text('Interests', style: theme.textTheme.labelLarge?.copyWith(color: muted)),
          const SizedBox(height: 6),
          if (interests.isEmpty)
            missing('+ Pick a few interests')
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final i in interests) chip('${i.emoji ?? ''} ${i.name}'.trim())],
            ),
          if (p.prompts.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final prompt in p.prompts) ...[
              Text(prompt.prompt, style: theme.textTheme.labelLarge?.copyWith(color: muted)),
              const SizedBox(height: 2),
              Text(prompt.answer, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
            ],
          ] else ...[
            const SizedBox(height: 12),
            missing('+ Answer a prompt to spark conversations'),
          ],
        ],
      ),
    );
  }
}
