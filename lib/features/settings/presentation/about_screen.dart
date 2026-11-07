import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_info.dart';
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
          const SizedBox(height: AppSpacing.sm),
          for (final doc in LegalDoc.values)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(doc.title),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => openLegal(context, doc),
            ),
          ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: const Text('Support'),
            subtitle: const Text('kamaucha.me/rammy24d'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => launchUrl(Uri.parse(AppInfo.supportUrl), mode: LaunchMode.externalApplication),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline_rounded),
            title: const Text('Email support'),
            subtitle: const Text(Env.supportEmail),
            onTap: () => launchUrl(Uri.parse('mailto:${Env.supportEmail}?subject=Woops%20support%20($version)')),
          ),
          const ListTile(
            leading: Icon(Icons.business_rounded),
            title: Text('${AppInfo.product} by ${AppInfo.company}'),
            subtitle: Text('Developed by ${AppInfo.developer}'),
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: const Text('Open-source licenses'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Woops',
              applicationVersion: version,
              applicationLegalese:
                  '© ${DateTime.now().year} ${AppInfo.company} · ${AppInfo.product} by ${AppInfo.developer}',
            ),
          ),
        ],
      ),
    );
  }
}
