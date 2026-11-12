import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/widgets/canvas_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(390, 640), const Size(844, 390)]) {
    testWidgets(
        'mobile panels stay small and exclusive with pinned Hide at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final document = GraphDocument.forJob(Job(
          customerName: 'Panel layout QA',
          serviceAddress: '',
          pestPacBillToNumber: '',
          pestPacLocationNumber: '',
          serviceType: 'Measurement',
          createdBy: 'QA',
          createdDate: DateTime(2026)))
        ..replaceWallSegments(const [
          WallSegment(
              start: GraphPoint(x: 100, y: 100),
              end: GraphPoint(x: 800, y: 100))
        ])
        ..markClean();
      final before = document.toJson();
      await tester
          .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
      await tester.pumpAndSettle();
      final matrix = Matrix4.copy(tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value);
      await tester.tap(find.byTooltip('Show main toolbar'));
      await tester.pumpAndSettle();
      final tools = find.byType(CanvasToolbar);
      expect(tester.getSize(tools).height, lessThan(size.height * .4));
      final hide = find.byTooltip('Hide main toolbar');
      final hideRect = tester.getRect(hide);
      expect(hideRect.height, greaterThanOrEqualTo(44));
      expect(find.descendant(of: hide, matching: find.text('Hide')),
          findsOneWidget);
      await tester.drag(
          find
              .descendant(
                  of: tools, matching: find.byType(SingleChildScrollView))
              .first,
          const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(tester.getRect(hide), hideRect);
      tester
          .widget<CanvasQuickToolbar>(find.byType(CanvasQuickToolbar))
          .onToggleProperties();
      await tester.pumpAndSettle();
      expect(tools, findsNothing);
      expect(find.byTooltip('Collapse properties'), findsOneWidget);
      expect(
          tester
              .getSize(find.byKey(const ValueKey('canvas-inspector-panel')))
              .height,
          lessThanOrEqualTo(128));
      expect(find.text('Properties'), findsOneWidget);
      await tester.tap(find.byTooltip('Show main toolbar'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('canvas-inspector-panel')), findsNothing);
      expect(tools, findsOneWidget);
      tester
          .widget<CanvasQuickToolbar>(find.byType(CanvasQuickToolbar))
          .onToggleLayers();
      await tester.pumpAndSettle();
      expect(tools, findsNothing);
      expect(find.byTooltip('Collapse layers'), findsWidgets);
      await tester.tap(find.byTooltip('Collapse layers').first);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('canvas-inspector-panel')), findsNothing);
      expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!
              .value,
          matrix);
      expect(document.toJson(), before);
      expect(tester.takeException(), isNull);
    });
  }
}
