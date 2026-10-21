import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax_web_challenge_example/main.dart';

void main() {
  testWidgets('renders the challenge and updates its counter', (tester) async {
    await tester.pumpWidget(const WebChallengeApp());
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('NativaX Web Challenge'), findsWidgets);

    final ui = find.text('UI').evaluate().isNotEmpty
        ? find.text('UI').first
        : find.text('Interacción').first;
    await tester.tap(ui);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final plus = find.text('+');
    expect(plus, findsOneWidget);
    await tester.scrollUntilVisible(
      plus,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    // The sticky nav covers the top of the viewport (as in a browser);
    // bring the button below it before tapping.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(plus);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('1'), findsWidgets);
  });
}
