import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/screens/cloud_drafts/graph_draft_entry_screen.dart';
import 'package:bugman_graphs/screens/cloud_drafts/graph_draft_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/models/cloud_graph_draft.dart';
import 'package:bugman_graphs/screens/home_screen.dart';
import 'package:bugman_graphs/screens/new_job_screen.dart';
import 'package:bugman_graphs/screens/cloud_drafts/account_graph_gallery.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_activation.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_recovery.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_workspace.dart';
import 'package:bugman_graphs/widgets/cloud_drafts/graph_creator_picker.dart';
import 'graph_draft_sync_test.dart'
    show
        FixtureDraftService,
        workspace,
        ownerA,
        ownerB,
        creator,
        otherCreator,
        doc;

void main() {
  for (final deepLink in [false, true]) {
    testWidgets(
        'populated ${deepLink ? "deep-link" : "gallery"} form rejects account B and resumes original account A',
        (tester) async {
      final api = FixtureDraftService(), store = MemoryGraphDraftStore();
      final w = workspace(api, store);
      final b = workspace(FixtureDraftService(), store, scope: ownerB);
      final restored = workspace(api, store);
      var attempts = 0;
      Future<GraphDraftWorkspace> recover() async =>
          attempts++ == 0 ? b : restored;
      await tester.pumpWidget(MaterialApp(
          home: deepLink
              ? GraphDraftContextCreateScreen(
                  workspace: w,
                  resolution: Future.value(const GraphDraftEntryResolution()),
                  recoverWorkspace: recover)
              : AccountGraphGallery(workspace: w, recoverWorkspace: recover)));
      await tester.pumpAndSettle();
      if (!deepLink) {
        await tester.tap(find.text('New Graph'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('New Customer'));
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Company');
      await tester.enterText(field, 'Synthetic unfinished company');
      final controller = tester.widget<TextField>(field).controller!;
      w.account.invalidate();
      await tester.pumpAndSettle();
      expect(find.text('New graph interrupted'), findsOneWidget);
      expect(find.byType(NewJobScreen), findsNothing);
      expect(controller.text, 'Synthetic unfinished company');
      await tester.tap(find.text('Resume original form'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('This is a different account'), findsOneWidget);
      expect(find.byType(NewJobScreen), findsNothing);
      expect(await store.list(ownerB), isEmpty);
      await tester.tap(find.text('Resume original form'));
      await tester.pumpAndSettle();
      expect(find.byType(NewJobScreen), findsOneWidget);
      expect(tester.widget<TextField>(field).controller, same(controller));
      expect(controller.text, 'Synthetic unfinished company');
      Navigator.of(tester.element(find.byType(NewJobScreen))).pop(Job(
          pestPacLocationNumber: 'TEST-LOC',
          pestPacBillToNumber: 'TEST-BILL',
          customerName: 'Synthetic',
          serviceAddress: 'Synthetic training site',
          serviceType: 'Inspection',
          createdBy: 'Synthetic',
          createdDate: DateTime.utc(2026, 10, 12)));
      await tester.pumpAndSettle();
      final editor = tester
          .widget<GraphDraftEditorScreen>(find.byType(GraphDraftEditorScreen));
      expect(editor.session.workspace, same(restored));
      expect(editor.session.workspace.account.id, ownerA);
      expect(await store.list(ownerB), isEmpty);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      w.dispose();
    });
  }

  testWidgets(
      'account invalidation hides gallery and blocks recovery reopening without deleting stored work',
      (tester) async {
    final api = FixtureDraftService(), store = MemoryGraphDraftStore();
    final w = workspace(api, store);
    final original = await w.create(doc());
    await tester
        .pumpWidget(MaterialApp(home: AccountGraphGallery(workspace: w)));
    await tester.pumpAndSettle();
    expect(find.text(doc().customer.displayName), findsOneWidget);
    w.account.invalidate();
    await tester.pumpAndSettle();
    expect(find.text(doc().customer.displayName), findsNothing);
    expect(
        find.textContaining('Sign in to the original account'), findsOneWidget);
    await expectLater(w.open(original.id), throwsA(isA<Exception>()));
    expect(() => w.localGraphs(), throwsA(isA<Exception>()));
    expect(await store.read(ownerA, original.id), isNotNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    w.dispose();
  });

  testWidgets(
      'Home drains queued recovery and retries after reconnect without reopening editor',
      (tester) async {
    final api = FixtureDraftService()..failCode = 503;
    final store = MemoryGraphDraftStore();
    final recoveryWorkspace = workspace(api, store);
    final session = await recoveryWorkspace.create(doc());
    await tester.pumpWidget(
        MaterialApp(home: AccountGraphGallery(workspace: recoveryWorkspace)));
    await tester.pumpAndSettle();
    expect(session.hasQueuedEdits, isTrue);
    api.failCode = null;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(session.hasQueuedEdits, isFalse);
    expect(find.textContaining('Synced'), findsOneWidget);
    expect((await store.read(ownerA, session.id))!.revision, isNotNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    recoveryWorkspace.dispose();
  });

  testWidgets(
      'production gate stays closed and default home performs no cloud work',
      (tester) async {
    expect(createProductionGraphDraftWorkspace(), isNull);
    expect(accountGraphDraftsActivated, isFalse);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('My Graphs'), findsNothing);
    expect(find.text('New Job'), findsOneWidget);
  });
  testWidgets(
      'creator default is editable among active IDs and keeps inactive historical snapshot disabled',
      (tester) async {
    GraphDraftAuthor? selected;
    const directory = GraphDraftAuthors('employee-1', [creator, otherCreator]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GraphCreatorPicker(
                directory: directory,
                value: 'old-employee',
                historicalAuthor: const GraphDraftAuthor(
                    'old-employee', 'Historical synthetic creator'),
                onChanged: (a) => selected = a))));
    expect(find.text('Historical synthetic creator'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    final historical = tester.widget<DropdownMenuItem<String>>(find
        .widgetWithText(
            DropdownMenuItem<String>, 'Historical synthetic creator')
        .last);
    expect(historical.enabled, isFalse);
    await tester.tap(find.text('Other synthetic creator').last);
    await tester.pumpAndSettle();
    expect(selected!.id, otherCreator.id);
  });
  for (final size in [const Size(320, 568), const Size(1400, 900)]) {
    testWidgets(
        'account gallery is readable and account switch never shows prior owner at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final api = FixtureDraftService(),
          store = MemoryGraphDraftStore(),
          a = workspace(api, store),
          b = workspace(api, store, scope: ownerB);
      final d = doc();
      final json = d.toJson();
      (json['customer'] as Map)['name'] = 'Synthetic owner A only';
      await store.write(GraphDraftRecovery(accountId: ownerA, document: json));
      await tester
          .pumpWidget(MaterialApp(home: AccountGraphGallery(workspace: a)));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic owner A only'), findsOneWidget);
      expect(find.textContaining('Synced'), findsOneWidget);
      await tester
          .pumpWidget(MaterialApp(home: AccountGraphGallery(workspace: b)));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic owner A only'), findsNothing);
      expect(
          find.text('Your account graphs will appear here.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      a.dispose();
      b.dispose();
    });
  }
  testWidgets('new job uses directory default, not a name-only identity lookup',
      (tester) async {
    var nameLookups = 0;
    GraphDraftAuthor? selected;
    await tester.pumpWidget(MaterialApp(
        home: NewJobScreen(
            editOnly: true,
            onCreateJob: (_) {},
            authenticatedNameLoader: () async {
              nameLookups++;
              return 'Wrong name-only default';
            },
            cloudAuthors:
                const GraphDraftAuthors('employee-1', [creator, otherCreator]),
            cloudInitialAuthorId: 'employee-1',
            onCloudAuthorChanged: (a) => selected = a)));
    await tester.pumpAndSettle();
    expect(nameLookups, 0);
    final picker = find.byType(GraphCreatorPicker);
    await tester.scrollUntilVisible(picker, 300,
        scrollable: find
            .descendant(
                of: find.byType(NewJobScreen),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic creator'), findsOneWidget);
    await tester.tap(find.descendant(
        of: picker, matching: find.byType(DropdownButtonFormField<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other synthetic creator').last);
    await tester.pumpAndSettle();
    expect(selected!.id, 'employee-2');
    expect(tester.takeException(), isNull);
  });
}
