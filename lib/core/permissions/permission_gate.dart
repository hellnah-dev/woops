import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_colors.dart';

enum AppPermission {
  camera(
    Icons.photo_camera_outlined,
    'Allow camera access',
    'Woops uses your camera only when you take a profile photo or a verification selfie.',
  ),
  photos(
    Icons.photo_library_outlined,
    'Allow photo access',
    'Choose photos for your profile. You can allow only selected photos; we never look at the rest.',
  ),
  location(
    Icons.near_me_outlined,
    'See people near you',
    'Your location is rounded to about 1 km and never shown to anyone. Others only see an approximate distance.',
  ),
  notifications(
    Icons.notifications_active_outlined,
    'Never miss a match',
    'Get notified about new matches and messages. You can choose which ones in Settings.',
  );

  const AppPermission(this.icon, this.title, this.reason);
  final IconData icon;
  final String title;
  final String reason;
}

/// Friendly permission flow for iPhone and Android:
///  1. If already granted → continue.
///  2. If never asked → explain why first, then show the system prompt.
///  3. If blocked ("Don't allow" / "Don't ask again") → offer to open Settings.
class PermissionGate {
  const PermissionGate._();

  static Permission? _system(AppPermission p) => switch (p) {
        AppPermission.camera => Permission.camera,
        // Android 13+ uses the system Photo Picker, which needs no permission.
        AppPermission.photos => Platform.isIOS ? Permission.photos : null,
        AppPermission.location => Permission.locationWhenInUse,
        AppPermission.notifications => Permission.notification,
      };

  /// Returns true if the feature may be used now.
  static Future<bool> request(BuildContext context, AppPermission p) async {
    if (kIsWeb) return true;
    final permission = _system(p);
    if (permission == null) return true;

    var status = await permission.status;
    if (status.isGranted || status.isLimited || status.isProvisional) return true;

    if (status.isPermanentlyDenied || status.isRestricted) {
      if (!context.mounted) return false;
      final open = await _sheet(context, p, blocked: true);
      if (open == true) await openAppSettings();
      return false;
    }

    if (!context.mounted) return false;
    final proceed = await _sheet(context, p, blocked: false);
    if (proceed != true) return false;
    status = await permission.request();
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  static Future<bool?> _sheet(BuildContext context, AppPermission p, {required bool blocked}) {
    final theme = Theme.of(context);
    return showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
                child: Icon(p.icon, color: Colors.white, size: 36),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(blocked ? '${p.title} in Settings' : p.title,
                  style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(
                blocked
                    ? '${p.reason}\n\nAccess is currently turned off. Open Settings → Woops to allow it.'
                    : p.reason,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(blocked ? 'Open Settings' : 'Continue'),
              ),
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            ],
          ),
        ),
      ),
    );
  }
}
