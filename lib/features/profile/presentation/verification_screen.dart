import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/state_views.dart';
import '../application/profile_providers.dart';
import '../data/profile_repository.dart';

final verificationStatusProvider = FutureProvider.autoDispose<({String status, String? reason})?>(
  (ref) => ref.watch(profileRepositoryProvider).latestVerification(),
);

/// Photo verification: the user takes a selfie copying a pose, and a person
/// on our moderation team compares it with their profile photos in the admin
/// panel. Approved profiles get a blue badge. Selfies are only visible to admins.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  bool _uploading = false;

  Future<void> _takeSelfie() async {
    final XFile? selfie;
    try {
      selfie = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1600,
        imageQuality: 90,
      );
    } catch (_) {
      if (mounted) showSnack(context, 'Couldn’t open the camera. Check Woops’s camera permission in Settings.', isError: true);
      return;
    }
    if (selfie == null) return;
    setState(() => _uploading = true);
    try {
      await ref.read(profileRepositoryProvider).requestVerification(selfie);
      ref.invalidate(verificationStatusProvider);
      if (mounted) showSnack(context, 'Thanks! We’ll review your selfie soon.');
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verified = ref.watch(myProfileProvider).valueOrNull?.isVerified ?? false;
    final status = ref.watch(verificationStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Get verified')),
      body: status.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(verificationStatusProvider)),
        data: (s) {
          if (verified) {
            return const EmptyState(
              icon: Icons.verified_rounded,
              title: 'You’re verified',
              message: 'Your profile shows a blue verified badge.',
            );
          }
          if (s?.status == 'pending') {
            return const EmptyState(
              icon: Icons.hourglass_top_rounded,
              title: 'Under review',
              message: 'A member of our team is checking your selfie. This usually takes less than a day.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const Icon(Icons.verified_outlined, size: 64, color: Colors.blue),
              const SizedBox(height: AppSpacing.md),
              Text('Show people you’re real', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Take a selfie copying the pose below. Our team compares it with your profile photos. '
                'Your selfie is never shown on your profile and only our moderators can see it.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (s?.status == 'rejected') ...[
                const SizedBox(height: AppSpacing.md),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'Your last request wasn’t approved${s?.reason == null ? '' : ': ${s!.reason}'}. You can try again.',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      const Text('✌️', style: TextStyle(fontSize: 72)),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Hold up a peace sign next to your face', style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text('Good light, face clearly visible, no filters or sunglasses.',
                          style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Take selfie',
                icon: Icons.photo_camera_front_outlined,
                loading: _uploading,
                onPressed: _takeSelfie,
              ),
            ],
          );
        },
      ),
    );
  }
}
