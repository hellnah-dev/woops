import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/love_ui.dart';
import '../../core/widgets/love_widgets.dart';
import '../discovery/application/discovery_controller.dart';
import '../notifications/push_service.dart';
import '../profile/data/location_service.dart';

const _doneKey = 'permissions_intro_done_v1';

/// True if the permissions screen should be shown (once per install).
Future<bool> shouldShowPermissionsIntro() async {
  if (kIsWeb) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_doneKey) ?? false);
  } catch (_) {
    return false;
  }
}

/// Asks for notifications and location up front, explaining why, with one
/// friendly screen instead of surprise system pop-ups.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  bool? _notifications;
  bool? _location;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final n = await Permission.notification.status;
    final l = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    setState(() {
      _notifications = n.isGranted || n.isProvisional;
      _location = l.isGranted || l.isLimited;
    });
  }

  Future<void> _allowNotifications() async {
    setState(() => _busy = true);
    final status = await Permission.notification.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else {
      await ref.read(pushServiceProvider).requestPermission();
    }
    await _check();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _allowLocation() async {
    setState(() => _busy = true);
    try {
      final status = await Permission.locationWhenInUse.status;
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        await ref.read(locationServiceProvider).updateMyLocation();
        ref.read(discoveryControllerProvider.notifier).load(reset: true);
      }
    } catch (_) {
      // Explained in the tile; they can allow it later from Settings.
    }
    await _check();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_doneKey, true);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Back (button or gesture) works like "Maybe later", so nobody gets stuck here.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        body: DreamyBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  const Spacer(),
                  const Text('💌', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: AppSpacing.md),
                  Text('Let love find you', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Two quick things so you never miss a spark.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _PermissionTile(
                    icon: Icons.notifications_active_rounded,
                    title: 'Notifications',
                    subtitle: 'New matches, likes and messages, the moment they happen.',
                    granted: _notifications,
                    onAllow: _busy ? null : _allowNotifications,
                  ),
                  const SizedBox(height: 12),
                  _PermissionTile(
                    icon: Icons.near_me_rounded,
                    title: 'Location',
                    subtitle: 'See people nearby and how far they are. Rounded to ~1 km, never exact.',
                    granted: _location,
                    onAllow: _busy ? null : _allowLocation,
                  ),
                  const Spacer(flex: 2),
                  PrimaryButton(
                    label: (_notifications ?? false) && (_location ?? false) ? 'Start exploring' : 'Continue',
                    onPressed: _finish,
                  ),
                  TextButton(onPressed: _finish, child: const Text('Maybe later')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onAllow,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool? granted;
  final VoidCallback? onAllow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = granted ?? false;
    return SoftCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: ok
                ? const Icon(Icons.check_circle_rounded, key: ValueKey('ok'), color: Color(0xFF2EAD62), size: 30)
                : FilledButton.tonal(
                    key: const ValueKey('ask'),
                    style: FilledButton.styleFrom(minimumSize: const Size(72, 38)),
                    onPressed: granted == null ? null : onAllow,
                    child: const Text('Allow'),
                  ),
          ),
        ],
      ),
    );
  }
}
