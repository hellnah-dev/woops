import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/love_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../profile/application/profile_providers.dart';
import '../data/auth_repository.dart';

/// Shown while the signed-in user's profile loads. The router moves on as
/// soon as it is available.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    return Scaffold(
      body: DreamyBackground(
        child: SafeArea(
          child: profile.hasError && !profile.isLoading
              ? Column(
                  children: [
                    Expanded(
                      child: ErrorView(error: profile.error!, onRetry: () => ref.invalidate(myProfileProvider)),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (await confirmAction(context, title: 'Sign out?', confirmLabel: 'Sign out')) {
                          await ref.read(authRepositoryProvider).signOut();
                        }
                      },
                      child: const Text('Sign out'),
                    ),
                    const SizedBox(height: 16),
                  ],
                )
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppLogo(size: 112, showWordmark: true),
                      SizedBox(height: 32),
                      SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
