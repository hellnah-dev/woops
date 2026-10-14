import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_config.dart';

/// Consent + SDK start-up.
///
/// 1. Google's User Messaging Platform (UMP) shows the GDPR/UK/Swiss consent
///    form where required (configure the message in AdMob → Privacy & messaging).
/// 2. On iOS, Apple's App Tracking Transparency prompt is shown afterwards
///    (if not already answered). Without consent/permission, Google serves
///    only non-personalised / limited ads automatically.
/// 3. The Mobile Ads SDK starts only if consent allows ads to be requested.
/// Any failure simply leaves ads off; the dating features never depend on ads.
class AdsController extends Notifier<bool> {
  bool _started = false;

  /// true once ads may be requested.
  @override
  bool build() => false;

  Future<void> start() async {
    if (_started || !AdsConfig.supported) return;
    _started = true;
    try {
      await _updateConsent();
      if (!await ConsentInformation.instance.canRequestAds()) return;
      if (Platform.isIOS && await AppTrackingTransparency.trackingAuthorizationStatus == TrackingStatus.notDetermined) {
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
      await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
        // Keep ads tasteful in a dating app: no mature-rated ads.
        maxAdContentRating: MaxAdContentRating.t,
      ));
      await MobileAds.instance.initialize();
      state = true;
    } catch (e) {
      debugPrint('Ads disabled: $e');
    }
  }

  Future<void> _updateConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        if (!done.isCompleted) done.complete();
      },
      (_) {
        if (!done.isCompleted) done.complete(); // offline etc. → canRequestAds decides
      },
    );
    return done.future;
  }

  /// Whether to show an "Ad privacy choices" entry in Settings (GDPR regions).
  static Future<bool> privacyOptionsRequired() async {
    if (!AdsConfig.supported) return false;
    try {
      return await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showPrivacyOptions() => ConsentForm.showPrivacyOptionsForm((_) {});
}

final adsReadyProvider = NotifierProvider<AdsController, bool>(AdsController.new);
