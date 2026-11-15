import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'support/crowded_canvas_fixture.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(1400, 900),
    const Size(600, 400)
  ]) {
    testWidgets('layers use available space and remain operable at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: GraphCanvasScreen(document: crowdedCanvasFixture())));
      await tester.pumpAndSettle();
      for (var cycle = 0; cycle < 3; cycle++) {
        await tester.ensureVisible(find.byTooltip('Layers panel'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Layers panel'));
        await tester.pumpAndSettle();
        expect(find.text('Layers'), findsOneWidget);
        final panel = find
            .ancestor(of: find.text('Layers'), matching: find.byType(Material))
            .first;
        final scrollable =
            find.descendant(of: panel, matching: find.byType(Scrollable));
        final trace = find.text('Trace Layer');
        await tester.scrollUntilVisible(trace, 80, scrollable: scrollable);
        await tester.pumpAndSettle();
        expect(trace.hitTestable(), findsOneWidget);
        expect(tester.getRect(trace).bottom, lessThan(size.height - 82));
        final photo = find.text('Photos');
        await tester.scrollUntilVisible(photo, -80, scrollable: scrollable);
        await tester.pumpAndSettle();
        final row = find.ancestor(of: photo, matching: find.byType(Row)).first;
        final hide =
            find.descendant(of: row, matching: find.byTooltip('Hide layer'));
        await tester.tap(hide);
        await tester.pumpAndSettle();
        expect(find.descendant(of: row, matching: find.byTooltip('Show layer')),
            findsOneWidget);
        await tester.tap(
            find.descendant(of: row, matching: find.byTooltip('Show layer')));
        await tester.tap(
            find.descendant(of: row, matching: find.byTooltip('Lock layer')));
        await tester.pumpAndSettle();
        expect(
            find.descendant(of: row, matching: find.byTooltip('Unlock layer')),
            findsOneWidget);
        await tester.tap(
            find.descendant(of: row, matching: find.byTooltip('Unlock layer')));
        await tester.tap(find.byTooltip('Collapse layers'));
        await tester.pumpAndSettle();
        expect(find.text('Photos'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
