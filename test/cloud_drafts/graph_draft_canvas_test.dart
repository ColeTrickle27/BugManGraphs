import 'dart:typed_data';
import 'dart:convert';
import 'package:bugman_graphs/screens/cloud_drafts/graph_draft_remote_preview.dart';
import 'package:bugman_graphs/models/cloud_graph_draft.dart';
import 'graph_draft_recovery_test.dart' show FailingStore;
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_editor_repository.dart';
import 'package:flutter/material.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:bugman_graphs/screens/cloud_drafts/graph_draft_editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/screens/new_job_screen.dart';
import 'package:bugman_graphs/widgets/cloud_drafts/graph_creator_picker.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_workspace.dart';
import 'graph_draft_sync_test.dart'
    show FixtureDraftService, workspace, ownerA, doc, moved;

void main() {
  testWidgets(
      'Save As New close awaits repository transition and failed active recovery',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final api = FixtureDraftService(), store = FailingStore()..fail = false;
    final w = workspace(api, store);
    final original = await w.create(doc());
    await original.retry();
    await original.updatePortalKey('synthetic/existing.bgraph');
    final portal = RecordingDraftPortal();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => GraphDraftEditorScreen(
                            session: original, portalService: portal))),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save and share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Graph to BugMan Graphs'));
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.tap(find.text('Save As New'));
    await tester.pumpAndSettle();
    final active = (tester
            .widget<GraphCanvasScreen>(find.byType(GraphCanvasScreen))
            .repository as GraphDraftEditorRepository)
        .session;
    expect(active.id, isNot(original.id));
    expect(active.hasUnpersistedEdits, isTrue);
    expect(portal.saves, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(GraphDraftEditorScreen), findsOneWidget);
    store.fail = false;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(GraphDraftEditorScreen), findsNothing);
    expect((await store.read(ownerA, active.id))!.document['id'], active.id);
    expect((await store.read(ownerA, original.id))!.portalKey,
        'synthetic/existing.bgraph');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    w.dispose();
  });

  testWidgets(
      'cloud conflict preview includes every object and full photos with explicit Close',
      (tester) async {
    final json = doc().toJson();
    json['attachments'] = [
      const GraphAttachment(
              id: 'photo', name: 'Synthetic evidence', blobKey: 'full')
          .toJson()
    ];
    const encoded =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    final remote = RemoteGraphDraft(
        GraphDraftPackage.fromJson({
          'type': 'bugman-graph',
          'version': 1,
          'document': json,
          'blobs': {'full': encoded}
        }),
        'a' * 32,
        const GraphDraftAuthor('employee-1', 'Synthetic'));
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            GraphDraftRemotePreview(remote: remote))),
                child: const Text('Review')))));
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    final canvas =
        tester.widget<GraphCanvasScreen>(find.byType(GraphCanvasScreen));
    expect(canvas.presentationMode, isTrue);
    expect(canvas.completePackagePreview, isTrue);
    expect(canvas.document!.annotations.length, doc().annotations.length);
    expect(find.text('Synthetic evidence'), findsOneWidget);
    final image =
        tester.widget<Image>(find.byType(Image).last).image as MemoryImage;
    expect(image.bytes, base64Decode(encoded));
    expect(find.byTooltip('Save and share'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(GraphDraftRemotePreview), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets(
      'Keep Both close checks active fork and blocks exit when its recovery fails',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final api = FixtureDraftService()..failCode = 409;
    final store = FailingStore()..fail = false;
    final w = workspace(api, store), document = doc();
    api.remote = RemoteGraphDraft(
        GraphDraftPackage.fromJson({
          'type': 'bugman-graph',
          'version': 1,
          'document': document.toJson(),
          'blobs': <String, String>{}
        }),
        'a' * 32,
        const GraphDraftAuthor('employee-1', 'Synthetic'));
    final session = await w.create(document);
    await session.retry();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            GraphDraftEditorScreen(session: session))),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byTooltip('Saved on this device · cloud copy differs'));
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.tap(find.text('Keep both copies'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(GraphDraftEditorScreen), findsOneWidget);
    expect(
        find.text(
            'Recovery could not be saved. Keep this graph open and save a recovery copy.'),
        findsOneWidget);
    store.fail = false;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(GraphDraftEditorScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    w.dispose();
  });

  testWidgets('clean cloud graph can publish its first manual customer file',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final w = workspace(FixtureDraftService(), MemoryGraphDraftStore());
    final session = await w.create(doc());
    await session.retry();
    final loaded = GraphDocument.fromJson(session.documentJson);
    expect(loaded.isDirty, isFalse);
    final portal = RecordingDraftPortal();
    await tester.pumpWidget(MaterialApp(
        home: GraphCanvasScreen(
            document: loaded,
            cloudDraftSession: session,
            portalService: portal)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save and share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Graph to BugMan Graphs'));
    await tester.pumpAndSettle();
    expect(portal.saves, 1);
    expect(session.portalKey, 'synthetic/customer/graph.bgraph');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await session.flushLocal();
    w.dispose();
  });
  testWidgets(
      'navigation before debounce persists and uploads without reopening',
      (tester) async {
    final w = workspace(FixtureDraftService(), MemoryGraphDraftStore());
    final session = await w.create(doc());
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            GraphDraftEditorScreen(session: session))),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    session.capture(moved(session));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(session.hasQueuedEdits, isFalse);
    expect(session.phase, GraphDraftPhase.synced);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    w.dispose();
  });

  testWidgets('copy structure child does not rebind the parent account editor',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final w = workspace(FixtureDraftService(), MemoryGraphDraftStore());
    final document = doc();
    final session = await w.create(document);
    // Use the session's exact graph identity for the parent canvas.
    final parent = session.documentJson;
    await tester.pumpWidget(MaterialApp(
        home:
            GraphCanvasScreen(document: document, cloudDraftSession: session)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save and share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Structure to New Graph'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start New Graph'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    final segments = document.wallSegments.toList();
    segments[0] = segments[0].copyWith(start: const GraphPoint(x: 750, y: 800));
    document.replaceWallSegments(segments);
    await tester.pumpAndSettle();
    await session.flushLocal();
    expect(session.id, parent['id']);
    expect(session.documentJson, document.toJson());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await session.flushLocal();
    w.dispose();
  });

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

class RecordingDraftPortal implements BugManPortalService {
  int saves = 0;
  @override
  bool get isAvailable => true;
  @override
  Future<PortalUploadResult> saveGraph(
      GraphDocument document, Map<String, Uint8List> blobs,
      {String? existingKey}) async {
    saves++;
    return const PortalUploadResult(
        key: 'synthetic/customer/graph.bgraph', message: 'Graph saved');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
