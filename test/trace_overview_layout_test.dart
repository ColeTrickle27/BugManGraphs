import 'dart:convert';

import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:bugman_graphs/services/trace_imagery_service.dart';

import 'mobile_canvas_panels_test.dart' as fixture;
import 'support/crowded_canvas_fixture.dart';

final viewer = find.byType(InteractiveViewer);
final overview = find.byKey(const ValueKey('mobile-trace-summary'));

Future<void> openEditor(WidgetTester tester, GraphDocument doc,
    {double width = 1400, double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildBugManTheme(),
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: GraphCanvasScreen(document: doc, fitToContentOnOpen: true),
  ));
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.pumpAndSettle();
}

Offset screen(WidgetTester tester, Offset scene) =>
    tester.getTopLeft(viewer) +
    MatrixUtils.transformPoint(fixture.viewportController(tester).value, scene);

Future<void> centerOn(WidgetTester tester, Offset scene) async {
  final center = tester.getSize(viewer).center(Offset.zero);
  fixture.viewportController(tester).value =
      Matrix4.translationValues(center.dx - scene.dx, center.dy - scene.dy, 0);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  for (final scene in ['no trace', 'trace', 'trace with attribution']) {
    testWidgets('marker follows the pointer with $scene', (tester) async {
      final doc = crowdedCanvasFixture();
      if (scene == 'no trace') doc.replaceTraces([]);
      if (scene == 'trace with attribution') {
        final trace = doc.traces.single;
        final imagery = TraceImagery(
          base64Jpeg:
              base64Encode(img.encodeJpg(img.Image(width: 2, height: 2))),
          corners: trace.canvasPoints.take(3).toList(),
          capturedAt: '2026-11-20T00:00:00Z',
        );
        await tester.runAsync(() => TraceImageryCache.instance.load(imagery));
        doc.replaceTraces([trace.copyWith(imagery: imagery)]);
      }
      final tracesBefore = doc.traces.map((t) => t.toJson()).toList();
      final marker = doc.annotations.last;
      final point = marker.point.offset;
      await openEditor(tester, doc);
      await centerOn(tester, point);
      final start = screen(tester, point);
      final initial = tester.getRect(viewer);
      final gesture =
          await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(tester.getRect(viewer), initial);
      expect(screen(tester, point), start);

      const movement = Offset(40, 0);
      await gesture.moveTo(start + movement);
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      final reopened = GraphDocument.fromJson(doc.toJson());
      expect(
          reopened.annotations
              .singleWhere((a) => a.id == marker.id)
              .point
              .offset,
          point + movement);
      expect(reopened.traces.map((t) => t.toJson()).toList(), tracesBefore);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(doc.annotations.singleWhere((a) => a.id == marker.id).point.offset,
          point);
    });
  }

  testWidgets('desktop trace and property-line summaries are both readable',
      (tester) async {
    final doc = crowdedCanvasFixture();
    doc.replaceShapes(
        [doc.shapes.first.copyWith(preset: GraphDrawingPreset.propertyLine)]);
    await openEditor(tester, doc);
    final summary = tester.getRect(overview);
    final property = tester.getRect(
        find.byKey(const ValueKey('property-line-measurement-summary')));
    expect(summary.overlaps(property), isFalse);
  });

  testWidgets('overlapping traces can be individually chosen on desktop',
      (tester) async {
    final doc = fixture.yardDocument();
    final first = doc.traces.single;
    doc.replaceTraces(
        [first, first.copyWith(id: 'yard-copy', label: 'Second yard')]);
    await openEditor(tester, doc);
    final edge =
        (first.canvasPoints[0].offset + first.canvasPoints[1].offset) / 2;
    await centerOn(tester, edge);
    await tester.tapAt(screen(tester, edge));
    await tester.pumpAndSettle();
    final direct = find.widgetWithText(TextButton, 'Choose overlap');
    expect(direct, findsNothing);
    await tester.tap(find.byTooltip('Canvas options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose overlap'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Second yard'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Yard'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Yard'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: overview, matching: find.text('Yard')),
        findsOneWidget);
  });

  for (final width in [1400.0, 900.0, 600.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets(
          'all overview acreage fits with both panels at $width x $scale',
          (tester) async {
        await openEditor(tester, fixture.yardDocument(),
            width: width, scale: scale);
        await fixture.openProperties(tester);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Hide main toolbar'), findsOneWidget);
        expect(find.byKey(const ValueKey('canvas-inspector-panel')),
            findsOneWidget);
        final overviewRect = tester.getRect(overview);
        expect(overviewRect.overlaps(tester.getRect(viewer)), isFalse);
        expect(
            overviewRect.overlaps(tester
                .getRect(find.byKey(const ValueKey('canvas-inspector-panel')))),
            isFalse);
        if (width == 600) expect(overviewRect.width, width - 24);
        for (final prefix in ['Net yard:', 'Total:']) {
          final text = find.descendant(
              of: overview, matching: find.textContaining(prefix));
          final render = tester.renderObject<RenderParagraph>(text);
          final painter = TextPainter(
              text: render.text,
              textDirection: render.textDirection,
              textScaler: render.textScaler,
              maxLines: render.maxLines,
              ellipsis: render.overflow == TextOverflow.ellipsis ? '…' : null)
            ..layout(maxWidth: render.size.width);
          expect(painter.didExceedMaxLines, isFalse,
              reason: render.text.toPlainText());
          expect(painter.height, lessThanOrEqualTo(render.size.height + .01));
          painter.dispose();
        }
      });
    }
  }
}
