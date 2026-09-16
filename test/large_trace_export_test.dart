import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/export_bounds_calculator.dart';
import 'package:bugman_graphs/services/graph_image_export.dart';
import 'package:bugman_graphs/services/graph_pdf_export.dart';
import 'package:bugman_graphs/services/measurement_service.dart';
import 'package:bugman_graphs/services/trace_presentation.dart';
import 'package:bugman_graphs/services/trace_projection_service.dart';
import 'package:bugman_graphs/widgets/graph_scene_boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  for (final presentation in [false, true]) {
    for (final irregular in [false, true]) {
      testWidgets(
          'large trace exports all corners without changing measurements (presentation: $presentation, irregular: $irregular)',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1440, 1000);
        addTearDown(tester.view.reset);
        final font = Platform.environment['GRAPH_QA_FONT'];
        if (font != null) {
          await tester.runAsync(() async {
            final loader = FontLoader('Roboto')
              ..addFont(Future.value(
                  ByteData.sublistView(await File(font).readAsBytes())));
            await loader.load();
          });
        }
        // A 200 by 400 foot property, generated from known geographic offsets.
        const origin = GeoPoint(latitude: 35, longitude: -78);
        final offsets = irregular
            ? const [
                Offset.zero,
                Offset(4800, 0),
                Offset(4800, 7200),
                Offset(4000, 7200),
                Offset(4000, 8400),
                Offset(3200, 8400),
                Offset(3200, 9600),
                Offset(0, 9600)
              ]
            : const [
                Offset.zero,
                Offset(4800, 0),
                Offset(4800, 9600),
                Offset(0, 9600)
              ];
        final geo = [
          for (final p in offsets)
            TraceProjectionService.moveGeoPointByCanvasDelta(
                point: origin, canvasDelta: p, metersPerCanvasUnit: 0.3048 / 24)
        ];
        final projection = TraceProjectionService.projectToCanvas(geo,
            canvasSize: const Size(3600, 2600));
        final trace = TraceGeometry(
            id: 'large',
            label: 'Large Property',
            geoPoints: geo,
            canvasPoints: projection.canvasPoints,
            metersPerCanvasUnit: projection.metersPerCanvasUnit);
        final job = Job(
            customerName: 'Large Property QA',
            serviceAddress: '',
            pestPacLocationNumber: '',
            pestPacBillToNumber: '',
            serviceType: 'Inspection',
            createdBy: 'QA',
            createdDate: DateTime(2026, 9, 16));
        final document = GraphDocument(
            id: job.id,
            customer: GraphCustomerInfo.fromJob(job),
            traces: [trace],
            layers: const {'trace': GraphLayerState(visible: true)})
          ..markClean();
        final measurement = MeasurementService.measureTrace(trace,
            status: MeasurementAccuracyStatus.estimated);
        expect(measurement.linearFeet, closeTo(1200, 0.1));
        expect(measurement.squareFeet, closeTo(irregular ? 75000 : 80000, 2));
        final before = jsonEncode(document.toJson());
        await tester.pumpWidget(MaterialApp(
            home: GraphCanvasScreen(
                document: document, presentationMode: presentation)));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<GraphSceneRenderBoundary>(
            find.byType(GraphSceneBoundary));
        final bounds = ExportBoundsCalculator.forDocument(document,
            canvasSize: const Size(3600, 2600));
        expect(bounds.left, lessThan(0));
        expect(bounds.top, lessThan(0));
        expect(bounds.bottom, greaterThan(2600));
        expect(boundary.paintBounds.contains(bounds.topLeft), isTrue);
        final png = await tester
            .runAsync(() => GraphImageExport.capturePng(boundary, bounds));
        final decoded = img.decodePng(png!)!;
        expect(
            math.max(decoded.width, decoded.height), lessThanOrEqualTo(2400));
        // Every original corner must be visible blue/red paint in the exported
        // image, including corners entirely outside the former canvas rectangle.
        final scale = decoded.width / bounds.width;
        for (final p in trace.canvasPoints) {
          final x = ((p.x - bounds.left) * scale).round();
          final y = ((p.y - bounds.top) * scale).round();
          final pixel = decoded.getPixel(x, y);
          expect(pixel.r - pixel.g, greaterThan(80));
        }
        final labelWorldSize = 17 * TracePresentation.labelScale([trace]);
        // Conservative 440pt graph height on landscape Letter: >=10pt labels.
        expect(
            labelWorldSize * math.min(744 / bounds.width, 440 / bounds.height),
            greaterThanOrEqualTo(10));
        final pdf = await tester.runAsync(() => GraphPdfExport.build(
            graphPng: png, title: 'Large property - 200 by 400 feet'));
        expect(ascii.decode(pdf!.take(4).toList()), '%PDF');
        expect(jsonEncode(document.toJson()), before);
        expect(document.isDirty, isFalse);

        if (!presentation) {
          final finder = find.byType(InteractiveViewer);
          final controller = tester
              .widget<InteractiveViewer>(finder)
              .transformationController!;
          final corner = tester.getTopLeft(finder) +
              MatrixUtils.transformPoint(
                  controller.value, trace.canvasPoints.first.offset);
          await tester.dragFrom(corner, const Offset(15, 10));
          await tester.pump();
          expect(document.traces.first.canvasPoints.first.x,
              greaterThan(trace.canvasPoints.first.x));
          // Undo the deliberate geometry edit before comparing against the source.
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          expect(document.traces.first.toJson(), trace.toJson());
        }
        final output = Platform.environment['GRAPH_QA_OUTPUT'];
        if (output != null) {
          await tester.runAsync(() async {
            await File('$output/large-trace-$presentation-$irregular.png')
                .writeAsBytes(png);
            await File('$output/large-trace-$presentation-$irregular.pdf')
                .writeAsBytes(pdf);
          });
        }
      });
    }
  }
}
