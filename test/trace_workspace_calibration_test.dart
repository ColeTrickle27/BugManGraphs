import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/screens/trace_workspace_screen.dart';
import 'package:bugman_graphs/services/measurement_service.dart';
import 'package:bugman_graphs/services/trace_map_provider.dart';
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
    required ValueChanged<GeoPoint> onMapTap,
    required void Function(int, GeoPoint) onVertexMoved,
  }) {
    move = onVertexMoved;
    return const SizedBox.expand();
  }
}

Future<TraceGeometry> saveTrace(WidgetTester tester, TraceGeometry initial,
    {bool editGeometry = false}) async {
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
          )));
  await tester.pumpAndSettle();
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
