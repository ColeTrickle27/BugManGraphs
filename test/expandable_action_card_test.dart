import 'package:bugman_graphs/widgets/expandable_action_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collapsing and reopening preserves an edited field', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpandableActionCard(
            title: 'Details',
            children: [TextFormField(initialValue: 'Original note')],
          ),
        ),
      ),
    );
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Edited note');
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Edited note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow card opens with reduced motion without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: ExpandableActionCard(
                title: 'Edge measurements',
                subtitle: 'Every edge, including hidden short labels',
                children: [Text('Edge 1: 24 feet')],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edge measurements'));
    await tester.pumpAndSettle();
    expect(find.text('Edge 1: 24 feet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
