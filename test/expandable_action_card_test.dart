import 'dart:ui' show SemanticsAction;

import 'package:bugman_graphs/widgets/expandable_action_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native disclosure supports keyboard and expanded semantics',
      (t) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ExpandableActionCard(
                title: 'Details', children: [Text('Keyboard detail')]))));
    var data = t.getSemantics(find.text('Details')).getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), true);
    final localizations =
        MaterialLocalizations.of(t.element(find.byType(ExpansionTile)));
    expect(data.hint, localizations.expandedHint);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    data = t.getSemantics(find.text('Details')).getSemanticsData();
    expect(data.hint, localizations.collapsedHint);
    expect(find.text('Keyboard detail'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(find.text('Keyboard detail'), findsNothing);
    semantics.dispose();
  });

  testWidgets('native restored expansion keeps the custom icon aligned',
      (t) async {
    final bucket = PageStorageBucket();
    bool visible = true;
    late StateSetter update;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PageStorage(
      bucket: bucket,
      child: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return visible
            ? const ExpandableActionCard(
                key: PageStorageKey('restored'),
                title: 'Details',
                children: [Text('Retained detail')])
            : const SizedBox();
      }),
    ))));
    await t.tap(find.text('Details'));
    await t.pumpAndSettle();
    update(() => visible = false);
    await t.pumpAndSettle();
    update(() => visible = true);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Retained detail'), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
  });

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
      const MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Padding(
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
    expect(
        tester
            .widget<ExpansionTile>(find.byType(ExpansionTile))
            .expansionAnimationStyle!
            .duration,
        Duration.zero);
    expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero);
    expect(find.text('Edge 1: 24 feet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
