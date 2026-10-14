import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woops/core/widgets/confirm_dialog.dart';

void main() {
  Future<bool?> open(WidgetTester tester, Future<void> Function() act) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await confirmAction(
            context,
            title: 'Block Asha?',
            message: 'She won’t be able to message you.',
            confirmLabel: 'Block',
            destructive: true,
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Block Asha?'), findsOneWidget);
    await act();
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('returns true only when the confirm button is tapped', (tester) async {
    expect(await open(tester, () => tester.tap(find.byKey(const Key('confirm-ok')))), isTrue);
  });

  testWidgets('Cancel returns false', (tester) async {
    expect(await open(tester, () => tester.tap(find.byKey(const Key('confirm-cancel')))), isFalse);
  });

  testWidgets('tapping outside the dialog returns false', (tester) async {
    expect(await open(tester, () => tester.tapAt(const Offset(5, 5))), isFalse);
  });
}
