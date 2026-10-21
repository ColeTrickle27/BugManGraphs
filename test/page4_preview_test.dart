import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/widgets/canvas_toolbar.dart';
import 'package:bugman_graphs/services/measurement_format.dart';
import 'package:bugman_graphs/services/pat_pattern.dart';
import 'package:bugman_graphs/services/graph_pdf_export.dart';
import 'package:bugman_graphs/services/export_bounds_calculator.dart';
import 'package:bugman_graphs/theme/app_theme.dart';
import 'package:bugman_graphs/editor/editor_interaction_controller.dart';

GraphDocument sample() => GraphDocument.forJob(Job(
    customerName: 'Synthetic preview',
    serviceAddress: 'Preview property',
    pestPacLocationNumber: '',
    pestPacBillToNumber: '',
    serviceType: 'Preview',
    createdBy: 'Preview',
    createdDate: DateTime(2026, 10, 20)));

void main() {
  testWidgets(
      'drawing outside the old page keeps precise dimensions and zoom leaves data unchanged',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final document = sample();
    await tester
        .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    controller.value = Matrix4.identity()..translateByDouble(2000, 2000, 0, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    await tester.dragFrom(const Offset(300, 250), const Offset(240, 240));
    await tester.pump();
    expect(document.shapes, hasLength(1));
    expect(document.wallSegments.first.start.x, lessThan(0));
    expect(document.wallSegments.first.lengthFeet, closeTo(10, 1e-10));
    expect(ExportBoundsCalculator.forDocument(document).left, lessThan(0));
    final snapshot = document.toJson();
    controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
    await tester.pump();
    expect(document.toJson(), snapshot);
  });
  test('PAT preserves origins, rotated offsets and signed dashes as data', () {
    const raw = '*TEST, synthetic fixture\n90, 2,3, 4,5, 6,-7,0\n';
    final pattern = PatPattern.parse(raw);
    expect(pattern.original, raw);
    expect(pattern.lines.single.dashes, [6, -7, 0]);
    expect(pattern.lines.single.originFor(2).dx, closeTo(-8, 1e-10));
    expect(pattern.lines.single.originFor(2).dy, closeTo(11, 1e-10));
    expect(() => PatPattern.parse('*bad\n0,0,0,0,0'), throwsFormatException);
  });
  test('display precision never truncates source values', () {
    const value = 123.456789;
    expect(MeasurementFormat.linearFeet(value), '123 lf');
    expect(MeasurementFormat.squareFeet(value), '123 sf');
    expect(MeasurementFormat.acres(value), '123.46 ac');
    expect(value, 123.456789);
  });
  test('native PAT geometry preserves dash periods and row origins', () {
    final pattern = PatPattern.parse('*TEST\n0, 2,3, 4,5, 6,-7,0');
    final strokes = pattern.strokes(const Rect.fromLTRB(2, 3, 28, 8));
    expect(
        strokes.any((s) =>
            s.start == const Offset(2, 3) && s.end == const Offset(8, 3)),
        isTrue);
    expect(
        strokes.any((s) =>
            s.start == const Offset(15, 3) && s.end == const Offset(21, 3)),
        isTrue);
    expect(
        strokes.any((s) =>
            s.start == const Offset(6, 8) && s.end == const Offset(12, 8)),
        isTrue);
    expect(
        () =>
            pattern.strokes(const Rect.fromLTRB(0, 0, 10000, 10000), budget: 2),
        throwsStateError);
  });
  for (final finish in ['Enter', 'Tab', 'start', 'double']) {
    testWidgets(
        'geometry first polygon finish $finish and classification roundtrip',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.reset);
      final document = sample();
      await tester
          .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
      await tester.pumpAndSettle();
      tester
          .widget<CanvasToolbar>(find.byType(CanvasToolbar))
          .onDrawingPresetSelected(GraphDrawingPreset.mainStructure);
      await tester.pumpAndSettle();
      expect(find.text('Classify shape'), findsNothing);
      await tester.tap(find.text('Polygon'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(300, 250));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(const Offset(540, 250));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(const Offset(540, 490));
      await tester.pump(Duration(milliseconds: finish == 'double' ? 50 : 500));
      if (finish == 'start') {
        await tester.tapAt(const Offset(300, 250));
      } else if (finish == 'double') {
        await tester.tapAt(const Offset(540, 490));
      } else {
        await tester.sendKeyEvent(finish == 'Enter'
            ? LogicalKeyboardKey.enter
            : LogicalKeyboardKey.tab);
      }
      await tester.pumpAndSettle();
      expect(find.text('Classify shape'), findsOneWidget);
      await tester.tap(find.text('Patio').last);
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(document.shapes.single.preset, GraphDrawingPreset.patio);
      expect(GraphDocument.fromJson(document.toJson()).shapes.single.preset,
          GraphDrawingPreset.patio);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(document.shapes, isEmpty);
    });
  }
  for (final action in ['Cancel', 'Keep line', 'Fill area']) {
    testWidgets(
        'joined curve confirmation $action preserves the original structure',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.reset);
      final document = sample();
      await tester
          .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
      await tester.pumpAndSettle();
      final matrix = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final points = [
        const Offset(300, 250),
        const Offset(540, 250),
        const Offset(540, 490),
        const Offset(300, 490)
      ]
          .map((p) => GraphPoint.fromOffset(matrix
              .toScene(p - tester.getTopLeft(find.byType(InteractiveViewer)))))
          .toList();
      // Pointer coordinates are local to the canvas below the app bar.
      document.replaceWallSegments([
        for (var i = 0; i < 4; i++)
          WallSegment(start: points[i], end: points[(i + 1) % 4])
      ]);
      document.replaceShapes([
        const GraphShape(
            name: 'Existing',
            segmentIndexes: [0, 1, 2, 3],
            fillColor: Colors.grey,
            fillOpacity: 0.3,
            borderColor: Colors.black,
            borderWidth: 3,
            pattern: GraphShapePattern.grid,
            closed: true,
            rotationDegrees: 0,
            preset: GraphDrawingPreset.mainStructure)
      ]);
      await tester.pump();
      tester
          .widget<CanvasToolbar>(find.byType(CanvasToolbar))
          .onDrawingPresetSelected(GraphDrawingPreset.mainStructure);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Curved line'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(300, 250));
      await tester.tapAt(const Offset(420, 150));
      await tester.tapAt(const Offset(540, 250));
      await tester.pumpAndSettle();
      expect(find.text('Fill between shapes?'), findsOneWidget);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      if (action == 'Fill area') {
        await tester.tap(find.text('Patio').last);
        await tester.pump();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(document.shapes, hasLength(2));
        await tester.tap(find.byTooltip('Undo'));
        await tester.pump();
      }
      expect(document.shapes.first.name, 'Existing');
      expect(document.shapes, hasLength(1));
      expect(document.wallSegments, hasLength(action == 'Keep line' ? 5 : 4));
    });
  }
  for (final size in [const Size(1400, 900), const Size(390, 844)]) {
    testWidgets('preview screenshot ${size.width}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      final config =
          jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
              as Map<String, dynamic>;
      final flutter = (config['packages'] as List)
          .firstWhere((p) => p['name'] == 'flutter');
      final iconBytes = File.fromUri(Uri.parse('${flutter['rootUri']}/').resolve(
              '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'))
          .readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(iconBytes))))
          .load();
      for (final entry in const {
        'Ahem': 'assets/fonts/holloman/raxhHiqOu8IVPmnRc6SY1KXhnF_Y8fbfCL8.ttf',
        'Bitter':
            'assets/fonts/holloman/raxhHiqOu8IVPmnRc6SY1KXhnF_Y8fbfCL8.ttf',
        'Calistoga': 'assets/fonts/holloman/6NUU8F2OJg6MeR7l4e0vtA.ttf',
        'JetBrains Mono':
            'assets/fonts/holloman/tDbY2o-flEEny0FZhsfKu5WU4zr3E_BX0PnT8RD8yKxjPQ.ttf'
      }.entries) {
        await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
            .load();
      }
      final document = sample();
      await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildBugManTheme(),
              home: GraphCanvasScreen(document: document))));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final origin = tester.getTopLeft(find.byType(InteractiveViewer));
      final segments = <WallSegment>[];
      final shapes = <GraphShape>[];
      final patterns = size.width > 1000
          ? [
              GraphShapePattern.blockwork,
              GraphShapePattern.brick,
              GraphShapePattern.checkerplate
            ]
          : [GraphShapePattern.brick];
      for (var i = 0; i < patterns.length; i++) {
        final rect = Rect.fromLTWH(size.width > 1000 ? 240 + i * 300 : 145, 230,
            size.width > 1000 ? 240 : 210, 240);
        final points = [
          rect.topLeft,
          rect.topRight,
          rect.bottomRight,
          rect.bottomLeft
        ]
            .map((p) => GraphPoint.fromOffset(controller.toScene(p - origin)))
            .toList();
        final start = segments.length;
        segments.addAll([
          for (var j = 0; j < 4; j++)
            WallSegment(start: points[j], end: points[(j + 1) % 4])
        ]);
        shapes.add(GraphShape(
            name: patterns[i].name,
            segmentIndexes: [for (var j = 0; j < 4; j++) start + j],
            fillColor: Colors.amber,
            fillOpacity: 0.12,
            borderColor: Colors.brown,
            borderWidth: 2,
            pattern: patterns[i],
            closed: true,
            rotationDegrees: 0,
            preset: GraphDrawingPreset.patio));
      }
      document.replaceWallSegments(segments);
      document.replaceShapes(shapes);
      tester
          .widget<CanvasToolbar>(find.byType(CanvasToolbar))
          .onToolSelected(CanvasTool.select);
      await tester.pumpAndSettle();
      final toolbarBounds =
          tester.getRect(find.byKey(const ValueKey('canvas-quick-toolbar')));
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = data!.buffer.asUint8List();
        final dir = Directory('artifacts/page4')..createSync(recursive: true);
        File('${dir.path}/${size.width == 1400 ? 'desktop' : 'mobile'}-widget.png')
            .writeAsBytesSync(bytes);
        final crop = toolbarBounds.inflate(6).intersect(Offset.zero & size);
        final recorder = ui.PictureRecorder();
        Canvas(recorder)
            .drawImageRect(image, crop, Offset.zero & crop.size, Paint());
        final picture = recorder.endRecording();
        final toolbarImage =
            await picture.toImage(crop.width.ceil(), crop.height.ceil());
        final toolbarData =
            await toolbarImage.toByteData(format: ui.ImageByteFormat.png);
        File('${dir.path}/${size.width == 1400 ? 'desktop' : 'mobile'}-toolbar.png')
            .writeAsBytesSync(toolbarData!.buffer.asUint8List());
        toolbarImage.dispose();
        picture.dispose();
        if (size.width == 1400) {
          final pdf = await GraphPdfExport.build(
              graphPng: bytes, title: 'Synthetic page4 preview');
          File('${dir.path}/synthetic-preview.pdf').writeAsBytesSync(pdf);
        }
        image.dispose();
      });
      debugDisableShadows = true;
      expect(tester.takeException(), isNull);
    });
  }
}
