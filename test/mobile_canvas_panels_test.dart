import 'dart:ui' as ui;

import 'package:bugman_graphs/editor/label_presentation.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/export_bounds_calculator.dart';
import 'package:bugman_graphs/services/trace_projection_service.dart';
import 'package:bugman_graphs/widgets/canvas_toolbar.dart';
import 'package:bugman_graphs/widgets/trace_geometry_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

GraphDocument yardDocument() {
  const geo = [
    GeoPoint(latitude: 35.09445, longitude: -78.61855),
    GeoPoint(latitude: 35.09445, longitude: -78.61805),
    GeoPoint(latitude: 35.09385, longitude: -78.61805),
    GeoPoint(latitude: 35.0938, longitude: -78.61775),
    GeoPoint(latitude: 35.0936, longitude: -78.6176),
    GeoPoint(latitude: 35.0929, longitude: -78.61795),
    GeoPoint(latitude: 35.09285, longitude: -78.61815),
  ];
  const home = [
    GeoPoint(latitude: 35.09348, longitude: -78.61803),
    GeoPoint(latitude: 35.09348, longitude: -78.61788),
    GeoPoint(latitude: 35.0933, longitude: -78.61788),
    GeoPoint(latitude: 35.0933, longitude: -78.61803),
  ];
  final projection = TraceProjectionService.projectToCanvas(geo,
      canvasSize: const Size(3600, 2600));
  return GraphDocument(
      customer: const GraphCustomerInfo(
          name: 'Mobile yard QA',
          serviceAddress: '',
          pestPacBillToNumber: '',
          pestPacLocationNumber: '',
          serviceType: 'Yard measurement',
          createdBy: 'QA'),
      traces: [
        TraceGeometry(
            id: 'yard',
            label: 'Yard',
            geoPoints: geo,
            canvasPoints: projection.canvasPoints,
            exclusions: [
              TraceGeometry(
                  id: 'home',
                  label: 'Home',
                  geoPoints: home,
                  canvasPoints: TraceProjectionService.projectToCanvas(home,
                          canvasSize: const Size(3600, 2600),
                          referencePoints: geo)
                      .canvasPoints)
            ],
            metersPerCanvasUnit: projection.metersPerCanvasUnit)
      ],
      layers: const {
        'trace': GraphLayerState(visible: true)
      })
    ..markClean();
}

TransformationController viewportController(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!;

void expectUnobscuredYard(WidgetTester tester, GraphDocument document,
    {Finder? panel}) {
  final viewport = tester.getRect(find.byType(InteractiveViewer));
  // These bounds include trace labels, imagery and rotation-handle clearance,
  // rather than checking only the panel dimensions or geographic vertices.
  final painted = MatrixUtils.transformRect(viewportController(tester).value,
          ExportBoundsCalculator.forDocument(document, padding: 0))
      .shift(viewport.topLeft);
  expect(viewport.inflate(.1).contains(painted.topLeft), isTrue);
  expect(viewport.inflate(.1).contains(painted.bottomRight), isTrue);
  final summary = find.byKey(const ValueKey('mobile-trace-summary'));
  if (summary.evaluate().isNotEmpty) {
    expect(viewport.overlaps(tester.getRect(summary)), isFalse);
  }
  final quickToolbar = find.byType(CanvasQuickToolbar);
  if (quickToolbar.evaluate().isNotEmpty) {
    expect(viewport.overlaps(tester.getRect(quickToolbar)), isFalse);
  }
  if (panel != null) {
    final panelRect = tester.getRect(panel);
    expect(viewport.overlaps(panelRect), isFalse);
    expect(painted.overlaps(panelRect), isFalse);
    if (summary.evaluate().isNotEmpty) {
      expect(panelRect.overlaps(tester.getRect(summary)), isFalse);
    }
    if (quickToolbar.evaluate().isNotEmpty) {
      expect(panelRect.overlaps(tester.getRect(quickToolbar)), isFalse);
    }
  }
}

Future<void> openProperties(WidgetTester tester) async {
  if (find.byTooltip('More quick tools').evaluate().isEmpty) {
    await tester.tap(find.byTooltip('Object properties'));
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(find.byTooltip('More quick tools'));
  await tester.pumpAndSettle();
  await tester
      .tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'Properties'));
  await tester.pumpAndSettle();
}

Future<void> expectPaintedLabelsUnclipped(
    WidgetTester tester, GraphDocument document) async {
  final size = tester.getSize(find.byType(InteractiveViewer));
  final matrix = viewportController(tester).value;
  // Paint the real trace into a transparent area larger than the viewport.
  // Any ink in the outer border would be clipped in the actual editor.
  const border = 100;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(border.toDouble(), border.toDouble());
  canvas.transform(matrix.storage);
  TraceGeometryPainter(
          traces: document.traces,
          selectedTraceIndex: 0,
          showDetails: false,
          labels: LabelPresentation(
              zoom: matrix.getMaxScaleOnAxis(), bounded: true))
      .paint(canvas, size);
  final picture = recorder.endRecording();
  final width = size.width.ceil() + border * 2;
  final height = size.height.ceil() + border * 2;
  final pixels = await tester.runAsync(() async {
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!;
  });
  picture.dispose();
  var clippedPixels = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (x >= border &&
          x < border + size.width &&
          y >= border &&
          y < border + size.height) {
        continue;
      }
      if (pixels!.getUint8((y * width + x) * 4 + 3) > 20) {
        clippedPixels++;
      }
    }
  }
  expect(clippedPixels, 0,
      reason: 'Trace labels must not paint outside the canvas');
}

void main() {
  for (final size in [
    const Size(390, 640),
    const Size(390, 540),
    const Size(844, 390)
  ]) {
    testWidgets(
        'yard and labels stay unobscured while panels scroll, switch and edit at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      final document = yardDocument();
      final before = document.toJson();
      final beforeTrace = document.traces.single.toJson();
      await tester
          .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
      await tester.pumpAndSettle();
      expectUnobscuredYard(tester, document);
      expect(find.text('Net yard: 1.82 ac'), findsOneWidget);
      expect(find.text('Total: 1.89 ac · Excluded: 0.07 ac'), findsOneWidget);

      await tester.tap(find.byTooltip('Show main toolbar'));
      await tester.pumpAndSettle();
      final tools = find.byType(CanvasToolbar);
      final inspector = find.byKey(const ValueKey('canvas-inspector-panel'));
      expectUnobscuredYard(tester, document, panel: tools);
      final hide = find.byTooltip('Hide main toolbar');
      final hideRect = tester.getRect(hide);
      expect(hideRect.height, greaterThanOrEqualTo(44));
      await tester.drag(
          find
              .descendant(
                  of: tools, matching: find.byType(SingleChildScrollView))
              .first,
          const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(tester.getRect(hide), hideRect);
      expectUnobscuredYard(tester, document, panel: tools);

      await openProperties(tester);
      expect(tools, findsNothing);
      expectUnobscuredYard(tester, document, panel: inspector);
      expect(find.text('Select an object to edit its properties.'),
          findsOneWidget);
      await tester.tap(find.byTooltip('Show main toolbar'));
      await tester.pumpAndSettle();
      expect(inspector, findsNothing);
      await tester.tap(find.byTooltip('Hide main toolbar'));
      await tester.pumpAndSettle();
      expectUnobscuredYard(tester, document);
      expect(document.toJson(), before);

      // Select the yard through the live canvas, then edit through the same
      // quick menu and scrollable inspector used on a touch screen.
      await tester.tap(find.byTooltip('Select (V)'));
      await tester.pumpAndSettle();
      final center = document.traces.single.canvasPoints
              .map((p) => p.offset)
              .reduce((a, b) => a + b) /
          document.traces.single.canvasPoints.length.toDouble();
      await tester.tapAt(tester.getTopLeft(find.byType(InteractiveViewer)) +
          MatrixUtils.transformPoint(viewportController(tester).value, center));
      await tester.pumpAndSettle();
      await openProperties(tester);
      final label = find.byKey(const ValueKey('trace-0'));
      await tester.ensureVisible(label);
      await tester.enterText(label, 'Front yard');
      if (size.width < size.height) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pumpAndSettle();
        expectUnobscuredYard(tester, document, panel: inspector);
        tester.view.viewInsets = const FakeViewPadding();
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(document.traces.single.label, 'Front yard');
      expectUnobscuredYard(tester, document, panel: inspector);
      final propertiesHide =
          tester.getRect(find.byTooltip('Collapse properties'));
      await tester.scrollUntilVisible(find.text('Edge measurements'), 80,
          scrollable: find
              .descendant(of: inspector, matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byTooltip('Collapse properties')),
          propertiesHide);
      await Scrollable.ensureVisible(
          tester.element(find.text('Edge measurements')),
          alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edge measurements'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Edge 1'), 60,
          scrollable: find
              .descendant(of: inspector, matching: find.byType(Scrollable))
              .first);
      expect(find.text('Edge 1'), findsOneWidget);
      expectUnobscuredYard(tester, document, panel: inspector);
      expect(document.traces.single.toJson(),
          {...beforeTrace, 'label': 'Front yard'});
      await expectPaintedLabelsUnclipped(tester, document);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('canvas accepts drawing and undo beside an open inspector',
      (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final document = yardDocument();
    final trace = document.traces.single.toJson();
    await tester
        .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    await openProperties(tester);
    final viewport = tester.getRect(find.byType(InteractiveViewer));
    final inspector = find.byKey(const ValueKey('canvas-inspector-panel'));
    expect(viewport.overlaps(tester.getRect(inspector)), isFalse);
    await tester.tapAt(viewport.center - const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(viewport.center + const Offset(40, 20));
    await tester.pumpAndSettle();
    expect(document.wallSegments, isNotEmpty);
    expect(inspector, findsOneWidget);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(document.wallSegments, isEmpty);
    expect(document.traces.single.toJson(), trace);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual pan and zoom survive panels, rotation and keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final document = yardDocument();
    final before = document.toJson();
    await tester
        .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
    await tester.pumpAndSettle();
    final controller = viewportController(tester);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pan (H)'));
    await tester.pumpAndSettle();
    await tester.dragFrom(
        tester.getCenter(find.byType(InteractiveViewer)), const Offset(20, 15));
    await tester.pumpAndSettle();
    final zoom = controller.value.getMaxScaleOnAxis();
    final anchor = controller.toScene(
        tester.getSize(find.byType(InteractiveViewer)).center(Offset.zero));
    Future<void> expectAnchor() async {
      await tester.pumpAndSettle();
      final center = controller.toScene(
          tester.getSize(find.byType(InteractiveViewer)).center(Offset.zero));
      expect((center - anchor).distance, lessThan(.001));
      expect(controller.value.getMaxScaleOnAxis(), zoom);
    }

    await tester.tap(find.byTooltip('Show main toolbar'));
    await expectAnchor();
    await tester.tap(find.byTooltip('Hide main toolbar'));
    await expectAnchor();
    await openProperties(tester);
    await expectAnchor();
    tester.view.physicalSize = const Size(844, 390);
    await expectAnchor();
    tester.view.physicalSize = const Size(390, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await expectAnchor();
    final viewport = tester.getRect(find.byType(InteractiveViewer));
    final panel =
        tester.getRect(find.byKey(const ValueKey('canvas-inspector-panel')));
    expect(viewport.overlaps(panel), isFalse);
    expect(document.toJson(), before);
    expect(tester.takeException(), isNull);
  });
}
