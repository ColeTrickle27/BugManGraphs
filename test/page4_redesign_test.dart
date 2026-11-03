import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/callout_geometry.dart';
import 'package:bugman_graphs/services/curve_measurements.dart';
import 'package:bugman_graphs/services/editor_viewport.dart';
import 'package:bugman_graphs/services/export_bounds_calculator.dart';
import 'package:bugman_graphs/widgets/shape_classification_dialog.dart';
import 'page4_preview_test.dart' show sample;

void main() {
  test('quadratic length measures arc, exact area includes curved boundary',
      () {
    const arc = WallSegment(
        start: GraphPoint(x: 0, y: 0),
        end: GraphPoint(x: 2, y: 0),
        controlPoint: GraphPoint(x: 1, y: 2));
    final expected = math.sqrt(5) + math.log(2 + math.sqrt(5)) / 2;
    expect(arc.lengthPixels, closeTo(expected, 1e-8));
    const chord =
        WallSegment(start: GraphPoint(x: 2, y: 0), end: GraphPoint(x: 0, y: 0));
    expect(CurveMeasurements.areaPixels([arc, chord]), closeTo(4 / 3, 1e-12));
    const collapsed = WallSegment(
        start: GraphPoint(x: 0, y: 0),
        end: GraphPoint(x: 0, y: 0),
        controlPoint: GraphPoint(x: 0, y: 10));
    expect(collapsed.lengthPixels, closeTo(10, 1e-8));
  });
  test(
      'zoom anchors, clamps and fitting negative world bounds preserve geometry',
      () {
    final matrix = Matrix4.identity()..translateByDouble(200, -70, 0, 1);
    const anchor = Offset(430, 280);
    final before = MatrixUtils.transformPoint(Matrix4.inverted(matrix), anchor);
    for (final scale in [.001, .01, .25, 1.0, 4.0, 32.0, 100.0]) {
      final zoomed = EditorViewport.zoomAt(matrix, anchor, scale);
      expect(
          (MatrixUtils.transformPoint(Matrix4.inverted(zoomed), anchor) -
                  before)
              .distance,
          lessThan(1e-8));
      expect(zoomed.getMaxScaleOnAxis(), scale.clamp(.01, 32));
    }
    const bounds = Rect.fromLTRB(-2500, -2000, 4200, 1700);
    const viewport = Rect.fromLTWH(120, 60, 1100, 650);
    final fitted =
        MatrixUtils.transformRect(EditorViewport.fit(bounds, viewport), bounds);
    expect(viewport.contains(fitted.topLeft), isTrue);
    expect(viewport.contains(fitted.bottomRight), isTrue);
    expect((fitted.center - viewport.center).distance, lessThan(1e-8));
  });
  testWidgets('bowed curve edge selects, moves and undoes without chord hit',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final document = sample();
    const segment = WallSegment(
        start: GraphPoint(x: 400, y: 200),
        end: GraphPoint(x: 400, y: 500),
        controlPoint: GraphPoint(x: 100, y: 350));
    document.replaceWallSegments([segment]);
    document.replaceShapes([
      const GraphShape(
          name: 'Curve',
          segmentIndexes: [0],
          fillColor: null,
          fillOpacity: 0,
          borderColor: Colors.green,
          borderWidth: 3,
          pattern: GraphShapePattern.none,
          closed: false,
          rotationDegrees: 0,
          extraProperties: {'sourceTool': 'curve'})
    ]);
    await tester
        .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
    await tester.pumpAndSettle();
    final viewer = find.byType(InteractiveViewer);
    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    controller.value = Matrix4.identity();
    await tester.pump();
    final curveMid = tester.getTopLeft(viewer) + const Offset(250, 350);
    expect(CurveMeasurements.distanceTo(segment, const Offset(250, 350)),
        lessThan(.25));
    expect(CurveMeasurements.distanceTo(segment, const Offset(400, 350)),
        greaterThan(100));
    await tester.tapAt(curveMid);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Change shape type'), findsOneWidget);
    await tester.dragFrom(curveMid, const Offset(40, 20));
    await tester.pumpAndSettle();
    expect(document.wallSegments.single.controlPoint!.x, closeTo(140, .01));
    expect(document.wallSegments.single.start.x, closeTo(440, .01));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(document.wallSegments.single.controlPoint!.x, 100);
  });
  testWidgets(
      'compact classification searches secondary types and validates custom text',
      (tester) async {
    ShapeClassificationChoice? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showDialog<ShapeClassificationChoice>(
                          context: context,
                          builder: (_) => const ShapeClassificationDialog(
                              initial: GraphDrawingPreset.patio));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(7));
    await tester.tap(find.text('More types'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'driveway');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Driveway'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driveway'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result!.preset, GraphDrawingPreset.driveway);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Outdoor kitchen');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result!.description, 'Outdoor kitchen');
  });
  testWidgets(
      'empty mouse and touch context offers exactly three choices with escape',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final document = sample();
    await tester
        .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await gesture.down(const Offset(600, 350));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<int>), findsNWidgets(3));
    expect(find.text('Sketch structure'), findsOneWidget);
    expect(find.text('Add note'), findsOneWidget);
    expect(find.text('Callout box'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Callout box'), findsNothing);
    await tester.longPressAt(const Offset(600, 350));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<int>), findsNWidgets(3));
    expect(document.annotations, isEmpty);
  });
  testWidgets('Escape discards a new callout text draft', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final document = sample();
    await tester
        .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await gesture.down(const Offset(500, 350));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Callout box'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('inline-canvas-text-editor')),
        'Discard this draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(document.annotations, isEmpty);
    expect(
        find.byKey(const ValueKey('inline-canvas-text-editor')), findsNothing);
  });
  testWidgets('callout create edit move resize anchor save delete undo redo',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final document = sample();
    await tester
        .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
    await tester.pumpAndSettle();
    final viewer = find.byType(InteractiveViewer);
    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    final origin = tester.getTopLeft(viewer);
    const click = Offset(500, 350);
    final world = controller.toScene(click - origin);
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await gesture.down(click);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Callout box'));
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('inline-canvas-text-editor'));
    await tester.enterText(editor, 'Synthetic callout');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    var annotation = document.annotations.single;
    expect(CalloutGeometry.tip(annotation), world);
    Offset screen(Offset point) =>
        origin + MatrixUtils.transformPoint(controller.value, point);
    final initialCenter = annotation.point.offset;
    await tester.dragFrom(
        screen(initialCenter + const Offset(30, 0)), const Offset(70, 40));
    await tester.pumpAndSettle();
    annotation = document.annotations.single;
    expect(
        (annotation.point.offset - initialCenter - const Offset(70, 40))
            .distance,
        lessThan(.01));
    expect(CalloutGeometry.tip(annotation), world);
    final box = CalloutGeometry.box(annotation);
    await tester.dragFrom(screen(box.bottomRight), const Offset(80, 40));
    await tester.pumpAndSettle();
    annotation = document.annotations.single;
    expect(CalloutGeometry.box(annotation).width, greaterThan(box.width));
    await tester.dragFrom(screen(world), const Offset(-40, 20));
    await tester.pumpAndSettle();
    expect(CalloutGeometry.tip(document.annotations.single),
        world + const Offset(-40, 20));
    final restored = GraphDocument.fromJson(document.toJson());
    expect(restored.annotations.single.extraProperties,
        document.annotations.single.extraProperties);
    final bounds = ExportBoundsCalculator.forDocument(document);
    expect(
        bounds
            .contains(CalloutGeometry.box(document.annotations.single).topLeft),
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(document.annotations, isEmpty);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(document.annotations, hasLength(1));
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(document.annotations, isEmpty);
  });
}
