import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/photo_viewer.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../application/profile_providers.dart';
import '../data/profile_repository.dart';
import '../domain/profile_models.dart';

/// 3×2 grid to add, remove and reorder (make main) profile photos.
/// Changes are saved immediately.
class PhotoGridEditor extends ConsumerStatefulWidget {
  const PhotoGridEditor({super.key});

  static const maxPhotos = 6;

  @override
  ConsumerState<PhotoGridEditor> createState() => _PhotoGridEditorState();
}

class _PhotoGridEditorState extends ConsumerState<PhotoGridEditor> {
  bool _uploading = false;
  String? _busyId;

  Future<void> _add(int position) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 2048, maxHeight: 2048, imageQuality: 90);
    } catch (e) {
      if (mounted) {
        showSnack(
          context,
          'Couldn’t open your ${source == ImageSource.camera ? 'camera' : 'photos'}. '
          'Check Woops’s permissions in Settings.',
          isError: true,
        );
      }
      return;
    }
    if (file == null) return;

    setState(() => _uploading = true);
    try {
      await ref.read(profileRepositoryProvider).uploadPhoto(file, position: position);
      await ref.read(myProfileProvider.notifier).refresh();
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _options(ProfilePhotoRecord photo, List<ProfilePhotoRecord> photos) async {
    final isMain = photos.first.id == photo.id;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.zoom_out_map_rounded),
              title: const Text('View photo'),
              onTap: () => Navigator.pop(context, 'view'),
            ),
            if (!isMain)
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: const Text('Make main photo'),
                onTap: () => Navigator.pop(context, 'main'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
              title: Text('Remove photo', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'view') {
      await showPhotoViewer(context,
          photos: photos.map((p) => p.storagePath).toList(), initialIndex: photos.indexOf(photo));
      return;
    }

    final repo = ref.read(profileRepositoryProvider);
    setState(() => _busyId = photo.id);
    try {
      if (action == 'delete') {
        final profile = ref.read(myProfileProvider).valueOrNull;
        if (photos.length == 1 && (profile?.onboardingCompleted ?? false)) {
          showSnack(context, 'Your profile needs at least one photo. Add another before removing this one.',
              isError: true);
          return;
        }
        await repo.deletePhoto(photo);
        await repo.reorderPhotos(photos.where((p) => p.id != photo.id).toList());
      } else {
        await repo.reorderPhotos([photo, ...photos.where((p) => p.id != photo.id)]);
      }
      await ref.read(myProfileProvider.notifier).refresh();
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(myProfileProvider).valueOrNull?.photos ?? const <ProfilePhotoRecord>[];
    final scheme = Theme.of(context).colorScheme;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: PhotoGridEditor.maxPhotos,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.75,
      ),
      itemBuilder: (context, i) {
        if (i < photos.length) {
          final photo = photos[i];
          return Semantics(
            button: true,
            label: i == 0 ? 'Main photo. Tap for options' : 'Photo ${i + 1}. Tap for options',
            child: GestureDetector(
              onTap: _busyId == null ? () => _options(photo, photos) : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProfilePhoto(
                    storagePath: photo.storagePath,
                    thumbnail: true,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    memCacheWidth: 400,
                  ),
                  if (i == 0)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Text('Main',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  if (_busyId == photo.id)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                ],
              ),
            ),
          );
        }

        final isNextSlot = i == photos.length;
        return Semantics(
          button: true,
          label: 'Add photo',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: isNextSlot && !_uploading ? () => _add(i) : null,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Center(
                child: isNextSlot && _uploading
                    ? const CircularProgressIndicator()
                    : Icon(
                        Icons.add_circle_rounded,
                        size: 32,
                        color: isNextSlot ? scheme.primary : scheme.outlineVariant,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
