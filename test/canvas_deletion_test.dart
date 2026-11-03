import 'dart:ui' show PointerDeviceKind;
import 'dart:math' as math;
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/freehand_stroke.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/crowded_canvas_fixture.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1400, 900)]) {
    testWidgets(
        'middle of three shapes preserves remaining geometry and clears history hover at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      var document = deletionFixture('structure', false);
      final source = document.wallSegments.toList();
      final shape = document.shapes.single;
      document.replaceWallSegments([
        for (final dx in [-900.0, 0.0, 900.0])
          for (final segment in source)
            segment.copyWith(
                start:
                    GraphPoint.fromOffset(segment.start.offset + Offset(dx, 0)),
                end: GraphPoint.fromOffset(segment.end.offset + Offset(dx, 0)))
      ]);
      document.replaceShapes([
        for (var i = 0; i < 3; i++)
          shape.copyWith(
              name: 'Structure ${i + 1}',
              segmentIndexes: [for (var n = 0; n < 4; n++) i * 4 + n])
      ]);
      final extended = document.toJson();
      final objects = extended['graphObjects'] as Map;
      for (final wall in objects['wallSegments'] as List) { (wall as Map)['futureWall'] = {'source': (wall['start'] as Map)['x']}; }
      for (final shape in objects['shapes'] as List) { (shape as Map)['futureShape'] = shape['name']; }
      document = GraphDocument.fromJson(extended);
      final original = document.toJson();
      await tester
          .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      final finder = find.byType(InteractiveViewer);
      final viewer = tester.widget<InteractiveViewer>(finder);
      final center = tester.getSize(finder).center(Offset.zero);
      const zoom = 0.12;
      viewer.transformationController!
          .value = Matrix4.diagonal3Values(zoom, zoom, zoom)
        ..setTranslationRaw(center.dx - 1200 * zoom, center.dy - 950 * zoom, 0);
      await tester.pump();
      Offset screen(double x) =>
          tester.getTopLeft(finder) + center + Offset((x - 1200) * zoom, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: screen(1200));
      await tester.tapAt(screen(1200));
      await tester.pump();
      await mouse.moveTo(screen(2100));
      await tester.pump();
      dynamic painter() => tester
          .widget<CustomPaint>(find.byKey(const ValueKey('graph-canvas-paint')))
          .foregroundPainter as dynamic;
      expect(painter().hoveredShapeIndex, 2);
      await tester.ensureVisible(find.byTooltip('Delete selection'));
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.byTooltip('Delete selection')));
      await tester.tap(find.byTooltip('Delete selection'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(painter().hoveredShapeIndex, isNull);
      expect(
          document.shapes.map((s) => s.name), ['Structure 1', 'Structure 3']);
      final originalObjects = original['graphObjects'] as Map;
      final after = document.toJson()['graphObjects'] as Map;
      final originalWalls = originalObjects['wallSegments'] as List;
      expect(after['wallSegments'],
          [...originalWalls.take(4), ...originalWalls.skip(8)]);
      expect(document.shapes.last.segmentIndexes, [4, 5, 6, 7]);
      await mouse.moveTo(screen(2100));
      await tester.pump();
      expect(painter().hoveredShapeIndex, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(painter().hoveredShapeIndex, isNull);
      expect(document.toJson()['graphObjects'], originalObjects);
      await mouse.moveTo(screen(2100));
      await tester.pump();
      expect(painter().hoveredShapeIndex, 2);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(painter().hoveredShapeIndex, isNull);
      expect(document.toJson()['graphObjects'], after);
      expect(GraphDocument.fromJson(document.toJson()).toJson()['graphObjects'],
          after);
      await mouse.removePointer();
    });
  }
  for (final kind in [
    'structure',
    'measure',
    'annotation',
    'segment',
    'trace',
    'freehand'
  ]) {
    for (final keepOther in [false, true]) {
      for (final size in [const Size(390, 844), const Size(1400, 900)]) {
        testWidgets(
            '$kind delete/repeat/undo/redo/reopen ($keepOther unrelated, $size)',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);
          final document = deletionFixture(kind, keepOther);
          final original = document.toJson();
          await tester.pumpWidget(
              MaterialApp(home: GraphCanvasScreen(document: document)));
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
          final finder = find.byType(InteractiveViewer);
          final center = tester.getSize(finder).center(Offset.zero);
          tester
              .widget<InteractiveViewer>(finder)
              .transformationController!
              .value = Matrix4.identity()
            ..setTranslationRaw(center.dx - 1200, center.dy - 950, 0);
          await tester.pump();
          final point = tester.getTopLeft(finder) + center;
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: point);
          await mouse.moveTo(point);
          await tester.tapAt(point);
          await tester.pump();
          await tester.ensureVisible(find.byTooltip('Delete selection'));
          await tester.pumpAndSettle();
          await mouse
              .moveTo(tester.getCenter(find.byTooltip('Delete selection')));
          await tester.tap(find.byTooltip('Delete selection'));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
          final deleted = document.toJson();
          final objects = deleted['graphObjects'] as Map;
          expect(document.shapes, isEmpty);
          expect(document.freehandStrokes, isEmpty);
          expect(document.traces, isEmpty);
          expect(document.wallSegments, hasLength(keepOther ? 1 : 0));
          expect(document.annotations, hasLength(keepOther ? 1 : 0));
          if (keepOther) {
            expect(
                (objects['wallSegments'] as List).single,
                ((original['graphObjects'] as Map)['wallSegments'] as List)
                    .last);
            expect(
                (objects['annotations'] as List).single,
                ((original['graphObjects'] as Map)['annotations'] as List)
                    .last);
          }
          await tester.tap(find.byTooltip('Delete selection'));
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          expect(document.toJson()['graphObjects'], objects);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          expect(document.toJson()['graphObjects'], original['graphObjects']);
          expect(document.toJson()['traces'], original['traces']);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          expect(document.toJson()['graphObjects'], deleted['graphObjects']);
          final reopened = GraphDocument.fromJson(document.toJson());
          expect(reopened.toJson()['graphObjects'], deleted['graphObjects']);
          expect(reopened.toJson()['traces'], deleted['traces']);
          expect(tester.takeException(), isNull);
          expect(find.byType(ErrorWidget), findsNothing);
          await mouse.removePointer();
        });
      }
    }
  }
  for (final size in [const Size(390, 844), const Size(1400, 900)]) {
    testWidgets('deleting hovered last shape keeps canvas rendered at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final document = crowdedCanvasFixture()..replaceAnnotations([]);
      await tester
          .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      final finder = find.byType(InteractiveViewer);
      final viewer = tester.widget<InteractiveViewer>(finder);
      final center = tester.getSize(finder).center(Offset.zero);
      viewer.transformationController!.value = Matrix4.identity()
        ..setTranslationRaw(center.dx - 2160, center.dy - 1885, 0);
      await tester.pump();
      final point = tester.getTopLeft(finder) + center;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: point);
      await mouse.moveTo(point);
      await tester.pump();
      await tester.tapAt(point);
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Delete selection'));
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.byTooltip('Delete selection')));
      await tester.tap(find.byTooltip('Delete selection'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(document.shapes, hasLength(1));
      expect(find.byType(ErrorWidget), findsNothing);
      await mouse.removePointer();
    });
  }
}

GraphDocument deletionFixture(String kind, bool keepOther) {
  final document = crowdedCanvasFixture();
  final main = document.shapes.first;
  const center = Offset(1200, 950);
  final corners = [
    const Offset(850, 700),
    const Offset(1550, 700),
    const Offset(1550, 1200),
    const Offset(850, 1200)
  ].map((p) {
    final d = p - center;
    const angle = 0.5;
    return GraphPoint.fromOffset(center +
        Offset(d.dx * math.cos(angle) - d.dy * math.sin(angle),
            d.dx * math.sin(angle) + d.dy * math.cos(angle)));
  }).toList();
  final walls = kind == 'structure'
      ? [
          for (var i = 0; i < 4; i++)
            WallSegment(start: corners[i], end: corners[(i + 1) % 4])
        ]
      : kind == 'measure' || kind == 'segment'
          ? [
              const WallSegment(
                  start: GraphPoint(x: 1000, y: 950),
                  end: GraphPoint(x: 1400, y: 950))
            ]
          : <WallSegment>[];
  document.replaceShapes(kind == 'structure'
      ? [main.copyWith(rotationDegrees: 0.5 * 180 / math.pi)]
      : kind == 'measure'
          ? [
              main.copyWith(
                  preset: GraphDrawingPreset.measurementLine,
                  name: 'Measure',
                  closed: false,
                  segmentIndexes: [0])
            ]
          : []);
  if (keepOther) {
    walls.add(const WallSegment(
        start: GraphPoint(x: 200, y: 200), end: GraphPoint(x: 400, y: 200)));
  }
  document.replaceWallSegments(walls);
  document.replaceAnnotations([
    if (kind == 'annotation')
      const GraphAnnotation(
          id: 'delete-note',
          kind: GraphAnnotationKind.text,
          point: GraphPoint(x: 1200, y: 950),
          label: 'Treatment needed'),
    if (keepOther)
      const GraphAnnotation(
          id: 'keep-note',
          kind: GraphAnnotationKind.text,
          point: GraphPoint(x: 2000, y: 1400),
          label: 'Keep this note'),
  ]);
  document.replaceFreehandStrokes(kind == 'freehand'
      ? [
          const FreehandStroke(points: [
            GraphPoint(x: 1000, y: 950),
            GraphPoint(x: 1400, y: 950)
          ])
        ]
      : []);
  document.replaceTraces(kind == 'trace'
      ? [
          document.traces.single.copyWith(canvasPoints: corners, geoPoints: [
            for (final p in corners)
              GeoPoint(latitude: p.y * 0.00000012, longitude: p.x * 0.00000012)
          ])
        ]
      : []);
  return document;
}
