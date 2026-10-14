import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../../ads/ad_widgets.dart';
import '../application/profile_providers.dart';

class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: profile.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myProfileProvider)),
        data: (p) {
          if (p == null) return const LoadingView();
          final completeness = p.completeness;
          return RefreshIndicator(
            onRefresh: () => ref.read(myProfileProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 150,
                        height: 150,
                        child: CircularProgressIndicator(
                          value: completeness,
                          strokeWidth: 5,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      ProfileAvatar(storagePath: p.primaryPhoto, size: 130),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${p.displayName}, ${ageFromBirthdate(p.birthdate)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                if (p.username != null)
                  Text('@${p.username}', textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                Text(
                  '${p.zodiac.symbol} ${p.zodiac.label}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${(completeness * 100).round()}% complete',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => context.push(Routes.editProfile),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit profile'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(Routes.user(p.id)),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Preview'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: ListTile(
                    leading: Icon(p.isVerified ? Icons.verified_rounded : Icons.verified_outlined, color: Colors.blue),
                    title: Text(p.isVerified ? 'Photo verified' : 'Get verified'),
                    subtitle: Text(
                      p.isVerified ? 'Your profile shows a blue badge' : 'Take a quick selfie to earn a blue badge',
                    ),
                    trailing: p.isVerified ? null : const Icon(Icons.chevron_right_rounded),
                    onTap: p.isVerified ? null : () => context.push(Routes.verify),
                  ),
                ),
                if (completeness < 1) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome_rounded, color: AppColors.apricot),
                              const SizedBox(width: 8),
                              Text('Stand out', style: theme.textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (p.photos.length < 4) const _Tip('Add more photos (4+ works best)'),
                          if (p.bio.trim().isEmpty) const _Tip('Write a short bio'),
                          if (p.prompts.isEmpty) const _Tip('Answer a prompt. It makes starting a chat easy'),
                          if (p.interestIds.length < 3) const _Tip('Pick at least 3 interests'),
                          if ((p.jobTitle ?? '').isEmpty || (p.city ?? '').isEmpty) const _Tip('Add your job and city'),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.tune_rounded),
                        title: const Text('Settings & privacy'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push(Routes.settings),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const NativeAdCard(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  '),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
