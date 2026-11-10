import 'dart:async';
import 'dart:typed_data';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/graph_repository_stub.dart';
import 'package:bugman_graphs/services/bugman_portal_service_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/crowded_canvas_fixture.dart';

class _Repository extends MemoryGraphRepository {
  int saves = 0;
  bool fail = false;
  bool editAfterPersist = false;
  Completer<void>? pending;
  @override
  Future<void> saveGraph(GraphDocument document,
      {Map<String, Uint8List> blobs = const {},
      Set<String> deletedBlobKeys = const {}}) async {
    saves++;
    if (fail) throw StateError('Synthetic storage failure');
    if (pending != null) await pending!.future;
    await super
        .saveGraph(document, blobs: blobs, deletedBlobKeys: deletedBlobKeys);
    if (editAfterPersist) {
      document.replaceAnnotations([
        ...document.annotations,
        const GraphAnnotation(
            kind: GraphAnnotationKind.text,
            point: GraphPoint(x: 80, y: 80),
            label: 'Edit after persistence')
      ]);
    }
  }
}

void main() {
  for (final outcome in [
    'success',
    'failure',
    'pending',
    'overwrite cancel',
    'concurrent after persist'
  ]) {
    testWidgets('real editor save and leave $outcome', (t) async {
      final doc = crowdedCanvasFixture();
      doc.replaceAnnotations([
        ...doc.annotations,
        const GraphAnnotation(
            kind: GraphAnnotationKind.text,
            point: GraphPoint(x: 400, y: 300),
            label: 'New note awaiting first save')
      ]);
      final before = doc.toJson();
      final repo = _Repository()
        ..fail = outcome == 'failure'
        ..editAfterPersist = outcome == 'concurrent after persist';
      if (outcome == 'pending') repo.pending = Completer<void>();
      await t.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => GraphCanvasScreen(
                                  document: doc,
                                  repository: repo,
                                  portalService:
                                      UnavailableBugManPortalService(),
                                  portalKey: outcome == 'overwrite cancel'
                                      ? 'synthetic/existing'
                                      : null))),
                      child: const Text('Open'))))));
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('Save and continue'));
      await t.pumpAndSettle();
      if (outcome == 'overwrite cancel') {
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(repo.saves, 0);
      } else if (outcome == 'pending') {
        await t.binding.handlePopRoute();
        await t.pump();
        expect(repo.saves, 1);
        expect(find.byType(GraphCanvasScreen), findsOneWidget);
        repo.pending!.complete();
        await t.pumpAndSettle();
      }
      if (outcome == 'success' || outcome == 'pending') {
        expect(find.byType(GraphCanvasScreen), findsNothing);
      } else {
        expect(find.byType(GraphCanvasScreen), findsOneWidget);
        expect(doc.isDirty, true);
        if (outcome == 'concurrent after persist') {
          expect(doc.annotations.last.label, 'Edit after persistence');
          expect(
              (await repo.loadGraph(doc.id))!
                  .annotations
                  .any((a) => a.label == 'Edit after persistence'),
              false);
        } else {
          expect(doc.toJson(), before);
        }
      }
    });
  }
}
