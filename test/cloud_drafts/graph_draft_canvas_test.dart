import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/screens/new_job_screen.dart';
import 'package:bugman_graphs/widgets/cloud_drafts/graph_creator_picker.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_workspace.dart';
import 'graph_draft_sync_test.dart'
    show FixtureDraftService, workspace, ownerA, doc;

void main() {
  testWidgets(
      'canvas edits queue a frozen scoped recovery without changing geometry on sync',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store),
        document = doc();
    final session = await w.create(document);
    await tester.pumpWidget(MaterialApp(
        home:
            GraphCanvasScreen(document: document, cloudDraftSession: session)));
    await tester.pumpAndSettle();
    final segments = document.wallSegments.toList();
    segments[0] = segments[0].copyWith(start: const GraphPoint(x: 750, y: 800));
    document.replaceWallSegments(segments);
    await tester.pumpAndSettle();
    await session.flushLocal();
    final before = document.toJson();
    await session.retry();
    await tester.pumpAndSettle();
    expect((await store.read(ownerA, document.id))!.document, before);
    expect(document.toJson(), before);
    expect(session.phase, GraphDraftPhase.synced);
    expect(find.byTooltip('Synced to your account'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await session.flushLocal();
    w.dispose();
  });
  testWidgets(
      'cloud metadata cancel retains attribution and address; explicit selection changes only creator',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store);
    await w.refreshAuthors();
    final document = doc();
    final session = await w.create(document);
    await session.retry();
    final before = document.toJson();
    await tester.pumpWidget(MaterialApp(
        home:
            GraphCanvasScreen(document: document, cloudDraftSession: session)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit Graph Information'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(GraphCreatorPicker), 300,
        scrollable: find
            .descendant(
                of: find.byType(NewJobScreen),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic creator'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel edits'));
    await tester.pumpAndSettle();
    expect(document.toJson(), before);
    expect(session.recovery.pendingAuthor, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await session.flushLocal();
    w.dispose();
  });
}
