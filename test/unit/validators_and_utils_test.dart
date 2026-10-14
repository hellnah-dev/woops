import 'package:woops/core/utils/app_exception.dart';
import 'package:woops/core/utils/time_format.dart';
import 'package:woops/core/utils/uuid.dart';
import 'package:woops/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('  asha@example.com '), isNull);
    });

    test('password requires 8+ chars with letters and digits', () {
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('onlyletters'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
      expect(Validators.password('goodpass1'), isNull);
    });

    test('display name length mirrors the database constraint', () {
      expect(Validators.displayName('   '), isNotNull);
      expect(Validators.displayName('A' * 41), isNotNull);
      expect(Validators.displayName('Asha'), isNull);
    });
  });

  group('age', () {
    final today = DateTime(2026, 10, 14);

    test('counts birthdays correctly', () {
      expect(ageFromBirthdate(DateTime(2000, 10, 14), today: today), 26);
      expect(ageFromBirthdate(DateTime(2000, 10, 15), today: today), 25);
    });

    test('18th birthday boundary', () {
      expect(isAdult(DateTime(2008, 10, 14), today: today), isTrue);
      expect(isAdult(DateTime(2008, 10, 15), today: today), isFalse);
    });
  });

  group('AppException.from', () {
    test('maps backend error codes to friendly messages', () {
      final e = AppException.from(const PostgrestException(message: 'rate_limited: you are out of likes for today'));
      expect(e.code, 'rate_limited');
      expect(e.message, 'You are out of likes for today');
    });

    test('uses the default message when the server gives no detail', () {
      final e = AppException.from(const PostgrestException(message: 'nothing_to_undo'));
      expect(e.message, 'There is nothing to undo.');
    });

    test('does not leak raw database errors', () {
      final e = AppException.from(
        const PostgrestException(message: 'duplicate key value violates unique constraint "x"'),
      );
      expect(e.message, 'Something went wrong. Please try again.');
    });

    test('auth errors are humanised', () {
      final e = AppException.from(const AuthException('Invalid login credentials'));
      expect(e.message, 'Email or password is incorrect.');
    });
  });

  test('uuidV4 produces valid, unique v4 UUIDs', () {
    final re = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final ids = List.generate(500, (_) => uuidV4());
    expect(ids.every(re.hasMatch), isTrue);
    expect(ids.toSet().length, ids.length);
  });

  test('shortTimeAgo', () {
    final now = DateTime(2026, 10, 14, 12);
    expect(shortTimeAgo(now.subtract(const Duration(seconds: 20)), now: now), 'now');
    expect(shortTimeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5m');
    expect(shortTimeAgo(now.subtract(const Duration(hours: 3)), now: now), '3h');
  });
}
