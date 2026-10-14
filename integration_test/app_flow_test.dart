// End-to-end smoke test on a real device/emulator against your Supabase project.
//
//   flutter test integration_test --dart-define-from-file=.env
//
// It signs up a brand-new throwaway account, so turn OFF "Confirm email" in
// Supabase → Authentication → Providers → Email on your DEV project first
// (or the test stops at the "Check your email" step).
import 'package:woops/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new user can sign up and reach onboarding', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Create account'), findsOneWidget);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    final email = 'it-${DateTime.now().millisecondsSinceEpoch}@example.com';
    await tester.enterText(find.byKey(const Key('signup-email')), email);
    await tester.enterText(
      find.descendant(of: find.byKey(const Key('signup-password')), matching: find.byType(TextFormField)),
      'testpass123',
    );
    await tester.enterText(
      find.descendant(of: find.byKey(const Key('signup-confirm')), matching: find.byType(TextFormField)),
      'testpass123',
    );
    await tester.ensureVisible(find.byKey(const Key('signup-adult')));
    await tester.tap(find.byKey(const Key('signup-adult')));
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Signed in without a profile → onboarding wizard.
    expect(find.text('What’s your first name?'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('onboarding-name')), 'Tester');
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
  });
}
