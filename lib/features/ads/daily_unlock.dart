import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/theme/app_colors.dart';
import 'ad_pacer.dart';
import 'ads_config.dart';
import 'ads_service.dart';

/// Opens a tab (Likes, Matches) for the rest of the day after one short
/// full-screen ad. The ad only plays when the person taps the button, and if
/// ads are off, not ready, or no ad is available, the tab simply opens:
/// nobody is ever locked out of their own likes or matches.
class DailyAdGate extends ConsumerStatefulWidget {
  const DailyAdGate({
    super.key,
    required this.feature,
    required this.icon,
    required this.title,
    required this.message,
    required this.child,
  });

  /// Remembered per feature and per day, e.g. 'likes'.
  final String feature;
  final IconData icon;
  final String title;
  final String message;
  final Widget child;

  @override
  ConsumerState<DailyAdGate> createState() => _DailyAdGateState();
}

class _DailyAdGateState extends ConsumerState<DailyAdGate> {
  bool? _unlocked;
  bool _loading = false;

  String get _key => 'ad_unlock_${widget.feature}_${ref.read(currentUserIdProvider) ?? ''}';

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() => _unlocked = prefs.getString(_key) == _today());
    } catch (_) {
      if (mounted) setState(() => _unlocked = true);
    }
  }

  Future<void> _unlock() async {
    if (mounted) {
      setState(() {
        _unlocked = true;
        _loading = false;
      });
    }
    try {
      await (await SharedPreferences.getInstance()).setString(_key, _today());
    } catch (_) {}
  }

  Future<void> _watch() async {
    final unit = AdsConfig.interstitialUnitId;
    if (unit == null) return _unlock();
    setState(() => _loading = true);
    final loaded = Completer<InterstitialAd?>();
    await InterstitialAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (_) => loaded.complete(null),
      ),
    );
    final ad = await loaded.future.timeout(const Duration(seconds: 15), onTimeout: () => null);
    if (!mounted) return ad?.dispose();
    // No ad to show: open anyway.
    if (ad == null) return _unlock();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdImpression: (_) => ref.read(adPacerProvider.notifier).recordImpression(),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _unlock();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _unlock();
      },
    );
    await ad.show();
  }

  @override
  Widget build(BuildContext context) {
    final gated =
        AdsConfig.supported &&
        AdsConfig.dailyUnlockEnabled &&
        AdsConfig.interstitialUnitId != null &&
        ref.watch(adsReadyProvider) &&
        ref.watch(adPacerProvider).strongAdsAllowed;
    if (!gated || _unlocked == true) return widget.child;
    if (_unlocked == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
              child: Icon(widget.icon, color: Colors.white, size: 42),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              key: Key('unlock-${widget.feature}'),
              onPressed: _loading ? null : _watch,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_circle_outline_rounded),
              label: Text(_loading ? 'Loading ad…' : 'Watch a short ad to open'),
            ),
            const SizedBox(height: 8),
            Text(
              'Opens until tomorrow. Your chats are always free.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
