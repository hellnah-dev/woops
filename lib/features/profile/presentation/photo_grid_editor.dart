import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/permissions/permission_gate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/photo_viewer.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/profile_photo.dart';
import '../../../core/widgets/state_views.dart';
import '../application/profile_providers.dart';
import '../data/profile_repository.dart';
import '../domain/profile_models.dart';

/// 3×2 photo grid:
///  * tap an empty slot to add (camera or library → crop → upload)
///  * tap a photo to view, make main, replace (with crop) or remove
///  * press and hold a photo, then drag it to reorder
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

  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  Future<void> _refresh() => ref.read(myProfileProvider.notifier).refresh();

  /// Source sheet → permission → pick → crop. Returns null if cancelled.
  Future<XFile?> _pickAndCrop() async {
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
    if (source == null || !mounted) return null;

    final allowed = await PermissionGate.request(
      context,
      source == ImageSource.camera ? AppPermission.camera : AppPermission.photos,
    );
    if (!allowed || !mounted) return null;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 95);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Couldn’t open your ${source == ImageSource.camera ? 'camera' : 'photos'}.', isError: true);
      }
      return null;
    }
    if (picked == null || kIsWeb) return picked; // cropping is mobile-only

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 3, ratioY: 4),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop photo',
          toolbarColor: AppColors.rose,
          toolbarWidgetColor: Colors.white,
          statusBarLight: false,
          activeControlsWidgetColor: AppColors.rose,
          lockAspectRatio: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.original,
          ],
        ),
        IOSUiSettings(
          title: 'Crop photo',
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
          aspectRatioPresets: [
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.original,
          ],
        ),
      ],
    );
    return cropped == null ? null : XFile(cropped.path);
  }

  Future<void> _add(int position) async {
    final file = await _pickAndCrop();
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await _repo.uploadPhoto(file, position: position);
      await _refresh();
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _replace(ProfilePhotoRecord photo, List<ProfilePhotoRecord> photos) async {
    final file = await _pickAndCrop();
    if (file == null || !mounted) return;
    setState(() => _busyId = photo.id);
    try {
      // Upload the new one first so the profile never has zero photos.
      await _repo.uploadPhoto(file, position: photo.position);
      await _repo.deletePhoto(photo);
      await _refresh();
      // Put the new photo where the old one was.
      final updated = ref.read(myProfileProvider).valueOrNull?.photos ?? const <ProfilePhotoRecord>[];
      final index = photos.indexWhere((p) => p.id == photo.id);
      final fresh = updated.where((p) => photos.every((old) => old.id != p.id)).toList();
      if (fresh.isNotEmpty) {
        final ordered = updated.where((p) => p.id != fresh.first.id).toList()
          ..insert(index.clamp(0, updated.length - 1), fresh.first);
        await _repo.reorderPhotos(ordered);
        await _refresh();
      }
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _remove(ProfilePhotoRecord photo, List<ProfilePhotoRecord> photos) async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    if (photos.length == 1 && (profile?.onboardingCompleted ?? false)) {
      showSnack(context, 'Your profile needs at least one photo. Add another before removing this one.', isError: true);
      return;
    }
    final ok = await confirmAction(
      context,
      icon: Icons.delete_outline_rounded,
      destructive: true,
      title: 'Remove this photo?',
      message: 'It will be deleted from your profile.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    setState(() => _busyId = photo.id);
    try {
      await _repo.deletePhoto(photo);
      await _repo.reorderPhotos(photos.where((p) => p.id != photo.id).toList());
      await _refresh();
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _move(List<ProfilePhotoRecord> photos, int from, int to) async {
    if (from == to) return;
    HapticFeedback.selectionClick();
    final ordered = [...photos];
    final item = ordered.removeAt(from);
    ordered.insert(to.clamp(0, ordered.length), item);
    setState(() => _busyId = item.id);
    try {
      await _repo.reorderPhotos(ordered);
      await _refresh();
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _options(ProfilePhotoRecord photo, List<ProfilePhotoRecord> photos) async {
    final index = photos.indexOf(photo);
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
            if (index != 0)
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: const Text('Make main photo'),
                onTap: () => Navigator.pop(context, 'main'),
              ),
            ListTile(
              leading: const Icon(Icons.crop_rounded),
              title: const Text('Replace (choose & crop a new photo)'),
              onTap: () => Navigator.pop(context, 'replace'),
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
    if (!mounted) return;
    switch (action) {
      case 'view':
        await showPhotoViewer(context, photos: photos.map((p) => p.storagePath).toList(), initialIndex: index);
      case 'main':
        await _move(photos, index, 0);
      case 'replace':
        await _replace(photo, photos);
      case 'delete':
        await _remove(photo, photos);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(myProfileProvider).valueOrNull?.photos ?? const <ProfilePhotoRecord>[];
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - 20) / 3;
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
                if (i >= photos.length) return _emptySlot(i, photos.length, scheme);
                final photo = photos[i];
                final tile = _PhotoTile(photo: photo, isMain: i == 0, busy: _busyId == photo.id);
                return DragTarget<int>(
                  onWillAcceptWithDetails: (d) => d.data != i,
                  onAcceptWithDetails: (d) => _move(photos, d.data, i),
                  builder: (context, candidates, _) => AnimatedScale(
                    duration: const Duration(milliseconds: 120),
                    scale: candidates.isNotEmpty ? 0.94 : 1,
                    child: LongPressDraggable<int>(
                      data: i,
                      feedback: SizedBox(
                        width: tileWidth,
                        height: tileWidth / 0.75,
                        child: Opacity(
                          opacity: 0.9,
                          child: Material(color: Colors.transparent, child: tile),
                        ),
                      ),
                      childWhenDragging: Opacity(opacity: 0.3, child: tile),
                      onDragStarted: HapticFeedback.mediumImpact,
                      child: Semantics(
                        button: true,
                        label: i == 0 ? 'Main photo. Tap for options' : 'Photo ${i + 1}. Tap for options',
                        child: GestureDetector(
                          onTap: _busyId == null ? () => _options(photo, photos) : null,
                          child: tile,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        if (photos.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Tip: press and hold a photo, then drag to reorder.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _emptySlot(int i, int count, ColorScheme scheme) {
    final isNextSlot = i == count;
    return Semantics(
      button: true,
      label: 'Add photo',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: isNextSlot && !_uploading ? () => _add(i) : null,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: scheme.primary.withValues(alpha: isNextSlot ? 0.5 : 0.15), width: 1.5),
          ),
          child: Center(
            child: isNextSlot && _uploading
                ? const CircularProgressIndicator()
                : Icon(Icons.add_circle_rounded, size: 32, color: isNextSlot ? scheme.primary : scheme.outlineVariant),
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.isMain, required this.busy});
  final ProfilePhotoRecord photo;
  final bool isMain;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ProfilePhoto(
          storagePath: photo.storagePath,
          thumbnail: true,
          borderRadius: BorderRadius.circular(AppRadius.md),
          memCacheWidth: 400,
        ),
        if (isMain)
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: const Text(
                '💖 Main',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        Positioned(
          right: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
            child: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 16),
          ),
        ),
        if (busy)
          Container(
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
      ],
    );
  }
}
