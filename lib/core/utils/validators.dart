/// Form validators shared by auth and profile screens. They mirror the
/// database constraints so users see problems before a request is sent.
class Validators {
  const Validators._();

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter a password';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Use both letters and numbers';
    }
    return null;
  }

  static String? displayName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your first name';
    if (v.length > 40) return 'Keep it under 40 characters';
    return null;
  }

  static final _username = RegExp(r'^[a-zA-Z0-9_.]{3,20}$');

  /// Mirrors the database rule: 3–20 letters, numbers, "_" or ".".
  static String? username(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Choose a username';
    if (v.length < 3) return 'Use at least 3 characters';
    if (v.length > 20) return 'Use 20 characters or fewer';
    if (!_username.hasMatch(v)) return 'Only letters, numbers, _ and . are allowed';
    return null;
  }

  static String? maxLength(String? value, int max, {String? label}) {
    if ((value ?? '').length > max) return '${label ?? 'This'} must be $max characters or fewer';
    return null;
  }
}

/// Age in whole years on [today] (defaults to now).
int ageFromBirthdate(DateTime birthdate, {DateTime? today}) {
  final now = today ?? DateTime.now();
  var age = now.year - birthdate.year;
  final hadBirthday = now.month > birthdate.month || (now.month == birthdate.month && now.day >= birthdate.day);
  if (!hadBirthday) age--;
  return age;
}

bool isAdult(DateTime birthdate, {DateTime? today}) => ageFromBirthdate(birthdate, today: today) >= 18;
