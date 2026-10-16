import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/state_views.dart';

/// Legal documents bundled with the app (they work offline). Also publish the
/// same files on your website for the app-store listings.
enum LegalDoc {
  privacy('privacy', 'Privacy Policy', 'assets/legal/privacy_policy.md'),
  terms('terms', 'Terms of Service', 'assets/legal/terms.md'),
  guidelines('guidelines', 'Community Guidelines', 'assets/legal/community_guidelines.md');

  const LegalDoc(this.slug, this.title, this.asset);
  final String slug;
  final String title;
  final String asset;

  /// Must match private.current_legal_version() in the database. Bump both
  /// when the documents change; users will be asked to accept again.
  static const version = '2026-10-14';

  static LegalDoc? fromSlug(String slug) => LegalDoc.values.where((d) => d.slug == slug).firstOrNull;

  String get route => '/legal/$slug';
}

void openLegal(BuildContext context, LegalDoc doc) {
  // Drop focus first, otherwise coming back re-focuses the last text field
  // and the keyboard pops up unasked.
  FocusManager.instance.primaryFocus?.unfocus();
  context.push(doc.route);
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});
  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(doc.asset),
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!);
          if (!snap.hasData) return const LoadingView();
          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
              children: SimpleMarkdown.render(context, snap.data!),
            ),
          );
        },
      ),
    );
  }
}

/// Minimal Markdown renderer for our legal documents: headings, bullet
/// lists, paragraphs and **bold**. Keeps the app free of extra dependencies.
class SimpleMarkdown {
  const SimpleMarkdown._();

  static List<Widget> render(BuildContext context, String source) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text.rich(
            _inline(paragraph.join(' '), theme.textTheme.bodyLarge!),
            style: const TextStyle(height: 1.5),
          ),
        ),
      );
      paragraph.clear();
    }

    for (final raw in source.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flush();
      } else if (line.startsWith('# ')) {
        flush();
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(line.substring(2), style: theme.textTheme.headlineSmall),
          ),
        );
      } else if (line.startsWith('## ')) {
        flush();
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(line.substring(3), style: theme.textTheme.titleLarge),
          ),
        );
      } else if (line.startsWith('- ')) {
        flush();
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: theme.textTheme.bodyLarge),
                Expanded(
                  child: Text.rich(
                    _inline(line.substring(2), theme.textTheme.bodyLarge!),
                    style: const TextStyle(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        paragraph.add(line.trim());
      }
    }
    flush();
    return widgets;
  }

  static TextSpan _inline(String text, TextStyle base) {
    final parts = text.split('**');
    return TextSpan(
      style: base,
      children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
      ],
    );
  }
}
