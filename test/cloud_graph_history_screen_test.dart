import 'dart:async';

import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/screens/cloud_graph_history_screen.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/screens/home_screen.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:bugman_graphs/services/bugman_portal_service_stub.dart';
import 'package:bugman_graphs/services/cloud_graph_history.dart';
import 'package:bugman_graphs/services/graph_repository_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _History extends CloudGraphHistoryService {
  final calls = <String?>[];
  bool fail = false;
  @override
  bool get isAvailable => true;
  @override
  Future<CloudGraphHistoryPage> list({String? cursor}) async {
    calls.add(cursor);
    if (fail) throw const FormatException('Unavailable');
    return cursor == null
        ? const CloudGraphHistoryPage([], 'page2')
        : const CloudGraphHistoryPage([
            CloudGraphHistoryEntry(
              key: 'synthetic-key',
              name: 'Historical cloud graph',
            ),
            CloudGraphHistoryEntry(
              key: 'synthetic-key',
              name: 'Historical cloud graph',
            ),
          ], null);
  }

  @override
  void close() {}
}

class _Portal extends UnavailableBugManPortalService {
  _Portal(this.document);
  final GraphDocument document;
  int loads = 0;
  String? requestedKey;
  @override
  bool get isAvailable => true;
  @override
  Future<PortalGraphPackage> loadGraph(String key) async {
    loads++;
    requestedKey = key;
    return PortalGraphPackage(
      document: document,
      blobs: {},
      name: 'Historical cloud graph',
    );
  }
}

class _ControlledHistory extends _History {
  _ControlledHistory(this.respond);
  final Future<CloudGraphHistoryPage> Function(String?) respond;
  @override
  Future<CloudGraphHistoryPage> list({String? cursor}) => respond(cursor);
}

void main() {
  testWidgets(
      'cloud date display preserves instant sorting, exact offsets and unknown fallback',
      (t) async {
    final history = _ControlledHistory((_) async => CloudGraphHistoryPage([
          CloudGraphHistoryEntry(
              key: 'early',
              name: 'Early repeat',
              updatedAt: DateTime.parse('2026-11-01T01:45:00-04:00'),
              updatedAtRaw: '2026-11-01T01:45:00-04:00'),
          CloudGraphHistoryEntry(
              key: 'late',
              name: 'Late repeat',
              updatedAt: DateTime.parse('2026-11-01T01:30:00-05:00'),
              updatedAtRaw: '2026-11-01T01:30:00-05:00'),
          const CloudGraphHistoryEntry(
              key: 'invalid', name: 'Invalid date', updatedAtRaw: 'invalid'),
          const CloudGraphHistoryEntry(key: 'missing', name: 'Missing date'),
        ], null));
    final doc = GraphDocument.forJob(Job(
        customerName: 'Synthetic',
        serviceAddress: '',
        pestPacLocationNumber: '',
        pestPacBillToNumber: '',
        serviceType: '',
        createdBy: '',
        createdDate: DateTime(2026)));
    await t.pumpWidget(MaterialApp(
        home: CloudGraphHistoryScreen(service: history, portal: _Portal(doc))));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('Late repeat')).dy,
        lessThan(t.getTopLeft(find.text('Early repeat')).dy));
    expect(t.getTopLeft(find.text('Early repeat')).dy,
        lessThan(t.getTopLeft(find.text('Invalid date')).dy));
    expect(find.byTooltip('Exact timestamp: 2026-11-01T01:30:00-05:00'),
        findsOneWidget);
    expect(find.text('Date unavailable'), findsNWidgets(2));
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'cloud history paginates empty pages, deduplicates, previews without overwriting local identity',
    (tester) async {
      final local = MemoryGraphRepository();
      final localDocument = GraphDocument.forJob(
        Job(
          id: 'same-id',
          customerName: 'Local original',
          serviceAddress: '',
          pestPacLocationNumber: '',
          pestPacBillToNumber: '',
          serviceType: '',
          createdBy: '',
          createdDate: DateTime(2026),
        ),
      );
      await local.saveGraph(localDocument);
      final remoteDocument = GraphDocument.fromJson({
        'id': 'same-id',
        'job': {'customerName': 'Cloud original'},
        'metadata': {'portalKey': 'company/Other/unauthorized.bgraph'},
        'wallSegments': [
          {
            'start': {'x': 0, 'y': 0},
            'end': {'x': 240, 'y': 0}
          },
        ],
        'annotations': <Object?>[],
        'shapes': <Object?>[],
        'freehandStrokes': <Object?>[],
      });
      final history = _History(), portal = _Portal(remoteDocument);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            repository: local,
            cloudHistoryService: history,
            portalService: portal,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cloud graph history'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No graphs on this page'), findsOneWidget);
      await tester.tap(find.text('Load more history'));
      await tester.pumpAndSettle();
      expect(history.calls, [null, 'page2']);
      expect(find.text('Historical cloud graph'), findsOneWidget);
      await tester.tap(find.text('Historical cloud graph'));
      await tester.pumpAndSettle();
      final preview = tester.widget<GraphCanvasScreen>(
        find.byType(GraphCanvasScreen),
      );
      expect(preview.presentationMode, isTrue);
      expect(preview.completePackagePreview, isTrue);
      expect(preview.presentationFitToContent, isTrue);
      final viewerFinder = find.descendant(
          of: find.byType(GraphCanvasScreen),
          matching: find.byType(InteractiveViewer));
      final viewer = tester.widget<InteractiveViewer>(viewerFinder);
      final viewport = tester.getSize(viewerFinder);
      final displayedCenter = MatrixUtils.transformPoint(
          viewer.transformationController!.value, const Offset(120, 0));
      expect(displayedCenter.dx, closeTo(viewport.width / 2, 0.01));
      expect(displayedCenter.dy, closeTo(viewport.height / 2, 0.01));
      expect(remoteDocument.wallSegments.single.start.x, 0);
      expect(remoteDocument.wallSegments.single.end.x, 240);
      expect(preview.portalService!.isAvailable, isFalse);
      expect(preview.portalKey, isNull);
      expect(portal.requestedKey, 'synthetic-key');
      expect(portal.loads, 1);
      expect(
        (await local.loadGraph('same-id'))!.customer.name,
        'Local original',
      );
      expect(remoteDocument.customer.name, 'Cloud original');
      expect(remoteDocument.isDirty, isFalse);
      expect(find.text('Cloud history · read only'), findsOneWidget);
    },
  );

  for (final forbidden in [false, true]) {
    testWidgets(
      '${forbidden ? "forbidden" : "expired"} access mid-pagination clears cloud metadata',
      (tester) async {
        final history = _ControlledHistory((cursor) async {
          if (cursor != null) {
            if (forbidden) throw CloudGraphHistoryAccessException();
            throw const PortalAuthenticationException(
              'https://ops.example.test/',
            );
          }
          return const CloudGraphHistoryPage([
            CloudGraphHistoryEntry(
              key: 'synthetic-key',
              name: 'Visible before expiry',
            ),
          ], 'next');
        });
        final portal = _Portal(
          GraphDocument.fromJson({
            'job': {'customerName': 'Synthetic'},
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CloudGraphHistoryScreen(service: history, portal: portal),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Visible before expiry'), findsOneWidget);
        await tester.tap(find.text('Load more history'));
        await tester.pumpAndSettle();
        expect(find.text('Visible before expiry'), findsNothing);
        expect(find.text('Load more history'), findsNothing);
        expect(
          find.textContaining(
            forbidden ? 'cannot access' : 'Sign in to OpsBrain,',
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('an older response cannot replace a refreshed service result', (
    tester,
  ) async {
    final delayed = Completer<CloudGraphHistoryPage>();
    final old = _ControlledHistory((_) => delayed.future);
    final newer = _ControlledHistory(
      (_) async => const CloudGraphHistoryPage([
        CloudGraphHistoryEntry(key: 'new-key', name: 'Newer result'),
      ], null),
    );
    final portal = _Portal(
      GraphDocument.fromJson({
        'job': {'customerName': 'Synthetic'},
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudGraphHistoryScreen(service: old, portal: portal),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: CloudGraphHistoryScreen(service: newer, portal: portal),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Newer result'), findsOneWidget);
    delayed.complete(
      const CloudGraphHistoryPage([
        CloudGraphHistoryEntry(key: 'old-key', name: 'Stale result'),
      ], null),
    );
    await tester.pumpAndSettle();
    expect(find.text('Newer result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
  });

  testWidgets(
    'a repeated cursor fails visibly and retains already loaded history',
    (tester) async {
      var page = 0;
      final history = _ControlledHistory(
        (_) async => CloudGraphHistoryPage(
          [
            const CloudGraphHistoryEntry(
              key: 'synthetic-key',
              name: 'Existing result',
            ),
          ],
          ++page == 1
              ? 'page2'
              : page == 2
                  ? 'page3'
                  : 'page2',
        ),
      );
      final portal = _Portal(
        GraphDocument.fromJson({
          'job': {'customerName': 'Synthetic'},
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudGraphHistoryScreen(service: history, portal: portal),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Load more history'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Existing result'), findsOneWidget);
      expect(
        find.textContaining('Cloud history could not be loaded'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'failed cloud discovery is visible and retryable, never an empty success',
    (tester) async {
      final history = _History()..fail = true;
      final portal = _Portal(
        GraphDocument.fromJson({
          'job': {'customerName': 'Synthetic'},
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CloudGraphHistoryScreen(service: history, portal: portal),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cloud history could not be loaded'),
        findsOneWidget,
      );
      expect(find.text('No shared cloud graphs found.'), findsNothing);
      history.fail = false;
      await tester.tap(find.byTooltip('Refresh cloud history'));
      await tester.pumpAndSettle();
      expect(find.text('Load more history'), findsOneWidget);
    },
  );
}
