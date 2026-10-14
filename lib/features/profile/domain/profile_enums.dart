enum Gender {
  woman('woman', 'Woman', 'Women'),
  man('man', 'Man', 'Men'),
  nonbinary('nonbinary', 'Non-binary', 'Non-binary people');

  const Gender(this.value, this.label, this.pluralLabel);
  final String value;
  final String label;
  final String pluralLabel;

  static Gender fromValue(String value) =>
      Gender.values.firstWhere((g) => g.value == value, orElse: () => Gender.nonbinary);
}

enum Intention {
  longTerm('long_term', 'Long-term partner', '💞'),
  longTermOpen('long_term_open', 'Long-term, open to short', '😍'),
  shortTermOpen('short_term_open', 'Short-term, open to long', '🥂'),
  shortTerm('short_term', 'Short-term fun', '🎉'),
  friends('friends', 'New friends', '👋'),
  figuringOut('figuring_out', 'Still figuring it out', '🤔');

  const Intention(this.value, this.label, this.emoji);
  final String value;
  final String label;
  final String emoji;

  static Intention fromValue(String value) =>
      Intention.values.firstWhere((i) => i.value == value, orElse: () => Intention.figuringOut);
}

/// Prompt questions users can answer on their profile.
const profilePromptQuestions = <String>[
  'My ideal Sunday is…',
  'The way to win me over is…',
  'I geek out on…',
  'A green flag I look for…',
  'Two truths and a lie…',
  'My simple pleasures…',
  'We’ll get along if…',
  'Best travel story…',
  'I’m weirdly attracted to…',
  'Typical Friday night…',
];
