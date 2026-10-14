import 'package:woops/core/supabase/supabase_providers.dart';
import 'package:woops/core/theme/app_theme.dart';
import 'package:woops/core/widgets/app_logo.dart';
import 'package:woops/features/auth/presentation/auth_screens.dart';
import 'package:woops/features/discovery/data/discovery_repository.dart';
import 'package:woops/features/discovery/presentation/discover_screen.dart';
import 'package:woops/features/discovery/presentation/swipeable_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

Widget _app(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light, home: child),
    );

void main() {
  testWidgets('AppLogo shows a placeholder until assets/branding/logo.png exists', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(body: Center(child: AppLogo(size: 100)))));
    await tester.pumpAndSettle();
    expect(find.text('LOGO'), findsOneWidget);
    expect(tester.getSize(find.byType(AppLogo)), const Size(100, 100));
  });

  testWidgets('Sign-up age gate requires date of birth, consent and valid credentials', (tester) async {
    await tester.pumpWidget(_app(const SignUpScreen()));
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter a password'), findsOneWidget);
    expect(find.text('Enter your date of birth'), findsOneWidget);
    expect(find.text('Please accept to continue'), findsNWidgets(2));

    await tester.enterText(find.byKey(const Key('signup-email')), 'asha@example.com');
    await tester.enterText(find.descendant(of: find.byKey(const Key('signup-password')), matching: find.byType(TextFormField)), 'goodpass1');
    await tester.enterText(find.descendant(of: find.byKey(const Key('signup-confirm')), matching: find.byType(TextFormField)), 'different1');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.text('Passwords don’t match'), findsOneWidget);
  });

  testWidgets('Swipeable card: dragging right past the threshold likes', (tester) async {
    SwipeAction? result;
    await tester.pumpWidget(_app(Scaffold(
      body: SizedBox(
        width: 400,
        height: 600,
        child: SwipeableCard(onSwiped: (a) => result = a, child: const ColoredBox(color: Colors.pink)),
      ),
    )));
    await tester.drag(find.byType(SwipeableCard), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(result, SwipeAction.like);
  });

  testWidgets('Swipeable card: a short drag springs back without swiping', (tester) async {
    SwipeAction? result;
    await tester.pumpWidget(_app(Scaffold(
      body: SwipeableCard(onSwiped: (a) => result = a, child: const ColoredBox(color: Colors.pink)),
    )));
    await tester.timedDrag(find.byType(SwipeableCard), const Offset(-40, 0), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('Discover shows profiles and the Like button records a like', (tester) async {
    final repo = FakeDiscoveryRepository([
      [card('a', name: 'Asha'), card('b', name: 'Bina')],
    ]);
    await tester.pumpWidget(_app(
      const DiscoverScreen(),
      overrides: [
        discoveryRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWithValue('me'),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Asha  27', findRichText: true), findsWidgets);

    await tester.tap(find.byTooltip('Like'));
    await tester.pumpAndSettle();
    expect(repo.swipes, [('a', SwipeAction.like)]);
    expect(find.text('Bina  27', findRichText: true), findsWidgets);
  });

  testWidgets('Discover shows a helpful empty state', (tester) async {
    final repo = FakeDiscoveryRepository([const []]);
    await tester.pumpWidget(_app(
      const DiscoverScreen(),
      overrides: [
        discoveryRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWithValue('me'),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('You’ve seen everyone for now'), findsOneWidget);
    expect(find.text('Adjust filters'), findsOneWidget);
  });
}
