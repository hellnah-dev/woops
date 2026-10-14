import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/love_widgets.dart';
import '../../legal/legal_screen.dart';

final packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

/// App details: version/build, what's inside, legal, support and licenses.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final info = ref.watch(packageInfoProvider).valueOrNull;
    final version = info == null ? '' : 'Version ${info.version} (build ${info.buildNumber})';

    Widget fact(IconData icon, String title, String text) => ListTile(
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(title),
          subtitle: Text(text),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          SizedBox(
            height: 220,
            child: DreamyBackground(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 72),
                    const SizedBox(height: 6),
                    const Wordmark(size: 38),
                    Text(version, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Woops helps adults find genuine connections, anywhere in the world. '
              'Made with 💕 and a strong focus on safety and privacy.',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
          fact(Icons.lock_outline_rounded, 'Your privacy', 'Exact location never stored; photos stripped of hidden data.'),
          fact(Icons.verified_user_outlined, 'Adults only', '18+, or older where local law requires.'),
          fact(Icons.shield_outlined, 'Safety first', 'Block and report anyone; reports are confidential.'),
          const Divider(height: 32),
          for (final doc in LegalDoc.values)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(doc.title),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => openLegal(context, doc),
            ),
          ListTile(
            leading: const Icon(Icons.mail_outline_rounded),
            title: const Text('Contact support'),
            subtitle: const Text(Env.supportEmail),
            onTap: () => launchUrl(Uri.parse('mailto:${Env.supportEmail}?subject=Woops%20support%20($version)')),
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: const Text('Open-source licenses'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Woops',
              applicationVersion: version,
              applicationLegalese: '© ${DateTime.now().year} Woops',
            ),
          ),
        ],
      ),
    );
  }
}
