import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/love_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../legal/legal_screen.dart';
import '../data/auth_repository.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  OAuthProvider? _busy;

  Future<void> _social(OAuthProvider provider) async {
    setState(() => _busy = provider);
    try {
      await ref.read(authRepositoryProvider).signInWithProvider(provider);
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DreamyBackground(
        child: Stack(
          children: [
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          const Spacer(flex: 2),
                          const AppLogo(size: 120, showWordmark: true),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Find your sweetheart 💕\nReal people. Real chemistry.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                          const Spacer(flex: 3),
                          PrimaryButton(label: 'Create account', onPressed: () => context.push(Routes.signUp)),
                          const SizedBox(height: AppSpacing.sm + 4),
                          OutlinedButton(onPressed: () => context.push(Routes.signIn), child: const Text('Sign in')),
                          if (Env.enableAppleSignIn) ...[
                            const SizedBox(height: AppSpacing.sm + 4),
                            OutlinedButton.icon(
                              onPressed: _busy == null ? () => _social(OAuthProvider.apple) : null,
                              icon: const Icon(Icons.apple),
                              label: const Text('Continue with Apple'),
                            ),
                          ],
                          if (Env.enableGoogleSignIn) ...[
                            const SizedBox(height: AppSpacing.sm + 4),
                            OutlinedButton.icon(
                              onPressed: _busy == null ? () => _social(OAuthProvider.google) : null,
                              icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                              label: const Text('Continue with Google'),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  border: Border.all(color: theme.colorScheme.outline),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('18+', style: theme.textTheme.labelMedium),
                              ),
                              const SizedBox(width: 8),
                              Text('Adults only', style: theme.textTheme.bodySmall),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const LegalText(),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LegalText extends StatelessWidget {
  const LegalText({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final link = style?.copyWith(decoration: TextDecoration.underline, fontWeight: FontWeight.w600);
    Widget linkButton(String label, LegalDoc doc) => InkWell(
      onTap: () => openLegal(context, doc),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(label, style: link),
      ),
    );
    return Column(
      children: [
        Text('By continuing you agree to our', style: style, textAlign: TextAlign.center),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            linkButton('Terms', LegalDoc.terms),
            Text('·', style: style),
            linkButton('Privacy Policy', LegalDoc.privacy),
            Text('·', style: style),
            linkButton('Community Guidelines', LegalDoc.guidelines),
          ],
        ),
      ],
    );
  }
}
