/// Simple Western astrology, just for fun.
enum ZodiacElement { fire, earth, air, water }

enum ZodiacSign {
  aries('aries', 'Aries', '♈', ZodiacElement.fire, 'Mar 21 – Apr 19'),
  taurus('taurus', 'Taurus', '♉', ZodiacElement.earth, 'Apr 20 – May 20'),
  gemini('gemini', 'Gemini', '♊', ZodiacElement.air, 'May 21 – Jun 20'),
  cancer('cancer', 'Cancer', '♋', ZodiacElement.water, 'Jun 21 – Jul 22'),
  leo('leo', 'Leo', '♌', ZodiacElement.fire, 'Jul 23 – Aug 22'),
  virgo('virgo', 'Virgo', '♍', ZodiacElement.earth, 'Aug 23 – Sep 22'),
  libra('libra', 'Libra', '♎', ZodiacElement.air, 'Sep 23 – Oct 22'),
  scorpio('scorpio', 'Scorpio', '♏', ZodiacElement.water, 'Oct 23 – Nov 21'),
  sagittarius('sagittarius', 'Sagittarius', '♐', ZodiacElement.fire, 'Nov 22 – Dec 21'),
  capricorn('capricorn', 'Capricorn', '♑', ZodiacElement.earth, 'Dec 22 – Jan 19'),
  aquarius('aquarius', 'Aquarius', '♒', ZodiacElement.air, 'Jan 20 – Feb 18'),
  pisces('pisces', 'Pisces', '♓', ZodiacElement.water, 'Feb 19 – Mar 20');

  const ZodiacSign(this.value, this.label, this.symbol, this.element, this.dates);
  final String value;
  final String label;
  final String symbol;
  final ZodiacElement element;
  final String dates;

  static ZodiacSign? fromValue(String? v) => ZodiacSign.values.where((s) => s.value == v).firstOrNull;

  /// Same boundaries as the server's private.zodiac_sign().
  static ZodiacSign fromBirthdate(DateTime d) {
    final md = d.month * 100 + d.day;
    if (md >= 321 && md <= 419) return aries;
    if (md >= 420 && md <= 520) return taurus;
    if (md >= 521 && md <= 620) return gemini;
    if (md >= 621 && md <= 722) return cancer;
    if (md >= 723 && md <= 822) return leo;
    if (md >= 823 && md <= 922) return virgo;
    if (md >= 923 && md <= 1022) return libra;
    if (md >= 1023 && md <= 1121) return scorpio;
    if (md >= 1122 && md <= 1221) return sagittarius;
    if (md >= 1222 || md <= 119) return capricorn;
    if (md >= 120 && md <= 218) return aquarius;
    return pisces;
  }

  String get elementLabel => switch (element) {
    ZodiacElement.fire => '🔥 Fire',
    ZodiacElement.earth => '🌿 Earth',
    ZodiacElement.air => '🌬️ Air',
    ZodiacElement.water => '🌊 Water',
  };
}

class ZodiacMatch {
  const ZodiacMatch(this.hearts, this.title, this.text);

  /// 1–3 hearts.
  final int hearts;
  final String title;
  final String text;
}

/// Light-hearted element-based compatibility. Not science, just a conversation starter.
ZodiacMatch zodiacCompatibility(ZodiacSign a, ZodiacSign b) {
  if (a == b) return const ZodiacMatch(3, 'Twin flames', 'Same sign: you just get each other.');
  if (a.element == b.element) {
    return const ZodiacMatch(3, 'Natural harmony', 'Same element: easy understanding and shared vibes.');
  }
  const complementary = {
    {ZodiacElement.fire, ZodiacElement.air},
    {ZodiacElement.earth, ZodiacElement.water},
  };
  if (complementary.any((pair) => pair.containsAll({a.element, b.element}))) {
    return const ZodiacMatch(3, 'Sparks fly', 'Your elements fuel each other. Great chemistry!');
  }
  return const ZodiacMatch(2, 'Opposites attract', 'Different energies that can balance each other out.');
}
