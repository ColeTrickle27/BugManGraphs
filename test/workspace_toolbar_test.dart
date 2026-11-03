import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'support/crowded_canvas_fixture.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1400, 900)
  ]) {
    testWidgets(
        'history stays visible at bottom with clear share/settings labels at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
          home: GraphCanvasScreen(document: crowdedCanvasFixture())));
      await tester.pumpAndSettle();
      for (final key in ['canvas-bottom-undo', 'canvas-bottom-redo']) {
        final finder = find.byKey(ValueKey(key));
        final rect = tester.getRect(finder);
        expect(rect.top, greaterThan(size.height / 2));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        expect(tester.widget<IconButton>(finder).onPressed, isNull);
      }
      expect(find.byTooltip('Undo'), findsOneWidget);
      expect(find.byTooltip('Redo'), findsOneWidget);
      expect(find.byTooltip('Save and share'), findsOneWidget);
      expect(find.byIcon(Icons.ios_share), findsOneWidget);
      expect(find.byTooltip('Canvas options'), findsOneWidget);
      expect(find.byTooltip('Object properties'), findsOneWidget);
      expect(find.byIcon(Icons.display_settings_outlined), findsOneWidget);
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
      await tester.tap(find.byTooltip('Save and share'));
      await tester.pumpAndSettle();
      final save = find.text('Save Graph to BugMan Graphs');
      expect(save, findsOneWidget);
      expect(tester.getRect(save).right, lessThanOrEqualTo(size.width));
      expect(find.text('Save & Open Inspection Workflow'), findsNothing);
      expect(find.text('Save PNG…'), findsOneWidget);
      expect(find.text('Save PDF…'), findsOneWidget);
      expect(find.text('Email PDF…'), findsOneWidget);
      expect(find.text('Copy Structure to New Graph'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
