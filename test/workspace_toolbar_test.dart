import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/theme/app_theme.dart';
import 'support/crowded_canvas_fixture.dart';

void main() {
  for (final scale in [1.0, 1.6, 2.0]) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(844, 390),
      const Size(1400, 900)
    ]) {
      testWidgets(
          'history and primary save remain visible at $size and text $scale',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(MaterialApp(
            theme: buildBugManTheme(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: GraphCanvasScreen(document: crowdedCanvasFixture())));
        await tester.pumpAndSettle();
        final compact = size.shortestSide < 600;
        for (final tooltip in ['Undo', 'Redo']) {
          final finder = find.byTooltip(tooltip);
          final rect = tester.getRect(finder);
          expect(
              rect.top,
              compact
                  ? lessThan(size.height / 2)
                  : greaterThan(size.height / 2));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.width, greaterThanOrEqualTo(44));
          expect(rect.height, greaterThanOrEqualTo(44));
          expect(
              tester
                  .widget<IconButton>(find.widgetWithIcon(
                      IconButton, tooltip == 'Undo' ? Icons.undo : Icons.redo))
                  .onPressed,
              isNull);
        }
        expect(find.byTooltip('Undo'), findsOneWidget);
        expect(find.byTooltip('Redo'), findsOneWidget);
        expect(find.byTooltip('Save and share'), findsOneWidget);
        expect(find.byIcon(compact ? Icons.save_outlined : Icons.ios_share),
            findsOneWidget);
        expect(find.byTooltip('Canvas options'), findsOneWidget);
        expect(find.byTooltip('Object properties'), findsOneWidget);
        expect(
            find.byIcon(
                compact ? Icons.more_horiz : Icons.display_settings_outlined),
            findsOneWidget);
        expect(find.byIcon(Icons.edit_note), findsOneWidget);
        for (final tooltip in [
          'Save and share',
          'Canvas options',
          'Object properties'
        ]) {
          final finder = find.byTooltip(tooltip);
          if (!compact) {
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
          }
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          if (compact) {
            expect(rect.width, greaterThanOrEqualTo(44));
            expect(rect.height, greaterThanOrEqualTo(44));
          }
        }
        if (compact) {
          await tester.tap(find.byKey(const ValueKey('primary-pan')));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const ValueKey('primary-select')));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.byTooltip('Save and share'));
        await tester.pumpAndSettle();
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
}
