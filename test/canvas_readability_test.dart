import 'package:bugman_graphs/editor/label_presentation.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/widgets/graph_annotations_painter.dart';
import 'package:bugman_graphs/widgets/trace_geometry_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'support/crowded_canvas_fixture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const marker = GraphAnnotation(
    id: 'synthetic',
    kind: GraphAnnotationKind.marker,
    point: GraphPoint(x: 500, y: 500),
    label: 'Side Door',
  );
  test('marker has a stable 44 pixel touch target at different zooms', () {
    for (final zoom in [0.03, 0.1, 0.5, 1.0, 4.0]) {
      final labels = LabelPresentation(zoom: zoom, bounded: true);
      expect(
        GraphAnnotationsPainter.containsPoint(
          marker,
          marker.point.offset + Offset(21 / zoom, 0),
          labels,
        ),
        isTrue,
      );
      expect(
        GraphAnnotationsPainter.containsPoint(
          marker,
          marker.point.offset + Offset(100 + 100 / zoom, -100 - 100 / zoom),
          labels,
        ),
        isFalse,
      );
    }
  });
  test(
    'text wrapping and hit bounds follow displayed text at fit and close zoom',
    () {
      const text = GraphAnnotation(
        id: 'text',
        kind: GraphAnnotationKind.text,
        point: GraphPoint(x: 500, y: 500),
        label: 'Treatment Area',
        fontSize: 24,
      );
      for (final zoom in [0.03, 0.2, 1.0, 5.0]) {
        final labels = LabelPresentation(zoom: zoom, bounded: true);
        final bounds = GraphAnnotationsPainter.textBounds(text, labels);
        expect(bounds.height * zoom, lessThan(65));
        expect(bounds.width, greaterThan(bounds.height));
        expect(
          GraphAnnotationsPainter.containsPoint(text, bounds.centerRight, labels),
          isTrue,
        );
      }
    },
  );
  test(
    'trace decorations have bounded screen scale while export remains unscaled',
    () {
      for (final zoom in [0.03, 0.2, 1.0, 5.0]) {
        final scale = TraceGeometryPainter.displayScaleFor(
          [],
          LabelPresentation(zoom: zoom, bounded: true),
        );
        expect(scale * zoom, inInclusiveRange(0.75, 1.3));
      }
      expect(
        TraceGeometryPainter.displayScaleFor([], const LabelPresentation()),
        1,
      );
    },
  );
  for (final viewport in [const Size(390, 844), const Size(1400, 900)]) {
    testWidgets('overlaid marker wins over selected handles at $viewport', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      addTearDown(tester.view.reset);
      final document = crowdedCanvasFixture();
      final beforeWalls = (document.toJson()['graphObjects'] as Map)['wallSegments'];
      final beforeTrace = document.traces.single.toJson();
      await tester.pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      final finder = find.byType(InteractiveViewer);
      final viewer = tester.widget<InteractiveViewer>(finder);
      final controller = viewer.transformationController!;
      controller.value = Matrix4.diagonal3Values(0.15, 0.15, 1)..setTranslationRaw(20, 40, 0);
      await tester.pump();
      Offset screen(Offset scene) => tester.getTopLeft(finder) + MatrixUtils.transformPoint(controller.value, scene);
      await tester.tapAt(screen(const Offset(1200, 900)));
      await tester.pump();
      await tester.dragFrom(screen(const Offset(850, 700)), const Offset(45, 30));
      await tester.pumpAndSettle();
      expect(document.annotations.last.point.x, greaterThan(850));
      expect(document.annotations.first.point.x, 850);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(document.annotations.last.point.x, 850);
      await tester.tapAt(screen(const Offset(850, 700)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose overlap'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Side Door'));
      await tester.pumpAndSettle();
      await tester.dragFrom(screen(const Offset(850, 700)), const Offset(45, 30));
      await tester.pumpAndSettle();
      expect(document.annotations.first.point.x, greaterThan(850));
      expect(document.annotations.last.point.x, 850);
      expect((document.toJson()['graphObjects'] as Map)['wallSegments'], beforeWalls);
      expect(document.traces.single.toJson(), beforeTrace);
      final reopened = GraphDocument.fromJson(document.toJson());
      expect((reopened.toJson()['graphObjects'] as Map)['wallSegments'], beforeWalls);
      expect(reopened.traces.single.toJson(), beforeTrace);
    });
  }

}
