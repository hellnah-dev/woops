import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_providers.dart';
import '../utils/image_processing.dart';

/// Loads a photo from the private `profile-photos` bucket with caching.
/// The cache key is the storage path, so refreshed auth tokens do not cause
/// re-downloads.
class ProfilePhoto extends ConsumerWidget {
  const ProfilePhoto({
    super.key,
    required this.storagePath,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.memCacheWidth,
    this.thumbnail = false,
  });

  final String? storagePath;

  /// Load the small 480 px version (falls back to the full photo if missing).
  final bool thumbnail;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Decode at this width to save memory for thumbnails.
  final int? memCacheWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
    );

    Widget child;
    final path = storagePath;
    if (path == null || path.isEmpty) {
      child = placeholder;
    } else {
      final resolver = ref.watch(photoUrlResolverProvider);
      final key = thumbnail ? thumbnailPathFor(path) : path;
      child = CachedNetworkImage(
        imageUrl: resolver.url(key),
        cacheKey: key,
        httpHeaders: resolver.headers,
        fit: fit,
        memCacheWidth: memCacheWidth,
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (context, url) => Container(color: scheme.surfaceContainerHighest),
        errorWidget: (context, url, error) => thumbnail
            ? ProfilePhoto(storagePath: path, fit: fit, memCacheWidth: memCacheWidth)
            : Container(
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
        ),
      );
    }

    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.storagePath, this.size = 56, this.ring = false});

  final String? storagePath;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final photo = SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ProfilePhoto(storagePath: storagePath, thumbnail: true, memCacheWidth: (size * 3).round()),
      ),
    );
    if (!ring) return photo;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Color(0xFFE8456B), Color(0xFFFF8A5B)]),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.surface),
        child: photo,
      ),
    );
  }
}
