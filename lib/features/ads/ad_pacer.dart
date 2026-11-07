import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ads_config.dart';

/// Decides how often passive ads (native cards, the Discover ad card) may
/// appear, so ads start minimal and grow slowly:
///
///  * a rolling 5-minute limit that rises with how many days someone has
///    actually used the app (not calendar days, so people who drop in rarely
///    ramp up slowly): day 1 → 1 ad per 5 min, then +1 per step until the
///    maximum (default 5 per 5 min) on day [AdsConfig.rampDays]. Longer
///    sessions see more ads simply because they span more 5-minute windows;
///  * the stronger formats (daily unlock, banners) only from day
///    [AdsConfig.strongAdsFromDay] of use;
///  * no passive ads in the first [AdsConfig.sessionGraceSeconds] of each
///    session (opening the app is never met with an ad);
///  * rewarded ads are chosen by the user and never counted or limited here.
///
/// Pure logic with an injectable clock, so it can be unit-tested.
class AdPacing {
  AdPacing({
    required DateTime firstSeen,
    required DateTime sessionStart,
    List<DateTime> impressions = const [],
    DateTime Function()? clock,
    this.activeDays,
    this.maxPer5Min = AdsConfig.maxPer5Min,
    this.rampDays = AdsConfig.rampDays,
    this.graceSeconds = AdsConfig.sessionGraceSeconds,
  }) : _firstSeen = firstSeen,
       _sessionStart = sessionStart,
       _impressions = [...impressions],
       _clock = clock ?? DateTime.now;

  final DateTime _firstSeen;
  final DateTime _sessionStart;
  final List<DateTime> _impressions;
  final DateTime Function() _clock;
  final int maxPer5Min;
  final int rampDays;

  /// Days on which the app was opened, today included (null: not known yet,
  /// then calendar days since [firstSeen] are used).
  final int? activeDays;

  /// Which day of use this is (1 on the first day).
  int get daysUsed => activeDays ?? _clock().difference(_firstSeen).inDays + 1;

  /// Daily unlock and banners: not for brand-new users.
  bool get strongAdsAllowed => daysUsed >= AdsConfig.strongAdsFromDay;
  final int graceSeconds;

  static const window = Duration(minutes: 5);

  List<DateTime> get impressions => List.unmodifiable(_impressions);

  /// Ads allowed in any 5-minute window today: 1 on the first day, rising
  /// evenly to [maxPer5Min] by day [rampDays].
  int get capPer5Min {
    if (maxPer5Min <= 1 || rampDays <= 1) return maxPer5Min.clamp(0, 1 << 10);
    final days = daysUsed - 1;
    final step = rampDays / (maxPer5Min - 1);
    return (1 + (days / step).floor()).clamp(1, maxPer5Min);
  }

  /// Profiles between two Discover ad cards: ~17 at the start, 5 at the maximum.
  int get swipesBetweenDeckAds => (20 - 3 * capPer5Min).clamp(5, 20);

  int get shownInWindow {
    final since = _clock().subtract(window);
    return _impressions.where((t) => t.isAfter(since)).length;
  }

  bool get inGracePeriod => _clock().difference(_sessionStart).inSeconds < graceSeconds;

  bool get canShow => maxPer5Min > 0 && !inGracePeriod && shownInWindow < capPer5Min;

  void recordImpression() {
    final now = _clock();
    _impressions
      ..add(now)
      ..removeWhere((t) => now.difference(t) > window);
  }
}

/// App-wide pacer, remembered across launches (first-seen day and recent ads).
class AdPacerController extends Notifier<AdPacing> {
  static const _firstSeenKey = 'ads_first_seen';
  static const _impressionsKey = 'ads_recent_impressions';
  static const _activeDaysKey = 'ads_active_days';
  static const _lastActiveDayKey = 'ads_last_active_day';

  @override
  AdPacing build() {
    final now = DateTime.now();
    _restore(now);
    // Until storage loads, behave like a brand-new user (most conservative).
    return AdPacing(firstSeen: now, sessionStart: now);
  }

  Future<void> _restore(DateTime sessionStart) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var firstMs = prefs.getInt(_firstSeenKey);
      if (firstMs == null) {
        firstMs = sessionStart.millisecondsSinceEpoch;
        await prefs.setInt(_firstSeenKey, firstMs);
      }
      // Count each day the app is opened once.
      final today = '${sessionStart.year}-${sessionStart.month}-${sessionStart.day}';
      var activeDays = prefs.getInt(_activeDaysKey) ?? 0;
      if (prefs.getString(_lastActiveDayKey) != today) {
        activeDays++;
        await prefs.setInt(_activeDaysKey, activeDays);
        await prefs.setString(_lastActiveDayKey, today);
      }
      final recent = (jsonDecode(prefs.getString(_impressionsKey) ?? '[]') as List)
          .map((e) => DateTime.fromMillisecondsSinceEpoch(e as int))
          .toList();
      state = AdPacing(
        firstSeen: DateTime.fromMillisecondsSinceEpoch(firstMs),
        sessionStart: sessionStart,
        impressions: [...recent, ...state.impressions],
        activeDays: activeDays,
      );
    } catch (_) {
      // Storage unavailable: keep the conservative defaults.
    }
  }

  bool get canShow => state.canShow;

  /// Call when an ad is actually shown (AdMob's impression callback).
  Future<void> recordImpression() async {
    state.recordImpression();
    ref.notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_impressionsKey, jsonEncode([for (final t in state.impressions) t.millisecondsSinceEpoch]));
    } catch (_) {}
  }
}

final adPacerProvider = NotifierProvider<AdPacerController, AdPacing>(AdPacerController.new);
