import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woops/core/theme/app_theme.dart';
import 'package:woops/features/auth/data/auth_repository.dart';
import 'package:woops/features/auth/presentation/auth_screens.dart';

class _MockAuth extends Mock implements AuthRepository {}

void main() {
  late _MockAuth auth;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = _MockAuth();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: MaterialApp(theme: AppTheme.light, home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillSignIn(
    WidgetTester tester, {
    String email = 'asha@example.com',
    String password = 'goodpass1',
  }) async {
    await tester.enterText(find.byKey(const Key('signin-email')), email);
    await tester.enterText(find.byType(TextFormField).last, password);
  }

  Future<void> tapSignIn(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Sign in').last);
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
  }

  group('Sign in', () {
    testWidgets('valid details sign in', (tester) async {
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {});
      await pumpScreen(tester, const SignInScreen());
      await fillSignIn(tester);
      await tapSignIn(tester);
      verify(() => auth.signIn(email: 'asha@example.com', password: 'goodpass1')).called(1);
    });

    testWidgets('empty fields are explained instead of sent', (tester) async {
      await pumpScreen(tester, const SignInScreen());
      await tapSignIn(tester);
      expect(find.text('Enter your password'), findsOneWidget);
      verifyNever(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    });

    testWidgets('after 3 wrong passwords a reset option appears', (tester) async {
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AuthException('Invalid login credentials', statusCode: '400'));
      await pumpScreen(tester, const SignInScreen());
      await fillSignIn(tester, password: 'wrongpass');
      for (var i = 0; i < 3; i++) {
        await tapSignIn(tester);
      }
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(find.text('Trouble signing in? Reset your password'), findsOneWidget);
    });

    testWidgets('too many attempts shows a countdown and blocks retries', (tester) async {
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AuthException('Request rate limit reached', statusCode: '429'));
      await pumpScreen(tester, const SignInScreen());
      await fillSignIn(tester);
      await tapSignIn(tester);
      expect(find.textContaining('Try again in 4:'), findsOneWidget);
      expect(find.textContaining('Too many attempts for now'), findsOneWidget);
      // The button is disabled, so a second tap doesn't call the server.
      await tester.tap(find.textContaining('Try again in'));
      await tester.pump();
      verify(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).called(1);
      // The wait survives leaving and reopening the screen.
      await pumpScreen(tester, const SizedBox());
      await pumpScreen(tester, const SignInScreen());
      expect(find.textContaining('Try again in'), findsOneWidget);
    });

    testWidgets('unconfirmed email offers to resend the confirmation', (tester) async {
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AuthException('Email not confirmed', statusCode: '400'));
      when(() => auth.resendConfirmation(any())).thenAnswer((_) async {});
      await pumpScreen(tester, const SignInScreen());
      await fillSignIn(tester);
      await tapSignIn(tester);
      expect(find.textContaining('Please confirm your email first'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('resend-confirmation')));
      await tester.tap(find.byKey(const Key('resend-confirmation')));
      await tester.pumpAndSettle();
      verify(() => auth.resendConfirmation('asha@example.com')).called(1);
      expect(find.textContaining('Confirmation email sent'), findsOneWidget);
    });
  });

  group('Create account', () {
    Future<void> fillSignUp(WidgetTester tester) async {
      await tester.enterText(find.byKey(const Key('signup-email')), 'asha@example.com');
      await tester.enterText(
        find.descendant(of: find.byKey(const Key('signup-password')), matching: find.byType(TextFormField)),
        'goodpass1',
      );
      await tester.enterText(
        find.descendant(of: find.byKey(const Key('signup-confirm')), matching: find.byType(TextFormField)),
        'goodpass1',
      );
      // Date of birth through the date picker (typed in).
      await tester.ensureVisible(find.byKey(const Key('signup-birthdate')));
      await tester.tap(find.byKey(const Key('signup-birthdate')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '01/15/1995');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      for (final key in ['signup-terms', 'signup-guidelines']) {
        final box = find.descendant(of: find.byKey(Key(key)), matching: find.byType(Checkbox));
        await tester.ensureVisible(box);
        await tester.tap(box);
        await tester.pump();
      }
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      // The button keeps a spinner while a dialog is open, so don't wait to "settle".
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    setUp(() {
      when(() => auth.minAgeFor(any())).thenAnswer((_) async => 18);
    });

    testWidgets('a new account is told to check their email', (tester) async {
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          birthdate: any(named: 'birthdate'),
          countryCode: any(named: 'countryCode'),
        ),
      ).thenAnswer((_) async => SignUpResult.confirmEmail);
      await pumpScreen(tester, const SignUpScreen());
      await fillSignUp(tester);
      await submit(tester);
      expect(find.text('Check your email'), findsOneWidget);
      final captured = verify(
        () => auth.signUp(
          email: 'asha@example.com',
          password: 'goodpass1',
          birthdate: captureAny(named: 'birthdate'),
          countryCode: any(named: 'countryCode'),
        ),
      ).captured;
      expect(captured.single, DateTime(1995, 1, 15));
    });

    testWidgets('an email that already has an account is told so (no fake "check your email")', (tester) async {
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          birthdate: any(named: 'birthdate'),
          countryCode: any(named: 'countryCode'),
        ),
      ).thenAnswer((_) async => SignUpResult.alreadyRegistered);
      await pumpScreen(tester, const SignUpScreen());
      await fillSignUp(tester);
      await submit(tester);
      expect(find.text('You already have an account'), findsOneWidget);
      expect(find.text('Check your email'), findsNothing);
    });

    testWidgets('someone under the minimum age for their country is stopped before an account exists', (tester) async {
      when(() => auth.minAgeFor(any())).thenAnswer((_) async => 40); // pretend a strict country
      await pumpScreen(tester, const SignUpScreen());
      await fillSignUp(tester);
      await submit(tester);
      expect(find.text('Sorry, you can’t join Woops'), findsOneWidget);
      verifyNever(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          birthdate: any(named: 'birthdate'),
          countryCode: any(named: 'countryCode'),
        ),
      );
    });
  });
}
