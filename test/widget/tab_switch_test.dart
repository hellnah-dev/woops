import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woops/core/router/home_shell.dart';

void main() {
  testWidgets('switching tabs shows the new tab, hides the old one, and taps reach only the visible tab', (
    tester,
  ) async {
    final taps = <String>[];
    Widget tab(String name) => Center(
      child: ElevatedButton(onPressed: () => taps.add(name), child: Text('Tab $name')),
    );
    var index = 4; // start on "Profile"
    late StateSetter setIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) {
            setIndex = set;
            return Scaffold(
              body: FadingBranchContainer(
                currentIndex: index,
                children: [
                  for (final n in ['Discover', 'Likes', 'Matches', 'Chats', 'Profile']) tab(n),
                ],
              ),
            );
          },
        ),
      ),
    );
    expect(find.text('Tab Profile'), findsOneWidget);
    expect(find.text('Tab Discover'), findsNothing); // offstage tabs aren't found

    setIndex(() => index = 0); // tap "Discover"
    await tester.pumpAndSettle();
    expect(find.text('Tab Discover'), findsOneWidget);
    expect(find.text('Tab Profile'), findsNothing, reason: 'the old tab must not stay on top');

    await tester.tap(find.text('Tab Discover'));
    expect(taps, ['Discover'], reason: 'taps go to the visible tab only');

    // Back to Profile again, then to Chats: never more than one tab visible.
    setIndex(() => index = 4);
    await tester.pumpAndSettle();
    setIndex(() => index = 3);
    await tester.pumpAndSettle();
    expect(find.text('Tab Chats'), findsOneWidget);
    expect(find.text('Tab Profile'), findsNothing);
    expect(find.text('Tab Discover'), findsNothing);
  });
}
