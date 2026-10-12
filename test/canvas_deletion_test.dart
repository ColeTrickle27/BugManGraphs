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
