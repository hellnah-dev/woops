import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/state_views.dart';
import 'ads_config.dart';
import 'ads_service.dart';

/// Offered when the user has run out of likes or swipes. The reward (more
/// likes and swipes) is granted by the server after Google's server-side
/// verification callback, never by the app, so this just shows the ad and
/// then checks the new allowance.
Future<void> offerRewardedLikes(BuildContext context, WidgetRef ref, {bool swipes = false}) async {
  final outOf = swipes ? 'swipes' : 'likes';
  final outMessage = 'You’re out of $outOf for today. They refresh within 24 hours.';
  if (!AdsConfig.rewardedEnabled || !ref.read(adsReadyProvider)) {
    showSnack(context, outMessage);
    return;
  }
  final client = ref.read(supabaseClientProvider);
  final unit = AdsConfig.rewardedUnitId;
  final uid = client.auth.currentUser?.id;
  if (unit == null || uid == null) return;

  Map<String, dynamic> allowance;
  try {
    allowance = Map<String, dynamic>.from(await client.rpc('get_like_allowance') as Map);
  } catch (e) {
    if (context.mounted) showSnack(context, e);
    return;
  }
  if (!context.mounted) return;
  if ((allowance['rewarded_ads_left'] as num? ?? 0) <= 0) {
    showSnack(context, outMessage);
    return;
  }
  final rewardSwipes = (allowance['reward_swipes'] as num?)?.toInt() ?? 20;

  final watch = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.favorite_rounded),
      title: Text('Out of $outOf'),
      content: Text(
        'Watch a short ad to get ${AdsConfig.rewardLikes} more likes and $rewardSwipes more swipes today '
        '(${allowance['rewarded_ads_left']} ads left today). Or wait: they refresh within 24 hours.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Watch ad'),
        ),
      ],
    ),
  );
  if (watch != true || !context.mounted) return;

  final loaded = Completer<RewardedAd?>();
  await RewardedAd.load(
    adUnitId: unit,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: loaded.complete,
      onAdFailedToLoad: (_) => loaded.complete(null),
    ),
  );
  final ad = await loaded.future;
  if (!context.mounted) {
    ad?.dispose();
    return;
  }
  if (ad == null) {
    showSnack(context, 'No ad is available right now. Please try again later.', isError: true);
    return;
  }

  var earned = false;
  final closed = Completer<void>();
  await ad.setServerSideOptions(ServerSideVerificationOptions(userId: uid, customData: 'likes'));
  ad.fullScreenContentCallback = FullScreenContentCallback(
    onAdDismissedFullScreenContent: (ad) {
      ad.dispose();
      closed.complete();
    },
    onAdFailedToShowFullScreenContent: (ad, _) {
      ad.dispose();
      closed.complete();
    },
  );
  await ad.show(onUserEarnedReward: (_, _) => earned = true);
  await closed.future;
  if (!context.mounted || !earned) return;

  // Google's callback usually arrives within seconds; poll briefly.
  final before = (allowance['limit'] as num?)?.toInt() ?? 0;
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(const Duration(seconds: 2));
    try {
      final now = Map<String, dynamic>.from(await client.rpc('get_like_allowance') as Map);
      if (((now['limit'] as num?)?.toInt() ?? 0) > before) {
        if (context.mounted) {
          showSnack(context, 'You got ${now['limit'] - before} more likes and $rewardSwipes more swipes!');
        }
        return;
      }
    } catch (_) {}
  }
  if (context.mounted) showSnack(context, 'Thanks! Your extra likes and swipes will appear shortly.');
}
