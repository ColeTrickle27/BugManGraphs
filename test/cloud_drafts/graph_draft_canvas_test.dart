import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_service.dart';
import 'package:bugman_graphs/widgets/cloud_drafts/graph_draft_sync_panel.dart';
import 'package:bugman_graphs/screens/trace_workspace_screen.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_recovery.dart';
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
      'held overwrite rejects a second identity switch and binds the late key only to its captured session',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final store = MemoryGraphDraftStore();
    final scoped = workspace(FixtureDraftService(), store);
    final session = await scoped.create(doc());
    await session.retry();
    await session.updatePortalKey('original/key.bgraph');
    final portal = HeldPublicationPortal();
    await tester.pumpWidget(MaterialApp(
        home: GraphDraftEditorScreen(session: session, portalService: portal)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save and share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Graph to BugMan Graphs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overwrite Existing'));
    await tester.pumpAndSettle();
    expect(portal.documents, hasLength(1));
    await tester.tap(find.byTooltip('Save and share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Graph to BugMan Graphs'));
    await tester.pumpAndSettle();
    expect(find.text('Save As New'), findsNothing);
    expect(find.text('A graph save is already in progress.'), findsOneWidget);
    final canvas =
        tester.widget<GraphCanvasScreen>(find.byType(GraphCanvasScreen));
    final active = (canvas.repository as GraphDraftEditorRepository).session;
    expect(active, same(session));
    final edited = canvas.document!;
    final segments = edited.wallSegments.toList();
    segments[0] = segments[0].copyWith(start: const GraphPoint(x: 750, y: 800));
    edited.replaceWallSegments(segments);
    await tester.pump();
    portal.release.complete(const PortalUploadResult(
        key: 'original/returned.bgraph', message: 'Graph saved'));
    await tester.pumpAndSettle();
    await session.flushLocal();
    expect(session.portalKey, 'original/returned.bgraph');
    expect(
        (await store.read(ownerA, session.id))!.portalKey, session.portalKey);
    expect(await store.list(ownerA), hasLength(1));
    expect(portal.documents, hasLength(1));
    expect(edited.isDirty, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await session.flushLocal();
    scoped.dispose();
  });

  testWidgets(
      'actual sync-panel preview locks when its owning account invalidates',
      (tester) async {
    final api = FixtureDraftService()..failCode = 409;
    final store = MemoryGraphDraftStore();
    final scoped = workspace(api, store), document = doc();
    api.remote = RemoteGraphDraft(
        GraphDraftPackage.fromJson({
          'type': 'bugman-graph',
          'version': 1,
          'document': document.toJson(),
          'blobs': <String, String>{}
        }),
        'a' * 32,
        const GraphDraftAuthor('employee-1', 'Synthetic'));
    final session = await scoped.create(document);
    await session.retry();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showGraphDraftSyncPanel(context, session),
                    child: const Text('Status'))))));
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review cloud copy'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<GraphDraftRemotePreview>(
                find.byType(GraphDraftRemotePreview))
            .account,
        same(scoped.account));
    expect(find.byType(GraphCanvasScreen), findsOneWidget);
    scoped.account.invalidate();
    await tester.pumpAndSettle();
    expect(find.byType(GraphCanvasScreen), findsNothing);
    expect(
        find.textContaining('Sign in to the original account'), findsOneWidget);
    expect(await store.read(ownerA, session.id), isNotNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Download recovery copy'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    scoped.dispose();
  });
  testWidgets(
      'open trace route hides address and trace controls on confirmed account mismatch',
      (tester) async {
    final account = GraphDraftAccount(id: ownerA, displayName: 'Synthetic');
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => TraceWorkspaceScreen(
                            account: account,
                            address: 'Synthetic private site',
                            canvasSize: const Size(3000, 3000),
                            traceLabel: 'Synthetic private trace',
                            initialTrace: doc().traces.first,
                            autoSelectJobAddress: false))),
                child: const Text('Trace')))));
    await tester.tap(find.text('Trace'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
    account.invalidate();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Synthetic private site'), findsNothing);
    expect(
        find.textContaining('Sign in to the original account'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TraceWorkspaceScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    account.dispose();
  });

  testWidgets(
      'confirmed account change locks current canvas without deleting recovery',
      (tester) async {
    final store = MemoryGraphDraftStore();
    final scoped = workspace(FixtureDraftService(), store);
    final original = await scoped.create(doc());
    await tester.pumpWidget(
        MaterialApp(home: GraphDraftEditorScreen(session: original)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('graph-canvas-paint')), findsOneWidget);
    await tester.tap(find.byTooltip('Save and share'));
    await tester.pumpAndSettle();
    expect(find.text('Save Graph to BugMan Graphs'), findsOneWidget);
    scoped.account.invalidate();
    await tester.pumpAndSettle();
    expect(find.text('Save Graph to BugMan Graphs'), findsNothing);
    expect(find.byKey(const ValueKey('graph-canvas-paint')), findsNothing);
    expect(find.byTooltip('Save and share'), findsNothing);
    expect(
        find.textContaining('Sign in to the original account'), findsOneWidget);
    expect(await store.read(ownerA, original.id), isNotNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await original.flushLocal();
    scoped.dispose();
  });

  testWidgets(
      '404 publication waits for delayed fork creation before binding its portal key',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final store = HeldForkStore();
    final scoped = workspace(FixtureDraftService(), store);
    final parent = await scoped.create(doc());
    await parent.retry();
    await parent.updatePortalKey('original/key.bgraph');
    final portal = MissingOriginalPortal();
    await tester.pumpWidget(MaterialApp(
        home: GraphDraftEditorScreen(session: parent, portalService: portal)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save and share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Graph to BugMan Graphs'));
    await tester.pumpAndSettle();
    store.hold = true;
    await tester.tap(find.text('Overwrite Existing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(store.started.isCompleted, isTrue);
    expect(portal.attempts, 1);
    expect(parent.portalKey, 'original/key.bgraph');
    store.release.complete();
    await tester.pumpAndSettle();
    final active = (tester
            .widget<GraphCanvasScreen>(find.byType(GraphCanvasScreen))
            .repository as GraphDraftEditorRepository)
        .session;
    expect(active.id, isNot(parent.id));
    expect(active.portalKey, 'synthetic/customer/graph.bgraph');
    expect(parent.portalKey, 'original/key.bgraph');
    expect((await store.read(ownerA, active.id))!.portalKey, active.portalKey);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    scoped.dispose();
  });

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
                        builder: (_) => GraphDraftRemotePreview(
                            remote: remote,
                            account: GraphDraftAccount(
                                id: ownerA, displayName: 'Synthetic')))),
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
      'open editor reconnect retries current Keep Both fork, not original conflict',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final api = FixtureDraftService()..failCode = 409;
    final store = MemoryGraphDraftStore();
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
    final original = await w.create(document);
    await original.retry();
    await tester.pumpWidget(
        MaterialApp(home: GraphDraftEditorScreen(session: original)));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byTooltip('Saved on this device · cloud copy differs'));
    await tester.pumpAndSettle();
    api.failCode = 503;
    await tester.tap(find.text('Keep both copies'));
    await tester.pumpAndSettle();
    final repository = tester
        .widget<GraphCanvasScreen>(find.byType(GraphCanvasScreen))
        .repository as GraphDraftEditorRepository;
    final fork = repository.session;
    expect(fork.id, isNot(original.id));
    expect(fork.hasQueuedEdits, isTrue);
    api.failCode = null;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(fork.hasQueuedEdits, isFalse);
    expect(original.recovery.errorCode, 409);
    expect((await store.read(ownerA, fork.id))!.revision, isNotNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    w.dispose();
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

class HeldForkStore extends MemoryGraphDraftStore {
  bool hold = false;
  final release = Completer<void>(), started = Completer<void>();
  @override
  Future<void> write(GraphDraftRecovery record) async {
    if (hold && record.id != 'synthetic-canvas-review') {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    await super.write(record);
  }
}

class MissingOriginalPortal extends RecordingDraftPortal {
  int attempts = 0;
  @override
  Future<PortalUploadResult> saveGraph(
      GraphDocument document, Map<String, Uint8List> blobs,
      {String? existingKey}) async {
    attempts++;
    if (existingKey != null) throw StateError('Saved graph not found.');
    return super.saveGraph(document, blobs, existingKey: existingKey);
  }
}

class HeldPublicationPortal extends RecordingDraftPortal {
  final release = Completer<PortalUploadResult>();
  final documents = <Map<String, Object?>>[];
  @override
  Future<PortalUploadResult> saveGraph(
      GraphDocument document, Map<String, Uint8List> blobs,
      {String? existingKey}) {
    documents.add(document.toJson());
    if (documents.length > 1) {
      throw StateError('Synthetic second publication fails');
    }
    return release.future;
  }
}
