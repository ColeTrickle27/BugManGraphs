import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/editor/label_presentation.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/widgets/graph_annotations_painter.dart';
import 'support/crowded_canvas_fixture.dart';

const callout = GraphAnnotation(
    id: 'synthetic-callout',
    kind: GraphAnnotationKind.text,
    point: GraphPoint(x: 1200, y: 950),
    label: 'Treatment needed',
    fontSize: 24,
    backgroundColor: Colors.blue,
    borderColor: Colors.black,
    extraProperties: {'calloutTipX': 1400.0, 'calloutTipY': 1200.0});

void main() {
  test('callout wraps whole words with bounded touch-sized frame', () {
    for (final zoom in [0.03, 0.15, 1.0, 4.0]) {
      final labels = LabelPresentation(zoom: zoom, bounded: true);
      final text = GraphAnnotationsPainter.calloutText(callout, labels);
      expect(text.computeLineMetrics().length, lessThanOrEqualTo(2));
      final bounds = GraphAnnotationsPainter.textBounds(callout, labels);
      expect(bounds.width * zoom, inInclusiveRange(128, 280));
      expect(bounds.height * zoom, lessThan(85));
      final scene =
          (Offset.zero & const Size(3600, 2600)).expandToInclude(bounds);
      expect(
          GraphAnnotationsPainter.textBounds(callout, labels,
              sceneBounds: scene),
          bounds);
      expect(
          GraphAnnotationsPainter.containsPoint(
              callout, bounds.centerRight - Offset(1 / zoom, 0), labels,
              sceneBounds: scene),
          isTrue);
    }
  });
  for (final size in [const Size(390, 844), const Size(1400, 900)]) {
    testWidgets(
        'callout body drag preserves grab offset, arrow tip and geometry at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final document = crowdedCanvasFixture()..replaceAnnotations([callout]);
      final walls = (document.toJson()['graphObjects'] as Map)['wallSegments'];
      final traces = document.toJson()['traces'];
      await tester
          .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      final finder = find.byType(InteractiveViewer);
      final viewer = tester.widget<InteractiveViewer>(finder);
      final center = tester.getSize(finder).center(Offset.zero);
      const zoom = 0.15;
      viewer.transformationController!
          .value = Matrix4.diagonal3Values(zoom, zoom, 1)
        ..setTranslationRaw(center.dx - 1200 * zoom, center.dy - 950 * zoom, 0);
      await tester.pump();
      final global = tester.getTopLeft(finder) + center;
      await tester.dragFrom(global + const Offset(30, 0), const Offset(40, 20));
      await tester.pumpAndSettle();
      final moved = document.annotations.single;
      expect(
          ((moved.point.offset - callout.point.offset) * zoom -
                  const Offset(40, 20))
              .distance,
          lessThan(7));
      expect(moved.extraProperties, callout.extraProperties);
      final editPoint = tester.getTopLeft(finder) +
          MatrixUtils.transformPoint(
              viewer.transformationController!.value, moved.point.offset);
      await tester.tapAt(editPoint);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(editPoint);
      await tester.pumpAndSettle();
      final editor = find.byKey(const ValueKey('inline-canvas-text-editor'));
      expect(editor, findsOneWidget);
      await tester.enterText(editor, 'Treatment needed here');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(document.annotations.single.label, 'Treatment needed here');
      expect(
          document.annotations.single.extraProperties, callout.extraProperties);
      expect((document.toJson()['graphObjects'] as Map)['wallSegments'], walls);
      expect(document.toJson()['traces'], traces);
    });
  }
}
