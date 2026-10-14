import 'package:flutter_test/flutter_test.dart';
import 'package:woops/core/astro/zodiac.dart';

void main() {
  test('signs match the server boundaries', () {
    expect(ZodiacSign.fromBirthdate(DateTime(2000, 3, 21)), ZodiacSign.aries);
    expect(ZodiacSign.fromBirthdate(DateTime(2000, 4, 19)), ZodiacSign.aries);
    expect(ZodiacSign.fromBirthdate(DateTime(2000, 12, 31)), ZodiacSign.capricorn);
    expect(ZodiacSign.fromBirthdate(DateTime(2000, 1, 19)), ZodiacSign.capricorn);
    expect(ZodiacSign.fromBirthdate(DateTime(2000, 1, 20)), ZodiacSign.aquarius);
    expect(ZodiacSign.fromBirthdate(DateTime(2000, 2, 19)), ZodiacSign.pisces);
    expect(ZodiacSign.fromBirthdate(DateTime(2000, 8, 10)), ZodiacSign.leo);
  });

  test('every day of the year maps to exactly one sign', () {
    for (var d = DateTime(2024, 1, 1); d.year == 2024; d = d.add(const Duration(days: 1))) {
      expect(ZodiacSign.fromBirthdate(d), isA<ZodiacSign>());
    }
  });

  test('compatibility is friendly and symmetric', () {
    for (final a in ZodiacSign.values) {
      for (final b in ZodiacSign.values) {
        final ab = zodiacCompatibility(a, b);
        expect(ab.hearts, inInclusiveRange(1, 3));
        expect(zodiacCompatibility(b, a).title, ab.title);
      }
    }
    expect(zodiacCompatibility(ZodiacSign.leo, ZodiacSign.gemini).title, 'Sparks fly');
    expect(zodiacCompatibility(ZodiacSign.taurus, ZodiacSign.virgo).title, 'Natural harmony');
  });

  test('server values round-trip', () {
    for (final s in ZodiacSign.values) {
      expect(ZodiacSign.fromValue(s.value), s);
    }
    expect(ZodiacSign.fromValue(null), isNull);
  });
}
