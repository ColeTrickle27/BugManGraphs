import 'package:bugman_graphs/models/cloud_graph_draft.dart';
import 'package:bugman_graphs/screens/cloud_drafts/account_graph_gallery.dart';
import 'package:bugman_graphs/screens/cloud_drafts/account_form_guard.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bugman_graphs/main.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:bugman_graphs/services/customer_files_service.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_authentication.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/models/customer_file.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/screens/new_job_screen.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/screens/cloud_drafts/graph_draft_entry_screen.dart';
import 'package:bugman_graphs/screens/cloud_drafts/graph_draft_editor_screen.dart';
import 'package:bugman_graphs/services/graph_repository_stub.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store.dart';
import 'graph_draft_sync_test.dart'
    show FixtureDraftService, workspace, ownerA, doc, otherCreator, moved;

void main() {
  for (final shared in [false, true]) {
    testWidgets(
        'uncached offline author directory explains choices without discarding creation form',
        (tester) async {
      final api = NetworkAuthorsFixture()..offline = true;
      final w = workspace(api, MemoryGraphDraftStore());
      await tester.pumpWidget(MaterialApp(
          home: GraphDraftContextCreateScreen(
              workspace: w,
              resolution: Future.value(const GraphDraftEntryResolution()))));
      await tester.pumpAndSettle();
      expect(find.byType(NewJobScreen), findsOneWidget);
      expect(
          find.textContaining('Creator choices are unavailable while offline'),
          findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      w.dispose();
    });
    testWidgets(
        '${shared ? "shared copy" : "gallery creation"} uses verified author cache when authors request loses network',
        (tester) async {
      final api = NetworkAuthorsFixture(), store = MemoryGraphDraftStore();
      final w = workspace(api, store);
      await w.refreshAuthors();
      api.offline = true;
      await tester.pumpWidget(MaterialApp(
          home: shared
              ? GraphDraftSharedEntryScreen(
                  workspace: w,
                  document: doc(),
                  repository: MemoryGraphRepository(),
                  portalKey: 'synthetic/shared.bgraph')
              : AccountGraphGallery(workspace: w)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(shared ? 'Copy to My Graphs' : 'New Graph'));
      await tester.pumpAndSettle();
      expect(api.offlineCalls, greaterThan(0));
      expect(w.directory!.authors, contains(otherCreator));
      if (shared) {
        final editor = tester.widget<GraphDraftEditorScreen>(
            find.byType(GraphDraftEditorScreen));
        expect(editor.session.workspace.account.id, ownerA);
        expect(editor.session.displayedAuthor?.id, 'employee-1');
      } else {
        expect(find.byType(NewJobScreen), findsOneWidget);
        expect(
            tester
                .widget<NewJobScreen>(find.byType(NewJobScreen))
                .cloudAuthors!
                .defaultAuthorId,
            'employee-1');
      }
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      w.dispose();
    });
  }
  testWidgets(
      'full app deep-link form survives wrapper invalidation, original login and author deactivation',
      (tester) async {
    var removed = false;
    final auth = entryAuth([],
        authorsBody: () => removed
            ? '{"defaultAuthorId":"employee-2","authors":[{"id":"employee-2","name":"Other synthetic creator"}]}'
            : '{"defaultAuthorId":"employee-1","authors":[{"id":"employee-1","name":"Synthetic"}]}');
    await tester.pumpWidget(BugManGraphsApp(
        accountDraftsEnabled: true,
        authentication: auth,
        initialUri: Uri.parse(
            'https://fixture.invalid/?billTo=TEST-BILL&location=TEST-LOC'),
        repository: MemoryGraphRepository(),
        customerFilesService: EntryCustomerService([])));
    await tester.pumpAndSettle();
    final owningState = tester
        .state(find.byType(GraphDraftContextCreateScreen, skipOffstage: false));
    await tester.tap(find.text('New Customer'));
    await tester.pumpAndSettle();
    final company = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Company');
    await tester.enterText(company, 'Synthetic preserved company');
    final controller = tester.widget<TextField>(company).controller!;
    final focus = tester
        .widget<EditableText>(
            find.descendant(of: company, matching: find.byType(EditableText)))
        .focusNode;
    final original = tester
        .widget<AccountFormGuard>(find.byType(AccountFormGuard))
        .workspace;
    removed = true;
    original.account.invalidate();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(find.byType(NewJobScreen), findsNothing);
    expect(
        tester.state(
            find.byType(GraphDraftContextCreateScreen, skipOffstage: false)),
        same(owningState));
    await tester.tap(find.text('Resume original form'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Username'),
        'synthetic');
    await tester.enterText(
        find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Password'),
        'synthetic-fixture-only');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(company).controller, same(controller));
    expect(controller.text, 'Synthetic preserved company');
    expect(find.textContaining('previously selected creator'), findsOneWidget);
    final form = tester.widget<NewJobScreen>(find.byType(NewJobScreen));
    expect(form.cloudAuthors!.authors.single.id, 'employee-2');
    await tester.scrollUntilVisible(find.text('Create Graph'), 300,
        scrollable: find
            .descendant(
                of: find.byType(NewJobScreen),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Create Graph'));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<GraphDraftEditorScreen>(find.byType(GraphDraftEditorScreen));
    expect(editor.session.workspace.account.id, ownerA);
    expect(editor.session.displayedAuthor?.id, 'employee-2');
    expect(
        GraphDocument.fromJson(editor.session.documentJson)
            .customer
            .displayName,
        'Synthetic preserved company');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    auth.close();
  });
  testWidgets(
      'actual billTo/location URL authenticates before lookup and selects account creation route',
      (tester) async {
    final events = <String>[];
    final auth = entryAuth(events);
    await tester.pumpWidget(BugManGraphsApp(
        accountDraftsEnabled: true,
        authentication: auth,
        initialUri: Uri.parse(
            'https://fixture.invalid/?billTo=TEST-BILL&location=TEST-LOC'),
        repository: MemoryGraphRepository(),
        customerFilesService: EntryCustomerService(events)));
    await tester.pumpAndSettle();
    expect(find.byType(GraphDraftContextCreateScreen, skipOffstage: false),
        findsOneWidget);
    expect(find.byType(NewJobScreen), findsOneWidget);
    expect(events.indexOf('context'), lessThan(events.indexOf('customer')));
    final form = tester.widget<NewJobScreen>(find.byType(NewJobScreen));
    expect(form.returnCreatedJob, isTrue);
    expect(form.preselectedLocation!.billToNumber, 'TEST-BILL');
    expect(form.preselectedLocation!.locationNumber, 'TEST-LOC');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    auth.close();
  });
  testWidgets(
      'actual graph URL authenticates before shared-folder load and requests explicit copy',
      (tester) async {
    final events = <String>[];
    final checked = entryAuth(events), repo = MemoryGraphRepository();
    await tester.pumpWidget(BugManGraphsApp(
        accountDraftsEnabled: true,
        authentication: checked,
        initialUri:
            Uri.parse('https://fixture.invalid/?graph=synthetic-shared'),
        repository: repo,
        portalService: EntryPortal(events)));
    await tester.pumpAndSettle();
    expect(find.byType(GraphDraftSharedEntryScreen), findsOneWidget);
    expect(find.text('Copy to My Graphs'), findsOneWidget);
    expect(find.byType(GraphCanvasScreen), findsNothing);
    expect(events.indexOf('context'), lessThan(events.indexOf('shared')));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    checked.close();
  });

  testWidgets(
      'verified bill-to/location creation route uses account session and preserves customer mapping',
      (tester) async {
    final store = MemoryGraphDraftStore(),
        w = workspace(FixtureDraftService(), MemoryGraphDraftStore());
    final scoped = workspace(FixtureDraftService(), store);
    const location = CustomerLocation(
        billToNumber: 'TEST-BILL',
        billToName: 'Synthetic',
        locationNumber: 'TEST-LOC',
        locationName: 'Synthetic site',
        locationAddress: 'Synthetic training site');
    await tester.pumpWidget(MaterialApp(
        home: GraphDraftContextCreateScreen(
            workspace: scoped,
            resolution: Future.value(
                const GraphDraftEntryResolution(location: location)))));
    await tester.pumpAndSettle();
    final form = tester.widget<NewJobScreen>(find.byType(NewJobScreen));
    expect(form.preselectedLocation, location);
    expect(form.returnCreatedJob, isTrue);
    expect(form.cloudAuthors, isNotNull);
    final context = tester.element(find.byType(NewJobScreen));
    Navigator.pop(
        context,
        Job(
            customerName: 'Synthetic',
            serviceAddress: 'Synthetic training site',
            pestPacBillToNumber: 'TEST-BILL',
            pestPacLocationNumber: 'TEST-LOC',
            serviceType: 'Inspection',
            createdBy: 'Synthetic',
            createdDate: DateTime.utc(2026, 10, 12)));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<GraphDraftEditorScreen>(find.byType(GraphDraftEditorScreen));
    expect(editor.session.workspace, same(scoped));
    final customer =
        GraphDocument.fromJson(editor.session.documentJson).customer;
    expect(customer.pestPacBillToNumber, 'TEST-BILL');
    expect(customer.pestPacLocationNumber, 'TEST-LOC');
    expect(customer.serviceAddress, 'Synthetic training site');
    expect(await store.read(ownerA, editor.session.id), isNotNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await editor.session.flushLocal();
    scoped.dispose();
    w.dispose();
  });
  testWidgets(
      'shared folder route never adopts source; explicit copy creates independent account identity',
      (tester) async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        repo = MemoryGraphRepository(),
        source = doc();
    final w = workspace(api, store);
    await repo.saveGraph(source);
    final before = source.toJson();
    await tester.pumpWidget(MaterialApp(
        home: GraphDraftSharedEntryScreen(
            workspace: w,
            document: source,
            repository: repo,
            portalKey: 'synthetic/shared.bgraph')));
    await tester.pumpAndSettle();
    expect(await store.list(ownerA), isEmpty);
    expect(api.writes, isEmpty);
    expect(find.byType(GraphCanvasScreen), findsNothing);
    await tester.tap(find.text('Copy to My Graphs'));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<GraphDraftEditorScreen>(find.byType(GraphDraftEditorScreen));
    expect(editor.session.id, isNot(source.id));
    expect(editor.session.portalKey, isNull);
    expect(api.writes, hasLength(1));
    expect(w.directory!.authors, contains(otherCreator));
    editor.session.selectAuthor(otherCreator);
    await editor.session.retry();
    expect(api.writes.last['authorId'], otherCreator.id);
    expect((await repo.loadGraph(source.id))!.toJson(), before);
    expect(source.toJson(), before);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await editor.session.flushLocal();
    w.dispose();
  });
  testWidgets('offline shared copy edits retry in the open editor without Home',
      (tester) async {
    final api = FixtureDraftService()..failCode = 503;
    final store = MemoryGraphDraftStore(), repo = MemoryGraphRepository();
    final w = workspace(api, store), source = doc();
    await tester.pumpWidget(MaterialApp(
        home: GraphDraftSharedEntryScreen(
            workspace: w,
            document: source,
            repository: repo,
            portalKey: 'synthetic/shared.bgraph')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy to My Graphs'));
    await tester.pumpAndSettle();
    final session = tester
        .widget<GraphDraftEditorScreen>(find.byType(GraphDraftEditorScreen))
        .session;
    session.capture(moved(session));
    await session.flushLocal();
    expect(session.hasQueuedEdits, isTrue);
    api.failCode = null;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(session.hasQueuedEdits, isFalse);
    expect(api.writes.length, greaterThanOrEqualTo(2));
    expect(
        (await store.read(ownerA, session.id))!.document, session.documentJson);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    w.dispose();
  });
  testWidgets(
      'existing shared open stays in legacy repository and does not create an account draft',
      (tester) async {
    final store = MemoryGraphDraftStore(),
        repo = MemoryGraphRepository(),
        source = doc(),
        w = workspace(FixtureDraftService(), MemoryGraphDraftStore());
    final scoped = workspace(FixtureDraftService(), store);
    await tester.pumpWidget(MaterialApp(
        home: GraphDraftSharedEntryScreen(
            workspace: scoped,
            document: source,
            repository: repo,
            portalKey: 'synthetic/shared.bgraph')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Customer Files graph'));
    await tester.pumpAndSettle();
    final canvas =
        tester.widget<GraphCanvasScreen>(find.byType(GraphCanvasScreen));
    expect(canvas.repository, same(repo));
    expect(canvas.cloudDraftSession, isNull);
    expect(canvas.portalKey, 'synthetic/shared.bgraph');
    expect(await store.list(ownerA), isEmpty);
    expect(canvas.onCreateAccountGraph, isNotNull);
    await tester.tap(find.byTooltip('Save and share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Structure to New Graph'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start New Graph'));
    await tester.pumpAndSettle();
    final copied = tester
        .widget<GraphDraftEditorScreen>(find.byType(GraphDraftEditorScreen));
    expect(copied.session.workspace, same(scoped));
    expect(copied.session.id, isNot(source.id));
    expect(scoped.directory!.authors, contains(otherCreator));
    copied.session.selectAuthor(otherCreator);
    await copied.session.retry();
    expect(copied.session.displayedAuthor?.id, otherCreator.id);
    scoped.account.invalidate();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('graph-canvas-paint')), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    scoped.dispose();
    w.dispose();
  });
}

GraphDraftAuthentication entryAuth(List<String> events,
        {String Function()? authorsBody}) =>
    GraphDraftAuthentication(
        origin: Uri.parse('https://fixture.invalid'),
        currentOrigin: Uri.parse('https://fixture.invalid'),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/context')) {
            events.add('context');
            return http.Response(jsonEncode({'accountId': ownerA}), 200);
          }
          if (r.url.path.endsWith('/authors')) {
            return http.Response(
                authorsBody?.call() ??
                    '{"defaultAuthorId":"employee-1","authors":[{"id":"employee-1","name":"Synthetic"}]}',
                200);
          }
          if (r.url.path == '/api/graph-drafts') {
            return http.Response('{"drafts":[],"nextCursor":null}', 200);
          }
          return http.Response('{"user":{"name":"Synthetic"}}', 200);
        }));

class EntryCustomerService implements CustomerFilesService {
  EntryCustomerService(this.events);
  final List<String> events;
  @override
  bool get isAvailable => true;
  @override
  Future<CustomerLocation?> getLocation(String bill, String location) async {
    events.add('customer');
    return CustomerLocation(
        billToNumber: bill,
        billToName: 'Synthetic',
        locationNumber: location,
        locationName: 'Synthetic site',
        locationAddress: 'Synthetic training site');
  }

  @override
  Future<List<CustomerLocation>> getLocations(String bill) async => [];
  @override
  Future<List<CustomerSearchResult>> searchCustomers(String query) async => [];
}

class EntryPortal implements BugManPortalService {
  EntryPortal(this.events);
  final List<String> events;
  @override
  bool get isAvailable => true;
  @override
  Future<PortalGraphPackage> loadGraph(String key) async {
    events.add('shared');
    return PortalGraphPackage(
        document: doc(), blobs: {}, name: 'Synthetic shared');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class NetworkAuthorsFixture extends FixtureDraftService {
  bool offline = false;
  int offlineCalls = 0;
  @override
  Future<GraphDraftAuthors> authors() async {
    if (offline) {
      offlineCalls++;
      throw Exception('Synthetic authors connection unavailable');
    }
    return super.authors();
  }
}
