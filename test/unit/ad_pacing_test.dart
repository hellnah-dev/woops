import 'package:flutter_test/flutter_test.dart';
import 'package:woops/features/ads/ad_pacer.dart';

void main() {
  final start = DateTime(2026, 10, 15, 12);

  AdPacing pacing({required int day, int secondsIntoSession = 600, List<DateTime> shown = const []}) {
    final now = start.add(Duration(days: day, seconds: secondsIntoSession));
    return AdPacing(
      firstSeen: start,
      sessionStart: now.subtract(Duration(seconds: secondsIntoSession)),
      impressions: shown,
      clock: () => now,
      maxPer5Min: 5,
      rampDays: 7,
      graceSeconds: 60,
    );
  }

  test('starts minimal and rises to 5 ads per 5 minutes by day 7', () {
    expect([for (var d = 0; d <= 8; d++) pacing(day: d).capPer5Min], [1, 1, 2, 2, 3, 3, 4, 5, 5]);
  });

  test('Discover ad cards are rare at first and at most every 5 profiles later', () {
    expect(pacing(day: 0).swipesBetweenDeckAds, 17);
    expect(pacing(day: 30).swipesBetweenDeckAds, 5);
  });

  test('no ads in the first minute of a session', () {
    expect(pacing(day: 10, secondsIntoSession: 30).canShow, isFalse);
    expect(pacing(day: 10, secondsIntoSession: 61).canShow, isTrue);
  });

  test('a new user gets at most 1 ad per 5 minutes', () {
    final p = pacing(day: 0);
    expect(p.canShow, isTrue);
    p.recordImpression();
    expect(p.canShow, isFalse);
  });

  test('a regular user gets at most 5 ads per 5 minutes, and older ads stop counting', () {
    var now = start.add(const Duration(days: 10));
    final p = AdPacing(
      firstSeen: start,
      sessionStart: now.subtract(const Duration(minutes: 10)),
      clock: () => now,
      maxPer5Min: 5,
      rampDays: 7,
      graceSeconds: 60,
    );
    for (var i = 0; i < 5; i++) {
      expect(p.canShow, isTrue, reason: 'ad ${i + 1}');
      p.recordImpression();
      now = now.add(const Duration(seconds: 30));
    }
    expect(p.canShow, isFalse); // 5 shown within 5 minutes
    now = now.add(const Duration(minutes: 3)); // the first ones age out of the window
    expect(p.canShow, isTrue);
  });

  test('ads can be switched off entirely', () {
    final p = AdPacing(
      firstSeen: start,
      sessionStart: start,
      clock: () => start.add(const Duration(days: 9)),
      maxPer5Min: 0,
    );
    expect(p.canShow, isFalse);
  });

  AdPacing used({required int activeDays, required int calendarDays}) {
    final now = start.add(Duration(days: calendarDays, minutes: 10));
    return AdPacing(
      firstSeen: start,
      sessionStart: now.subtract(const Duration(minutes: 10)),
      clock: () => now,
      activeDays: activeDays,
      maxPer5Min: 5,
      rampDays: 7,
      graceSeconds: 60,
    );
  }

  test('ads grow with days of actual use, not calendar days', () {
    // Opened on only 2 days in a month: still a light ad level.
    expect(used(activeDays: 2, calendarDays: 30).capPer5Min, 1);
    // Used daily for 8 days: the full level.
    expect(used(activeDays: 8, calendarDays: 7).capPer5Min, 5);
  });

  test('the daily unlock and banners start on the 3rd day of use', () {
    expect(used(activeDays: 1, calendarDays: 0).strongAdsAllowed, isFalse);
    expect(used(activeDays: 2, calendarDays: 20).strongAdsAllowed, isFalse);
    expect(used(activeDays: 3, calendarDays: 2).strongAdsAllowed, isTrue);
  });
}
