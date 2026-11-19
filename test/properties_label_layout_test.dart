import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/editor/label_presentation.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/widgets/trace_geometry_painter.dart';
import 'package:bugman_graphs/services/measurement_service.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/services/measurement_format.dart';
import 'package:bugman_graphs/theme/app_theme.dart';
import 'mobile_canvas_panels_test.dart' as fixture;

void main() {
  test(
      'automatic screen badges are restrained while explicit label scale and export scale remain intact',
      () {
    for (final zoom in [.03, .2, 1.0, 5.0]) {
      final normal = TraceGeometryPainter.displayScaleFor(
          [], LabelPresentation(zoom: zoom, bounded: true));
      final larger = TraceGeometryPainter.displayScaleFor(
          [], LabelPresentation(zoom: zoom, bounded: true, textScale: 1.6));
      expect(normal * zoom, inInclusiveRange(.75, 1.0));
      expect(larger / normal, closeTo(1.6, .000001));
    }
    expect(
        TraceGeometryPainter.displayScaleFor([], const LabelPresentation()), 1);
    expect(TraceGeometryPainter(traces: []).showSummary, isTrue);
  });
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(900, 650),
    const Size(1400, 900)
  ]) {
    testWidgets(
        'trace properties remain readable and overview stays off the drawing at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final doc = fixture.yardDocument(), before = jsonEncode(doc.toJson());
      await tester.pumpWidget(MaterialApp(
          theme: buildBugManTheme(),
          home: GraphCanvasScreen(document: doc, fitToContentOnOpen: true)));
      await tester.pumpAndSettle();
      final view = find.byType(InteractiveViewer),
          controller = fixture.viewportController(tester);
      final trace = doc.traces.single,
          mid =
              (trace.canvasPoints[0].offset + trace.canvasPoints[1].offset) / 2;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.tapAt(tester.getTopLeft(view) +
          MatrixUtils.transformPoint(controller.value, mid));
      await tester.pumpAndSettle();
      await fixture.openProperties(tester);
      await tester.pumpAndSettle();
      if (size.shortestSide < 600 &&
          find.text('Measurements').evaluate().isNotEmpty) {
        await tester.tap(find.text('Measurements'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Total area'), findsOneWidget);
      final result = MeasurementService.measureTrace(trace,
              status: MeasurementAccuracyStatus.estimated),
          value =
              '${MeasurementFormat.acres(result.acres)} (${MeasurementFormat.squareFeet(result.squareFeet)})';
      final valueFinder = find.text(value);
      expect(valueFinder, findsOneWidget);
      final widget = tester.widget<Text>(valueFinder);
      expect(widget.maxLines, isNull);
      expect(widget.overflow, isNot(TextOverflow.ellipsis));
      expect(widget.style!.fontFamily, 'Bitter');
      if (size.shortestSide >= 600) {
        expect(
            tester
                .widget<Text>(find.text('Trace Properties'))
                .style!
                .fontFamily,
            'Bitter');
      }
      final summary = find.byKey(const ValueKey('mobile-trace-summary'));
      expect(summary, findsOneWidget);
      expect(tester.getRect(view).overlaps(tester.getRect(summary)), isFalse);
      expect(jsonEncode(doc.toJson()), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
