import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/services/measurement_service.dart';
import 'package:bugman_graphs/services/measurement_format.dart';
import 'package:bugman_graphs/theme/app_theme.dart';
import 'mobile_canvas_panels_test.dart' as fixture;

void main() {
  for (final scale in [1.3, 1.6, 2.0]) {
    for (final size in [const Size(390, 844), const Size(1400, 900)]) {
      testWidgets(
          'scrolled properties expose full values with text scale $scale at $size',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        try {
          final document = fixture.yardDocument();
          final before = jsonEncode(document.toJson());
          await tester.pumpWidget(MaterialApp(
              theme: buildBugManTheme(),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: GraphCanvasScreen(
                  document: document, fitToContentOnOpen: true)));
          await tester.pumpAndSettle();
          final viewer = find.byType(InteractiveViewer);
          final controller = fixture.viewportController(tester);
          final trace = document.traces.single;
          final midpoint =
              (trace.canvasPoints[0].offset + trace.canvasPoints[1].offset) / 2;
          await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
          await tester.tapAt(tester.getTopLeft(viewer) +
              MatrixUtils.transformPoint(controller.value, midpoint));
          await tester.pumpAndSettle();
          await fixture.openProperties(tester);
          await tester.pumpAndSettle();
          if (size.width < 600) {
            await tester.ensureVisible(find.text('Measurements'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Measurements'));
            await tester.pumpAndSettle();
          }
          final measurement = MeasurementService.measureTrace(trace,
              status: MeasurementAccuracyStatus.estimated);
          final value =
              '${MeasurementFormat.acres(measurement.acres)} (${MeasurementFormat.squareFeet(measurement.squareFeet)})';
          final valueFinder = find.text(value);
          await tester.ensureVisible(valueFinder);
          await tester.pumpAndSettle();
          expect(tester.getSemantics(valueFinder).label, contains(value));
          expect(tester.getSemantics(find.text('Total area')).label,
              contains('Total area'));
          expect(
              Rect.fromLTWH(0, 0, size.width, size.height)
                  .contains(tester.getCenter(valueFinder)),
              isTrue);
          expect(jsonEncode(document.toJson()), before);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
