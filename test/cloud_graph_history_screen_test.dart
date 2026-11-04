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
          CloudGraphHistoryEntry(key: 'synthetic-key', name: 'Historical cloud graph'),
          CloudGraphHistoryEntry(key: 'synthetic-key', name: 'Historical cloud graph'),
        ], null);
  }
  @override
  void close() {}
}

class _Portal extends UnavailableBugManPortalService {
  _Portal(this.document);
  final GraphDocument document;
  int loads = 0;
  @override
  bool get isAvailable => true;
  @override
  Future<PortalGraphPackage> loadGraph(String key) async {
    loads++;
    return PortalGraphPackage(document: document, blobs: {}, name: 'Historical cloud graph');
  }
}

void main() {
  testWidgets('cloud history paginates empty pages, deduplicates, previews without overwriting local identity', (tester) async {
    final local = MemoryGraphRepository();
    final localDocument = GraphDocument.forJob(Job(
      id: 'same-id', customerName: 'Local original', serviceAddress: '',
      pestPacLocationNumber: '', pestPacBillToNumber: '', serviceType: '',
      createdBy: '', createdDate: DateTime(2026)));
    await local.saveGraph(localDocument);
    final remoteDocument = GraphDocument.fromJson({
      'id': 'same-id', 'job': {'customerName': 'Cloud original'},
      'wallSegments': <Object?>[], 'annotations': <Object?>[],
      'shapes': <Object?>[], 'freehandStrokes': <Object?>[],
    });
    final history = _History(), portal = _Portal(remoteDocument);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(
      repository: local, cloudHistoryService: history, portalService: portal)));
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
    final preview = tester.widget<GraphCanvasScreen>(find.byType(GraphCanvasScreen));
    expect(preview.presentationMode, isTrue);
    expect(preview.completePackagePreview, isTrue);
    expect(preview.portalService!.isAvailable, isFalse);
    expect(portal.loads, 1);
    expect((await local.loadGraph('same-id'))!.customer.name, 'Local original');
    expect(remoteDocument.customer.name, 'Cloud original');
    expect(remoteDocument.isDirty, isFalse);
    expect(find.text('Cloud history · read only'), findsOneWidget);
  });

  testWidgets('failed cloud discovery is visible and retryable, never an empty success', (tester) async {
    final history = _History()..fail = true;
    final portal = _Portal(GraphDocument.fromJson({'job': {'customerName': 'Synthetic'}}));
    await tester.pumpWidget(MaterialApp(home: CloudGraphHistoryScreen(service: history, portal: portal)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cloud history could not be loaded'), findsOneWidget);
    expect(find.text('No shared cloud graphs found.'), findsNothing);
    history.fail = false;
    await tester.tap(find.byTooltip('Refresh cloud history'));
    await tester.pumpAndSettle();
    expect(find.text('Load more history'), findsOneWidget);
  });
}
