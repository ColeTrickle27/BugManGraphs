import 'package:bugman_graphs/editor/label_presentation.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/widgets/graph_annotations_painter.dart';
import 'package:bugman_graphs/widgets/trace_geometry_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/services/measurement_service.dart';
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

  for (final zoom in [0.03, 0.15, 1.0]) {
    for (final shapeIndex in [0, 1]) {
      for (final selected in [false, true]) {
        testWidgets('center drag moves shape $shapeIndex at zoom $zoom (selected: $selected)', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.reset);
          final document = crowdedCanvasFixture()..replaceAnnotations([]);
          final before = document.wallSegments.toList();
          final beforeTrace = document.traces.single.toJson();
          final indexes = document.shapes[shapeIndex].segmentIndexes;
          final center = shapeIndex == 0 ? const Offset(1200, 950) : const Offset(2160, 1885);
          await tester.pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
          final finder = find.byType(InteractiveViewer);
          final viewer = tester.widget<InteractiveViewer>(finder);
          final viewportCenter = tester.getSize(finder).center(Offset.zero);
          viewer.transformationController!.value = Matrix4.diagonal3Values(zoom, zoom, 1)
            ..setTranslationRaw(viewportCenter.dx - center.dx * zoom, viewportCenter.dy - center.dy * zoom, 0);
          await tester.pump();
          final start = tester.getTopLeft(finder) + viewportCenter;
          if (selected) {
            await tester.tapAt(start);
            await tester.pump();
          }
          await tester.dragFrom(start, const Offset(36, 24));
          await tester.pumpAndSettle();
          for (var i = 0; i < before.length; i++) {
            final moved = document.wallSegments[i];
            if (indexes.contains(i)) {
              final delta = moved.start.offset - before[i].start.offset;
              expect(delta.distance, greaterThan(0));
              expect((moved.end.offset - before[i].end.offset - delta).distance, lessThan(0.00001));
              expect(moved.lengthFeet, closeTo(before[i].lengthFeet, 0.00001));
            } else {
              expect(moved.start.offset, before[i].start.offset);
              expect(moved.end.offset, before[i].end.offset);
            }
          }
          expect(document.traces.single.toJson(), beforeTrace);
        });
      }
    }
  }

  for (final zoom in [0.03, 0.15, 1.0]) {
    testWidgets('selected trace center moves all vertices at zoom $zoom', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      const points = [GraphPoint(x:300,y:300), GraphPoint(x:1200,y:300),
        GraphPoint(x:1200,y:900), GraphPoint(x:300,y:900)];
      final document = crowdedCanvasFixture()
        ..replaceAnnotations([])..replaceShapes([])..replaceWallSegments([]);
      document.replaceTraces([document.traces.single.copyWith(canvasPoints: points,
        geoPoints: [for(final p in points) GeoPoint(latitude:p.y*0.00000012,longitude:p.x*0.00000012)])]);
      final before = document.traces.single;
      final measurement = MeasurementService.measureTrace(before, status:MeasurementAccuracyStatus.estimated);
      await tester.pumpWidget(MaterialApp(home:GraphCanvasScreen(document:document)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      final finder = find.byType(InteractiveViewer);
      final viewer = tester.widget<InteractiveViewer>(finder);
      final center = tester.getSize(finder).center(Offset.zero);
      viewer.transformationController!.value = Matrix4.diagonal3Values(zoom,zoom,1)
        ..setTranslationRaw(center.dx-750*zoom,center.dy-600*zoom,0);
      await tester.pump();
      final start = tester.getTopLeft(finder)+center;
      await tester.tapAt(start);await tester.pump();
      await tester.dragFrom(start,const Offset(36,24));await tester.pumpAndSettle();
      final moved = document.traces.single;
      final delta = moved.canvasPoints.first.offset-before.canvasPoints.first.offset;
      expect(delta.distance,greaterThan(0));
      for(var i=0;i<points.length;i++) {
        expect((moved.canvasPoints[i].offset-before.canvasPoints[i].offset-delta).distance,lessThan(0.00001));
      }
      final after = MeasurementService.measureTrace(moved,status:MeasurementAccuracyStatus.estimated);
      expect(after.linearFeet,closeTo(measurement.linearFeet,0.0001));
      expect(after.squareFeet,closeTo(measurement.squareFeet,0.0001));
    });
  }

  for (final zoom in [0.15, 1.0]) {
    testWidgets('choosing underlying structure does not capture a distinct marker at zoom $zoom', (tester) async {
      tester.view.devicePixelRatio=1;tester.view.physicalSize=const Size(1400,900);
      addTearDown(tester.view.reset);
      final document=crowdedCanvasFixture();
      document.replaceAnnotations([...document.annotations, const GraphAnnotation(id:'distinct',
        kind:GraphAnnotationKind.marker,point:GraphPoint(x:1450,y:1100),label:'Distinct marker')]);
      final beforeWalls=(document.toJson()['graphObjects'] as Map)['wallSegments'];
      final beforeTrace=document.traces.single.toJson();
      await tester.pumpWidget(MaterialApp(home:GraphCanvasScreen(document:document)));
      await tester.pumpAndSettle();await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      final finder=find.byType(InteractiveViewer);
      final viewer=tester.widget<InteractiveViewer>(finder);
      viewer.transformationController!.value=Matrix4.diagonal3Values(zoom,zoom,1)
        ..setTranslationRaw(200-850*zoom,260-700*zoom,0);
      await tester.pump();
      Offset screen(Offset point)=>tester.getTopLeft(finder)+MatrixUtils.transformPoint(viewer.transformationController!.value,point);
      await tester.tapAt(screen(const Offset(850,700)));await tester.pumpAndSettle();
      await tester.tap(find.text('Choose overlap'));await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile,'Main Structure'));await tester.pumpAndSettle();
      await tester.dragFrom(screen(const Offset(1450,1100)),const Offset(36,24));
      await tester.pumpAndSettle();
      expect(document.annotations.last.point.x,greaterThan(1450));
      expect((document.toJson()['graphObjects'] as Map)['wallSegments'],beforeWalls);
      expect(document.traces.single.toJson(),beforeTrace);
    });
  }

}
