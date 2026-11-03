import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_info.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';

/// Good moments to ask for a little help for the creator.
enum SupportMoment {
  /// Right after someone's first match.
  firstMatch,

  /// After they've sent a good number of messages.
  chatting,

  /// Coming back after a week with the app.
  regular,
}

/// When to ask. Each moment asks at most once, never twice within
/// [cooldown], and never again once the person helped or said no.
class SupportPromptPolicy {
  const SupportPromptPolicy(this._prefs);
  final SharedPreferences _prefs;

  static const cooldown = Duration(days: 3);
  static const messagesBeforeAsking = 15;
  static const daysBeforeRegular = 7;

  static const _done = 'support_done';
  static const _lastAsked = 'support_last_asked';
  static const _firstOpen = 'support_first_open';
  static const _sent = 'support_sent_count';
  static String _asked(SupportMoment m) => 'support_asked_${m.name}';

  bool shouldAsk(SupportMoment moment, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (_prefs.getBool(_done) ?? false) return false;
    if (_prefs.getBool(_asked(moment)) ?? false) return false;
    final last = _prefs.getInt(_lastAsked);
    if (last != null && t.difference(DateTime.fromMillisecondsSinceEpoch(last)) < cooldown) return false;
    return switch (moment) {
      SupportMoment.firstMatch => true,
      SupportMoment.chatting => (_prefs.getInt(_sent) ?? 0) >= messagesBeforeAsking,
      SupportMoment.regular => () {
        final first = _prefs.getInt(_firstOpen);
        return first != null &&
            t.difference(DateTime.fromMillisecondsSinceEpoch(first)) >= const Duration(days: daysBeforeRegular);
      }(),
    };
  }

  Future<void> markAsked(SupportMoment moment, {DateTime? now}) async {
    await _prefs.setBool(_asked(moment), true);
    await _prefs.setInt(_lastAsked, (now ?? DateTime.now()).millisecondsSinceEpoch);
  }

  /// They rated, shared, supported, or asked us to stop: never ask again.
  Future<void> markDone() => _prefs.setBool(_done, true);

  Future<void> noteAppOpened({DateTime? now}) async {
    if (_prefs.getInt(_firstOpen) == null) {
      await _prefs.setInt(_firstOpen, (now ?? DateTime.now()).millisecondsSinceEpoch);
    }
  }

  Future<void> noteMessageSent() => _prefs.setInt(_sent, (_prefs.getInt(_sent) ?? 0) + 1);
}

/// Counts a sent message toward the "chatting" moment. Never throws.
Future<void> noteSupportMessageSent() async {
  try {
    await SupportPromptPolicy(await SharedPreferences.getInstance()).noteMessageSent();
  } catch (_) {}
}

/// Remembers when the app was first used (for the "regular" moment). Never throws.
Future<void> noteSupportAppOpened() async {
  try {
    await SupportPromptPolicy(await SharedPreferences.getInstance()).noteAppOpened();
  } catch (_) {}
}

/// Shows the support sheet if [moment] is a good time. Uses the root
/// navigator, so it can be called right after a screen closes.
Future<void> maybeAskForSupport(SupportMoment moment, {BuildContext? context}) async {
  try {
    final policy = SupportPromptPolicy(await SharedPreferences.getInstance());
    if (!policy.shouldAsk(moment)) return;
    final ctx = context != null && context.mounted ? context : rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await policy.markAsked(moment);
    if (!ctx.mounted) return;
    final helped = await showModalBottomSheet<bool>(
      context: ctx,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _SupportSheet(moment: moment),
    );
    if (helped == true) await policy.markDone();
  } catch (_) {
    // Asking for support must never get in the way.
  }
}

class _SupportSheet extends StatelessWidget {
  const _SupportSheet({required this.moment});
  final SupportMoment moment;

  static const _storeUrl = 'https://play.google.com/store/apps/details?id=com.woops.app';

  (String, String) get _copy => switch (moment) {
    SupportMoment.firstMatch => ('Your first match! 🎉', 'Hope it goes beautifully.'),
    SupportMoment.chatting => ('The conversation is flowing 💬', 'Love to see it.'),
    SupportMoment.regular => ('Thanks for sticking with Woops 💕', 'It means a lot.'),
  };

  Future<void> _rate(BuildContext context) async {
    final review = InAppReview.instance;
    try {
      if (await review.isAvailable()) {
        await review.requestReview();
      } else {
        await review.openStoreListing();
      }
    } catch (_) {
      await launchUrl(Uri.parse(_storeUrl), mode: LaunchMode.externalApplication);
    }
    if (context.mounted) Navigator.pop(context, true);
  }

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: 'I’m using Woops 💕, a sweet little dating app. Come find your person: $_storeUrl',
        subject: 'Try Woops',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    if (context.mounted) Navigator.pop(context, true);
  }

  Future<void> _support(BuildContext context) async {
    await launchUrl(Uri.parse(AppInfo.supportUrl), mode: LaunchMode.externalApplication);
    if (context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, lead) = _copy;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              '$lead Woops is made by one indie developer, ${AppInfo.developer}. '
              'If you’re enjoying it, a quick rating or a share really helps it grow.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              key: const Key('support-rate'),
              onPressed: () => _rate(context),
              icon: const Icon(Icons.star_rounded),
              label: const Text('Rate Woops'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _share(context),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Share with a friend'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _support(context),
              icon: const Icon(Icons.favorite_border_rounded),
              label: const Text('Support the creator'),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  key: const Key('support-never'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Don’t ask again'),
                ),
                TextButton(
                  key: const Key('support-later'),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Maybe later'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
