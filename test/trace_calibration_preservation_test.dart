import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/screens/trace_workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const customer = GraphCustomerInfo(
  name: 'Synthetic calibration',
  serviceAddress: '',
  pestPacLocationNumber: 'synthetic-location',
  pestPacBillToNumber: 'synthetic-bill-to',
  serviceType: 'Inspection',
  createdBy: 'Synthetic only',
);

const trace = TraceGeometry(
  id: 'synthetic-yard',
  label: 'Saved yard',
  geoPoints: [
    GeoPoint(latitude: 35, longitude: -78),
    GeoPoint(latitude: 35, longitude: -77.999),
    GeoPoint(latitude: 34.999, longitude: -77.999),
  ],
  canvasPoints: [
    GraphPoint(x: 0, y: 0),
    GraphPoint(x: 120, y: 0),
    GraphPoint(x: 120, y: 120),
  ],
  metersPerCanvasUnit: .0127,
);

final verified = MeasurementCalibration(
  source: MeasurementSource.calibratedImage,
  status: MeasurementAccuracyStatus.verified,
  metersPerCanvasUnit: .0254,
  residualErrorMeters: .03,
  verifiedAt: DateTime.utc(2026, 10, 22),
  note: 'Retain the original field verification',
);

Future<void> returnFromTracer(
  WidgetTester tester,
  GraphDocument document,
  TraceGeometry returned,
) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: GraphCanvasScreen(document: document)),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Satellite'));
  await tester.tap(find.text('Satellite'));
  await tester.pumpAndSettle();
  if (document.traces.isNotEmpty) {
    await tester.tap(find.text('Saved yard'));
    await tester.pumpAndSettle();
  }
  expect(find.byType(TraceWorkspaceScreen), findsOneWidget);
  Navigator.of(tester.element(find.byType(TraceWorkspaceScreen)))
      .pop<TraceGeometry>(returned);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'editing a trace keeps verified wall calibration and undo state',
    (tester) async {
      final document = GraphDocument(
        customer: customer,
        measurementCalibration: verified,
        wallSegments: [
          const WallSegment(
            start: GraphPoint(x: 0, y: 0),
            end: GraphPoint(x: 240, y: 0),
          ),
        ],
        traces: const [trace],
        metadata: const {'futureField': 'preserved'},
      );
      final before = document.toJson();
      final updated = trace.copyWith(label: 'Edited yard');
      await returnFromTracer(tester, document, updated);
      expect(document.traces.single.label, 'Edited yard');
      expect(document.measurementCalibration.toJson(), verified.toJson());
      expect(document.toJson()['graphObjects'], before['graphObjects']);
      final reopened = GraphDocument.fromJson(document.toJson());
      expect(reopened.measurementCalibration.toJson(), verified.toJson());
      expect(reopened.customer.toJson(), customer.toJson());
      expect(reopened.metadata, document.metadata);
      await tester.tap(find.byTooltip('Undo').first);
      await tester.pumpAndSettle();
      expect(document.traces.single.label, 'Saved yard');
      expect(document.measurementCalibration.toJson(), verified.toJson());
    },
  );

  testWidgets('new tracing preserves existing legacy wall measurements', (
    tester,
  ) async {
    final document = GraphDocument(
      customer: customer,
      wallSegments: [
        const WallSegment(
          start: GraphPoint(x: 0, y: 0),
          end: GraphPoint(x: 240, y: 0),
        ),
      ],
    );
    final calibration = document.measurementCalibration.toJson();
    await returnFromTracer(
      tester,
      document,
      trace.copyWith(metersPerCanvasUnit: .04),
    );
    expect(document.measurementCalibration.toJson(), calibration);
    expect(document.wallSegments.single.end.x, 240);
  });

  testWidgets(
    'first trace initializes the scale only in an empty legacy graph',
    (tester) async {
      final document = GraphDocument(customer: customer);
      await returnFromTracer(
        tester,
        document,
        trace.copyWith(metersPerCanvasUnit: .04),
      );
      expect(
        document.measurementCalibration.source,
        MeasurementSource.mapGeodesic,
      );
      expect(document.measurementCalibration.metersPerCanvasUnit, .04);
      expect(
        document.measurementCalibration.status,
        MeasurementAccuracyStatus.estimated,
      );
    },
  );

  for (final calibration in [
    verified,
    const MeasurementCalibration(
      source: MeasurementSource.legacyCanvasScale,
      status: MeasurementAccuracyStatus.verified,
      metersPerCanvasUnit: .0127,
      note: 'Existing legacy verification',
    ),
    const MeasurementCalibration(
      source: MeasurementSource.legacyCanvasScale,
      status: MeasurementAccuracyStatus.estimated,
      metersPerCanvasUnit: .05,
      note: 'Explicit nondefault legacy scale',
    ),
  ]) {
    testWidgets('empty graph retains calibration ${calibration.note}',
        (tester) async {
      final document = GraphDocument(
        customer: customer,
        measurementCalibration: calibration,
      );
      await returnFromTracer(tester, document, trace);
      expect(document.measurementCalibration.toJson(), calibration.toJson());
    });
  }
}
