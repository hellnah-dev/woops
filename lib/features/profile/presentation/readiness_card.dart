import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/love_ui.dart';
import '../domain/profile_models.dart';

void openProfileStep(BuildContext context, ProfileStep step) =>
    context.push(step == ProfileStep.ageCheck ? Routes.ageCheck : Routes.editProfile);

/// "Why your profile isn't complete": each missing step with the reason and a
/// tap target that goes straight to fixing it.
class ReadinessCard extends StatelessWidget {
  const ReadinessCard({super.key, required this.profile});
  final MyProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = profile.missingSteps;
    final total = ProfileStep.values.length;
    final done = total - missing.length;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💌', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(child: Text('Finish your profile to start matching', style: theme.textTheme.titleMedium)),
              Text('$done/$total', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.rose)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: done / total),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6),
            ),
          ),
          const SizedBox(height: 6),
          for (final step in ProfileStep.values)
            _StepRow(
              step: step,
              done: !missing.contains(step),
              pending: step == ProfileStep.ageCheck && profile.ageCheck == AgeCheck.pending,
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.done, required this.pending});
  final ProfileStep step;
  final bool done;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: done ? null : () => openProfileStep(context, step),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Icon(
                done
                    ? (pending ? Icons.hourglass_top_rounded : Icons.check_circle_rounded)
                    : Icons.radio_button_unchecked_rounded,
                key: ValueKey(done),
                size: 22,
                color: done ? (pending ? AppColors.undo : const Color(0xFF2EAD62)) : AppColors.rose,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pending ? 'ID sent, we’re checking it' : step.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: done ? muted : null,
                      decoration: done && !pending ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (!done) Text(step.why, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ],
              ),
            ),
            if (!done) Icon(Icons.chevron_right_rounded, color: muted),
          ],
        ),
      ),
    );
  }
}

/// Shown on Discover instead of the cards until the profile is ready.
class ProfileGate extends StatelessWidget {
  const ProfileGate({super.key, required this.profile});
  final MyProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = profile.missingSteps.first;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.md),
        const Center(child: Text('💞', style: TextStyle(fontSize: 56))),
        const SizedBox(height: AppSpacing.sm),
        Text('Almost ready to find love', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Complete profiles get far more matches, and they keep Woops real and safe. '
          'Finish these steps to start liking people.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        ReadinessCard(profile: profile),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: () => openProfileStep(context, next),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(next.title),
        ),
      ],
    );
  }
}
