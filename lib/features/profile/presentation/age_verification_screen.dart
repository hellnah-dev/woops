import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/countries.dart';
import '../../../core/i18n/id_documents.dart';
import '../../../core/permissions/permission_gate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/love_ui.dart';
import '../../../core/widgets/state_views.dart';
import '../application/profile_providers.dart';
import '../data/profile_repository.dart';
import '../domain/profile_models.dart';

final _minAgeProvider = FutureProvider.autoDispose.family<int, String?>(
  (ref, country) => ref.watch(profileRepositoryProvider).minAgeForCountry(country),
);

/// Age check with a government ID. The minimum age follows the person's
/// country. A moderator compares the date of birth on the document with the
/// profile; the photo is deleted right after the review.
class AgeVerificationScreen extends ConsumerStatefulWidget {
  const AgeVerificationScreen({super.key});

  @override
  ConsumerState<AgeVerificationScreen> createState() => _AgeVerificationScreenState();
}

class _AgeVerificationScreenState extends ConsumerState<AgeVerificationScreen> {
  String? _docType;
  XFile? _photo;
  bool _sending = false;

  Future<void> _pick(ImageSource source) async {
    final permission = source == ImageSource.camera ? AppPermission.camera : AppPermission.photos;
    if (!await PermissionGate.request(context, permission) || !mounted) return;
    try {
      final picked = await ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 92);
      if (picked != null && mounted) setState(() => _photo = picked);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Couldn’t open your ${source == ImageSource.camera ? 'camera' : 'photos'}.', isError: true);
      }
    }
  }

  Future<void> _submit() async {
    if (_docType == null || _photo == null) return;
    setState(() => _sending = true);
    try {
      await ref.read(profileRepositoryProvider).submitAgeDocument(_photo!, documentType: _docType!);
      await ref.read(myProfileProvider.notifier).refresh();
      if (!mounted) return;
      showSnack(context, 'Sent! You can start matching while we check it.');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final country = countryByCode(profile?.countryCode);
    final minAge = ref.watch(_minAgeProvider(profile?.countryCode)).valueOrNull ?? 18;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your age')),
      body: SafeArea(
        child: switch (profile?.ageCheck) {
          null => const LoadingView(),
          AgeCheck.approved => const EmptyState(
            icon: Icons.verified_user_rounded,
            title: 'Age confirmed',
            message: 'Thanks! Your ID has been checked and deleted.',
          ),
          AgeCheck.pending => const EmptyState(
            icon: Icons.hourglass_top_rounded,
            title: 'We’re checking your ID',
            message: 'This usually takes less than a day. You can already start matching.',
          ),
          _ => ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
            children: [
              SoftCard(
                child: Row(
                  children: [
                    Text(country?.flag ?? '🌍', style: const TextStyle(fontSize: 34)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$minAge+ in ${country?.name ?? 'your country'}', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            'Dating apps must check that members meet the local minimum age.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (profile!.ageCheck == AgeCheck.rejected) ...[
                const SizedBox(height: AppSpacing.md),
                InfoBanner(
                  icon: Icons.info_outline_rounded,
                  tone: BannerTone.error,
                  text:
                      'Your last ID wasn’t accepted${profile.ageRejectReason == null ? '' : ': ${profile.ageRejectReason}'}. Please try again.',
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              const StepHeader(number: 1, title: 'Choose your document'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final doc in idDocumentsFor(profile.countryCode))
                    ChoiceChip(
                      label: Text(doc),
                      selected: _docType == doc,
                      onSelected: (_) => setState(() => _docType = doc),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const StepHeader(number: 2, title: 'Take a clear photo of it'),
              const SizedBox(height: AppSpacing.sm),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _photo == null
                    ? Row(
                        key: const ValueKey('pick'),
                        children: [
                          Expanded(
                            child: _PickTile(
                              icon: Icons.photo_camera_outlined,
                              label: 'Camera',
                              onTap: () => _pick(ImageSource.camera),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PickTile(
                              icon: Icons.photo_library_outlined,
                              label: 'Gallery',
                              onTap: () => _pick(ImageSource.gallery),
                            ),
                          ),
                        ],
                      )
                    : Stack(
                        key: const ValueKey('preview'),
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: AspectRatio(
                              aspectRatio: 1.6,
                              child: kIsWeb
                                  ? Image.network(_photo!.path, fit: BoxFit.cover)
                                  : Image.file(File(_photo!.path), fit: BoxFit.cover),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton.filledTonal(
                              tooltip: 'Retake',
                              onPressed: () => setState(() => _photo = null),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '• All four corners visible  • Date of birth readable  • No glare  • Max 5 MB',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              const InfoBanner(
                icon: Icons.lock_outline_rounded,
                text:
                    'Only our safety team sees your ID. It is deleted as soon as it has been checked; '
                    'we keep only the result.',
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Send for review',
                icon: Icons.send_rounded,
                loading: _sending,
                onPressed: _docType != null && _photo != null ? _submit : null,
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.rose.withValues(alpha: 0.35), width: 1.2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: AppColors.rose),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
