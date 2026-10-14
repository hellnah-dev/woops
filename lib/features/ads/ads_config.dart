import 'package:flutter/foundation.dart';

/// AdMob configuration. Ad unit ids are not secrets, but production ids are
/// still passed via `.env` so debug builds can never show real ads.
///
/// In debug/profile builds Google's official TEST ids are ALWAYS used, as
/// AdMob policy requires (clicking real ads during development can get the
/// account suspended).
class AdsConfig {
  const AdsConfig._();

  static const enabled = bool.fromEnvironment('ADS_ENABLED', defaultValue: true);

  /// Placement switches ("frequency" controls). Interstitials are never used.
  static const bannersEnabled = bool.fromEnvironment('ADS_BANNERS', defaultValue: true);
  static const nativeEnabled = bool.fromEnvironment('ADS_NATIVE', defaultValue: true);
  static const rewardedEnabled = bool.fromEnvironment('ADS_REWARDED', defaultValue: true);

  /// Extra likes per rewarded ad, for display only; the server decides the real
  /// amount (REWARD_LIKES secret) and the daily cap.
  static const rewardLikes = int.fromEnvironment('ADS_REWARD_LIKES', defaultValue: 10);

  static bool get supported =>
      enabled &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _android => defaultTargetPlatform == TargetPlatform.android;
  static bool get useTestIds => !kReleaseMode;

  // Google's public test ad units: https://developers.google.com/admob/flutter/test-ads
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/9214589741';
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2435281174';
  static const _testNativeAndroid = 'ca-app-pub-3940256099942544/2247696110';
  static const _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  static const _bannerAndroid = String.fromEnvironment('ADMOB_ANDROID_BANNER_ID');
  static const _bannerIos = String.fromEnvironment('ADMOB_IOS_BANNER_ID');
  static const _nativeAndroid = String.fromEnvironment('ADMOB_ANDROID_NATIVE_ID');
  static const _nativeIos = String.fromEnvironment('ADMOB_IOS_NATIVE_ID');
  static const _rewardedAndroid = String.fromEnvironment('ADMOB_ANDROID_REWARDED_ID');
  static const _rewardedIos = String.fromEnvironment('ADMOB_IOS_REWARDED_ID');

  static String? _pick(String testAndroid, String testIos, String prodAndroid, String prodIos) {
    if (useTestIds) return _android ? testAndroid : testIos;
    final id = _android ? prodAndroid : prodIos;
    return id.isEmpty ? null : id; // no production id configured → no ad
  }

  static String? get bannerUnitId => _pick(_testBannerAndroid, _testBannerIos, _bannerAndroid, _bannerIos);
  static String? get nativeUnitId => _pick(_testNativeAndroid, _testNativeIos, _nativeAndroid, _nativeIos);
  static String? get rewardedUnitId => _pick(_testRewardedAndroid, _testRewardedIos, _rewardedAndroid, _rewardedIos);
}
