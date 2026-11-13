import 'dart:convert';

import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/screens/trace_workspace_screen.dart';
import 'package:bugman_graphs/services/measurement_service.dart';
import 'package:bugman_graphs/services/trace_map_provider.dart';
import 'package:bugman_graphs/services/trace_imagery_service.dart';
import 'package:bugman_graphs/services/trace_projection_service.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const points = [
  GeoPoint(latitude: 35, longitude: -78),
  GeoPoint(latitude: 35, longitude: -77.999),
  GeoPoint(latitude: 34.999, longitude: -77.999),
];

class TestMap extends TraceMapProvider {
  void Function(int, GeoPoint)? move;
  @override
  Future<void> initialize() async {}
  @override
  Widget buildMap({
    required GeoPoint center,
    required GeoPoint selectedAddress,
    required List<GeoPoint> points,
    List<List<GeoPoint>> referencePolygons = const [],
    required ValueChanged<GeoPoint> onMapTap,
    required void Function(int, GeoPoint) onVertexMoved,
  }) {
    move = onVertexMoved;
    return const SizedBox.expand();
  }
}

Future<TraceGeometry> saveTrace(WidgetTester tester, TraceGeometry initial,
    {bool editGeometry = false,
    TraceImageryService? imageryService,
    bool includeImagery = false}) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final navigator = GlobalKey<NavigatorState>();
  final provider = TestMap();
  await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('Previous page'))));
  final result = navigator.currentState!.push<TraceGeometry>(MaterialPageRoute(
      builder: (_) => TraceWorkspaceScreen(
            address: '',
            canvasSize: const Size(3600, 2600),
            traceLabel: 'Synthetic yard',
            initialTrace: initial,
            provider: provider,
            metersPerCanvasUnit: .0254,
            imageryService: imageryService ?? const TraceImageryService(),
          )));
  await tester.pumpAndSettle();
  if (includeImagery && initial.imagery == null) {
    if (find.byKey(const ValueKey('trace-options')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('trace-options')));
      await tester.pumpAndSettle();
    }
    await tester
        .ensureVisible(find.byKey(const ValueKey('include-trace-imagery')));
    await tester.tap(find.byKey(const ValueKey('include-trace-imagery')));
    await tester.pumpAndSettle();
  }
  if (editGeometry) {
    provider.move!(0, const GeoPoint(latitude: 35.0001, longitude: -78));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('finish-trace-button')));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return (await result)!;
}

void main() {
  for (final preserved in [false, true]) {
    testWidgets(
        'imagery and deductions share the saved frame: preserved=$preserved',
        (tester) async {
      final service = FrameImageryService();
      await tester.runAsync(() => TraceImageryCache.instance.load(TraceImagery(
          base64Jpeg: service.jpeg, capturedAt: 'cache', corners: const [])));
      final original = frameTrace(preserved: preserved);
      final saved = await saveTrace(tester, original,
          imageryService: service, includeImagery: true);
      final scale = preserved ? .0127 : .0254;
      expect(saved.metersPerCanvasUnit, scale);
      if (preserved) {
        expect(saved.canvasPoints.map((p) => [p.x, p.y]),
            original.canvasPoints.map((p) => [p.x, p.y]));
      }
      final expectedImage = TraceProjectionService.projectToCanvas(
              service.geoCorners!,
              canvasSize: const Size(3600, 2600),
              referencePoints: points,
              metersPerCanvasUnit: scale)
          .canvasPoints;
      final expectedDeduction = TraceProjectionService.projectToCanvas(
              original.exclusions.single.geoPoints,
              canvasSize: const Size(3600, 2600),
              referencePoints: points,
              metersPerCanvasUnit: scale)
          .canvasPoints;
      for (var i = 0; i < expectedImage.length; i++) {
        final expected =
            preserved ? turnAndMove(expectedImage[i]) : expectedImage[i];
        expect(
            saved.imagery!.corners[i].distanceTo(expected), lessThan(.00001));
      }
      for (var i = 0; i < expectedDeduction.length; i++) {
        final expected = preserved
            ? turnAndMove(expectedDeduction[i])
            : expectedDeduction[i];
        expect(saved.exclusions.single.canvasPoints[i].distanceTo(expected),
            lessThan(.00001));
      }
      expect(saved.exclusions.single.label, 'Home');
      expect(service.calls, 1);
    });
  }

  testWidgets('unchanged imagery retains exact corners without recapture',
      (tester) async {
    final service = FrameImageryService();
    final image = TraceImagery(
        base64Jpeg: service.jpeg,
        capturedAt: 'Existing',
        corners: const [
          GraphPoint(x: 10, y: 30),
          GraphPoint(x: 50, y: 20),
          GraphPoint(x: 20, y: 70)
        ]);
    final original = frameTrace(preserved: true).copyWith(imagery: image);
    final saved = await saveTrace(tester, original, imageryService: service);
    expect(saved.imagery!.toJson(), image.toJson());
    expect(saved.canvasPoints.map((p) => [p.x, p.y]),
        original.canvasPoints.map((p) => [p.x, p.y]));
    expect(service.calls, 0);
  });

  testWidgets('real Save Trace projects at the retained graph scale',
      (tester) async {
    final saved = await saveTrace(
        tester,
        const TraceGeometry(
            id: 'new',
            label: 'Synthetic yard',
            geoPoints: points,
            canvasPoints: []));
    expect(saved.metersPerCanvasUnit, .0254);
    final physicalDistance =
        saved.canvasPoints[0].distanceTo(saved.canvasPoints[1]) * .0254;
    expect(
        physicalDistance,
        closeTo(MeasurementService.geodesicDistanceMeters(points[0], points[1]),
            .01));
  });

  testWidgets('a non-geometric save preserves the exact stored canvas frame',
      (tester) async {
    const original = TraceGeometry(
        id: 'existing',
        label: 'Synthetic yard',
        geoPoints: points,
        canvasPoints: [
          GraphPoint(x: 100, y: 200),
          GraphPoint(x: 300, y: 200),
          GraphPoint(x: 300, y: 500)
        ],
        metersPerCanvasUnit: .0127);
    final saved = await saveTrace(tester, original);
    expect(saved.canvasPoints.map((p) => [p.x, p.y]),
        original.canvasPoints.map((p) => [p.x, p.y]));
    expect(saved.metersPerCanvasUnit, original.metersPerCanvasUnit);
  });

  testWidgets('an actual vertex edit projects changed geometry at graph scale',
      (tester) async {
    const original = TraceGeometry(
        id: 'existing',
        label: 'Synthetic yard',
        geoPoints: points,
        canvasPoints: [
          GraphPoint(x: 100, y: 200),
          GraphPoint(x: 300, y: 200),
          GraphPoint(x: 300, y: 500)
        ],
        metersPerCanvasUnit: .0127);
    final saved = await saveTrace(tester, original, editGeometry: true);
    expect(saved.metersPerCanvasUnit, .0254);
    expect(saved.geoPoints.first.latitude, 35.0001);
    expect(
        saved.canvasPoints[0].distanceTo(saved.canvasPoints[1]) * .0254,
        closeTo(
            MeasurementService.geodesicDistanceMeters(
                saved.geoPoints[0], saved.geoPoints[1]),
            .01));
  });
}

GraphPoint turnAndMove(GraphPoint p) => GraphPoint(x: 400 - p.y, y: 700 + p.x);

TraceGeometry frameTrace({required bool preserved}) {
  final canonical = TraceProjectionService.projectToCanvas(points,
      canvasSize: const Size(3600, 2600), metersPerCanvasUnit: .0127);
  return TraceGeometry(
      id: 'framed-yard',
      label: 'Yard',
      geoPoints: points,
      canvasPoints:
          preserved ? canonical.canvasPoints.map(turnAndMove).toList() : [],
      metersPerCanvasUnit: preserved ? .0127 : null,
      exclusions: const [
        TraceGeometry(id: 'home', label: 'Home', geoPoints: [
          GeoPoint(latitude: 34.9999, longitude: -77.9993),
          GeoPoint(latitude: 34.9999, longitude: -77.9991),
          GeoPoint(latitude: 34.9997, longitude: -77.9991),
          GeoPoint(latitude: 34.9997, longitude: -77.9993)
        ], canvasPoints: [])
      ]);
}

class FrameImageryService extends TraceImageryService {
  final jpeg = base64Encode(img.encodeJpg(img.Image(width: 2, height: 2)));
  List<GeoPoint>? geoCorners;
  var calls = 0;
  @override
  Future<TraceImagery> capture(
      {required List<GeoPoint> corners,
      required List<GraphPoint> canvasCorners,
      TraceImageryCancellation? cancellation,
      ValueChanged<TraceImageryProgress>? onProgress}) async {
    calls++;
    geoCorners = corners;
    return TraceImagery(
        base64Jpeg: jpeg, capturedAt: 'QA', corners: canvasCorners);
  }
}
