import 'dart:typed_data';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:bugman_graphs/services/bugman_portal_service_stub.dart';
import 'package:bugman_graphs/services/graph_repository_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GraphDocument source() => GraphDocument(
        id: 'synthetic-source',
        customer: const GraphCustomerInfo(
            name: 'Synthetic copy source',
            serviceAddress: '127 Synthetic Lane',
            pestPacBillToNumber: '990901',
            pestPacLocationNumber: '990903',
            serviceType: 'Inspection',
            createdBy: 'Synthetic'),
        wallSegments: const [
          WallSegment(
              start: GraphPoint(x: 20, y: 20), end: GraphPoint(x: 260, y: 20)),
          WallSegment(
              start: GraphPoint(x: 260, y: 20),
              end: GraphPoint(x: 260, y: 212)),
          WallSegment(
              start: GraphPoint(x: 260, y: 212),
              end: GraphPoint(x: 20, y: 212)),
          WallSegment(
              start: GraphPoint(x: 20, y: 212), end: GraphPoint(x: 20, y: 20))
        ],
        shapes: const [
          GraphShape(
              name: 'Synthetic structure',
              segmentIndexes: [0, 1, 2, 3],
              fillColor: Colors.green,
              fillOpacity: .3,
              borderColor: Colors.green,
              borderWidth: 3,
              pattern: GraphShapePattern.none,
              closed: true,
              rotationDegrees: 0,
              preset: GraphDrawingPreset.mainStructure)
        ]);

class _Portal extends UnavailableBugManPortalService {
  @override
  bool get isAvailable => true;
  @override
  Future<PortalUploadResult> saveGraph(
          GraphDocument document, Map<String, Uint8List> blobs,
          {String? existingKey}) async =>
      const PortalUploadResult(
          key: 'local-synthetic/new.bgraph', message: 'Synthetic saved');
  @override
  String? buildCustomerFolderUrl(
          {required String billToNumber, required String locationNumber}) =>
      'https://ops.example.test/folder?billTo=$billToNumber&location=$locationNumber';
}

Future<void> action(WidgetTester t, String label) async {
  await t.tap(find.byTooltip('Save and share'));
  await t.pumpAndSettle();
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(1440, 1100),
    const Size(390, 844),
    const Size(844, 390)
  ]) {
    testWidgets(
        'copy cancellation and first save/reopen preserve source at $size',
        (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      addTearDown(t.view.reset);
      final original = source();
      final before = original.toJson();
      final repo = MemoryGraphRepository();
      await repo.saveGraph(original);
      await t.pumpWidget(MaterialApp(
          home: GraphCanvasScreen(document: original, repository: repo)));
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await action(t, 'Copy Structure to New Graph');
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(original.toJson(), before);
        expect((await repo.loadGraph(original.id))!.toJson(), before);
      }
      await action(t, 'Copy Structure to New Graph');
      await t.tap(find.text('Start New Graph'));
      await t.pumpAndSettle();
      final copy =
          t.widget<GraphCanvasScreen>(find.byType(GraphCanvasScreen)).document!;
      expect(copy.id, isNot(original.id));
      expect(copy.isDirty, isTrue);
      expect(copy.toJson()['graphObjects'], before['graphObjects']);
      final copied = copy.toJson();
      await action(t, 'Save Graph to BugMan Graphs');
      final reopened = await repo.loadGraph(copy.id);
      expect(reopened, isNotNull);
      expect(reopened!.toJson(), copied);
      expect(reopened.isDirty, isFalse);
      expect((await repo.loadGraph(original.id))!.toJson(), before);
      expect(original.toJson(), before);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('reserved save notice preserves the Open folder action',
      (t) async {
    final doc = source()..replaceMetadata({'syntheticEdit': true});
    final opened = <String>[];
    await t.pumpWidget(MaterialApp(
        home: GraphCanvasScreen(
            document: doc,
            repository: MemoryGraphRepository(),
            portalService: _Portal(),
            onPortalSignIn: opened.add)));
    await t.pumpAndSettle();
    await action(t, 'Save Graph to BugMan Graphs');
    expect(find.byType(MaterialBanner), findsOneWidget);
    await t.tap(find.text('Open folder'));
    await t.pumpAndSettle();
    expect(opened,
        ['https://ops.example.test/folder?billTo=990901&location=990903']);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(t.takeException(), isNull);
  });
}
