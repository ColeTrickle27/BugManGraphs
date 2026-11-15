import 'package:bugman_graphs/main.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:bugman_graphs/services/bugman_portal_service_stub.dart';
import 'package:bugman_graphs/services/graph_repository_stub.dart';
import 'package:bugman_graphs/services/export_bounds_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Portal extends UnavailableBugManPortalService {
  Portal(this.document);
  final GraphDocument document;
  String? requested;
  @override
  bool get isAvailable => true;
  @override
  Future<PortalGraphPackage> loadGraph(String key) async {
    requested = key;
    return PortalGraphPackage(
        document: document, blobs: const {}, name: 'Synthetic offset graph');
  }
}

void main() {
  testWidgets('hidden reference trace does not shrink visible uploaded walls',
      (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1440, 1000);
    addTearDown(t.view.reset);
    final doc = GraphDocument.forJob(Job(
        customerName: 'Synthetic hidden trace',
        serviceAddress: '',
        pestPacLocationNumber: '',
        pestPacBillToNumber: '',
        serviceType: 'Inspection',
        createdBy: '',
        createdDate: DateTime(2026)))
      ..replaceWallSegments(const [
        WallSegment(
            start: GraphPoint(x: 40, y: 40), end: GraphPoint(x: 320, y: 240))
      ])
      ..replaceTraces(const [
        TraceGeometry(
            id: 'hidden-reference',
            label: 'Hidden reference',
            geoPoints: [],
            canvasPoints: [
              GraphPoint(x: 100000, y: 100000),
              GraphPoint(x: 200000, y: 200000)
            ])
      ])
      ..markClean();
    final before = doc.toJson();
    await t.pumpWidget(BugManGraphsApp(
        accountDraftsEnabled: false,
        repository: MemoryGraphRepository(),
        portalService: Portal(doc),
        initialUri: Uri.parse('https://graphs.example/?graph=SYNTHETIC-KEY')));
    await t.pumpAndSettle();
    final f = find.byType(InteractiveViewer);
    final matrix =
        t.widget<InteractiveViewer>(f).transformationController!.value;
    final visible = MatrixUtils.transformRect(
        matrix, const Rect.fromLTRB(40, 40, 320, 240));
    expect(visible.width, greaterThan(200));
    expect((Offset.zero & t.getSize(f)).contains(visible.center), true);
    expect(doc.toJson(), before);
  });

  for (final noteOnly in [false, true]) {
    testWidgets('uploaded graph opens at its content, note-only=$noteOnly',
        (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1440, 1000);
      addTearDown(t.view.reset);
      final doc = GraphDocument.forJob(Job(
          customerName: 'Synthetic linked graph',
          serviceAddress: '',
          pestPacLocationNumber: '',
          pestPacBillToNumber: '',
          serviceType: 'Inspection',
          createdBy: '',
          createdDate: DateTime(2026)));
      if (noteOnly) {
        doc.replaceAnnotations(const [
          GraphAnnotation(
              kind: GraphAnnotationKind.text,
              point: GraphPoint(x: 80, y: 60),
              label: 'NOTE ONLY')
        ]);
      } else {
        doc.replaceWallSegments(const [
          WallSegment(
              start: GraphPoint(x: 40, y: 40), end: GraphPoint(x: 320, y: 240))
        ]);
      }
      doc.markClean();
      final before = doc.toJson();
      final portal = Portal(doc);
      await t.pumpWidget(BugManGraphsApp(
          accountDraftsEnabled: false,
          repository: MemoryGraphRepository(),
          portalService: portal,
          initialUri:
              Uri.parse('https://graphs.example/?graph=SYNTHETIC-KEY')));
      await t.pumpAndSettle();
      expect(portal.requested, 'SYNTHETIC-KEY');
      final f = find.byType(InteractiveViewer);
      final viewer = t.widget<InteractiveViewer>(f);
      final screen = MatrixUtils.transformRect(
          viewer.transformationController!.value,
          ExportBoundsCalculator.forDocument(doc, padding: 0));
      final viewport = Offset.zero & t.getSize(f);
      expect(screen.left, greaterThanOrEqualTo(208));
      expect(viewport.contains(screen.center), true);
      expect(doc.toJson(), before);
      expect(t.takeException(), isNull);
    });
  }
}
