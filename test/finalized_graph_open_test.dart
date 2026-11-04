import 'dart:convert';
import 'dart:typed_data';

import 'package:bugman_graphs/main.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/screens/cloud_graph_history_screen.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:bugman_graphs/services/bugman_portal_service_stub.dart';
import 'package:bugman_graphs/services/cloud_graph_history.dart';
import 'package:bugman_graphs/services/graph_repository_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> finalizedResponse() {
  final claim = <String, dynamic>{
    'locked': true,
    'receiptVerified': true,
    'finalizedBy': 'synthetic-admin',
    'finalizedRole': 'admin',
    'finalizedAt': '2026-11-04T00:00:00Z',
    'snapshotSha256': 'a' * 64
  };
  return {
    'name': 'Synthetic finalized graph',
    'finalization': {...claim},
    'graph': {
      'type': 'bugman-graph',
      'version': 1,
      '_opsFinalization': {...claim},
      'document': {
        'id': 'same-id',
        'job': {'customerName': 'Finalized source'},
        'wallSegments': [
          {
            'start': {'x': 0, 'y': 0},
            'end': {'x': 240, 'y': 0}
          }
        ],
        'annotations': [],
        'shapes': [],
        'freehandStrokes': []
      },
      'blobs': {
        'full-photo': base64Encode([1, 2, 3]),
        'thumbnail': base64Encode([4, 5])
      }
    }
  };
}

class _Portal extends UnavailableBugManPortalService {
  _Portal(this.payload);
  final Map<String, dynamic> payload;
  @override
  bool get isAvailable => true;
  @override
  Future<PortalGraphPackage> loadGraph(String key) async =>
      PortalGraphPackage.fromResponse(
          jsonDecode(jsonEncode(payload)) as Map<String, dynamic>);
}

class _History extends CloudGraphHistoryService {
  @override
  bool get isAvailable => true;
  @override
  void close() {}
  @override
  Future<CloudGraphHistoryPage> list({String? cursor}) async =>
      const CloudGraphHistoryPage([
        CloudGraphHistoryEntry(
            key: 'synthetic-key',
            name: 'Synthetic finalized graph',
            finalized: true)
      ], null);
}

class _Repository extends MemoryGraphRepository {
  int saves = 0;
  @override
  Future<void> saveGraph(
    GraphDocument document, {
    Map<String, Uint8List> blobs = const {},
    Set<String> deletedBlobKeys = const {},
  }) {
    saves++;
    return super
        .saveGraph(document, blobs: blobs, deletedBlobKeys: deletedBlobKeys);
  }
}

void main() {
  test(
      'matching authenticated claims retain finalization and complete blob bytes',
      () {
    final package = PortalGraphPackage.fromResponse(finalizedResponse());
    expect(package.isFinalized, isTrue);
    expect(package.finalization!.snapshotSha256, 'a' * 64);
    expect(package.finalization!.finalizedBy, 'synthetic-admin');
    expect(package.blobs['full-photo'], [1, 2, 3]);
    expect(package.blobs['thumbnail'], [4, 5]);
    expect(package.document.wallSegments.single.measurementLabel, '10 lf');
  });

  final invalid = <String, void Function(Map<String, dynamic>)>{
    'missing response claim': (p) => p.remove('finalization'),
    'missing envelope claim': (p) =>
        (p['graph'] as Map).remove('_opsFinalization'),
    'unverified response': (p) => p['finalization']['receiptVerified'] = false,
    'unverified envelope': (p) =>
        p['graph']['_opsFinalization']['receiptVerified'] = false,
    'unlocked contradictory response': (p) =>
        p['finalization']['locked'] = false,
    'mismatched digest': (p) =>
        p['graph']['_opsFinalization']['snapshotSha256'] = 'b' * 64,
    'mismatched actor': (p) =>
        p['graph']['_opsFinalization']['finalizedBy'] = 'other-actor',
    'malformed claim': (p) => p['finalization'] = 'locked',
    'invalid timestamp': (p) {
      p['finalization']['finalizedAt'] = 'invalid';
      p['graph']['_opsFinalization']['finalizedAt'] = 'invalid';
    },
    'invalid digest': (p) {
      p['finalization']['snapshotSha256'] = 'invalid';
      p['graph']['_opsFinalization']['snapshotSha256'] = 'invalid';
    },
    'document-only lock hint': (p) {
      final claim = p.remove('finalization');
      p['graph'].remove('_opsFinalization');
      p['graph']['document']['metadata'] = {'_opsFinalization': claim};
    },
  };
  for (final entry in invalid.entries) {
    test('fails closed for ${entry.key}', () {
      final payload = finalizedResponse();
      entry.value(payload);
      expect(() => PortalGraphPackage.fromResponse(payload),
          throwsA(isA<PortalFinalizationException>()));
    });
  }

  for (final history in [false, true]) {
    testWidgets(
        '${history ? 'history' : 'deep link'} finalized opening is read only and never saves local document/photos',
        (tester) async {
      final repository = _Repository();
      final original = GraphDocument.fromJson({
        'id': 'same-id',
        'job': {'customerName': 'Local original'}
      });
      await repository.saveGraph(original, blobs: {
        'full-photo': Uint8List.fromList([9])
      });
      repository.saves = 0;
      final portal = _Portal(finalizedResponse());
      await tester.pumpWidget(history
          ? MaterialApp(
              home:
                  CloudGraphHistoryScreen(service: _History(), portal: portal))
          : BugManGraphsApp(
              accountDraftsEnabled: false,
              repository: repository,
              portalService: portal,
              initialUri: Uri.parse(
                  'http://localhost/bugman-graphs/?graph=synthetic-key')));
      await tester.pumpAndSettle();
      if (history) {
        await tester.tap(find.text('Synthetic finalized graph'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Locked · read only'), findsOneWidget);
      expect(find.byTooltip('+Note (T)'), findsNothing);
      expect(find.byTooltip('Save and share'), findsNothing);
      final preview =
          tester.widget<GraphCanvasScreen>(find.byType(GraphCanvasScreen));
      expect(preview.presentationMode, isTrue);
      expect(preview.completePackagePreview, isTrue);
      expect(preview.portalService!.isAvailable, isFalse);
      await expectLater(
          preview.repository!
              .saveGraph(preview.document!, blobs: {'new': Uint8List(1)}),
          throwsUnsupportedError);
      await expectLater(
          preview.repository!.deleteGraph('same-id'), throwsUnsupportedError);
      expect(repository.saves, 0);
      expect((await repository.loadGraph('same-id'))!.customer.name,
          'Local original');
      expect(await repository.loadBlob('full-photo'), [9]);
      expect(await repository.loadBlob('thumbnail'), isNull);
    });

    for (final missing in [false, true]) {
      testWidgets(
          '${history ? 'history' : 'deep link'} rejects ${missing ? 'missing' : 'contradictory'} finalization without persistent writes',
          (tester) async {
        final payload = finalizedResponse();
        if (missing) {
          payload.remove('finalization');
        } else {
          payload['finalization']['receiptVerified'] = false;
        }
        final repository = _Repository(), portal = _Portal(payload);
        await tester.pumpWidget(history
            ? MaterialApp(
                home: CloudGraphHistoryScreen(
                    service: _History(), portal: portal))
            : BugManGraphsApp(
                accountDraftsEnabled: false,
                repository: repository,
                portalService: portal,
                initialUri: Uri.parse(
                    'http://localhost/bugman-graphs/?graph=synthetic-key')));
        await tester.pumpAndSettle();
        if (history) {
          await tester.tap(find.text('Synthetic finalized graph'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(GraphCanvasScreen), findsNothing);
        expect(repository.saves, 0);
        expect(await repository.listGraphs(), isEmpty);
      });
    }
  }

  testWidgets(
      'ordinary legacy non-finalized deep links remain editable and restore full blobs',
      (tester) async {
    final payload = finalizedResponse()..remove('finalization');
    (payload['graph'] as Map).remove('_opsFinalization');
    final repository = _Repository();
    await tester.pumpWidget(BugManGraphsApp(
        accountDraftsEnabled: false,
        repository: repository,
        portalService: _Portal(payload),
        initialUri:
            Uri.parse('http://localhost/bugman-graphs/?graph=synthetic-key')));
    await tester.pumpAndSettle();
    final canvas =
        tester.widget<GraphCanvasScreen>(find.byType(GraphCanvasScreen));
    expect(canvas.presentationMode, isFalse);
    expect(repository.saves, 1);
    expect(await repository.loadBlob('full-photo'), [1, 2, 3]);
    expect(await repository.loadBlob('thumbnail'), [4, 5]);
  });

  testWidgets(
      'a finalized history row cannot silently downgrade to an unmarked package',
      (tester) async {
    final payload = finalizedResponse()..remove('finalization');
    (payload['graph'] as Map).remove('_opsFinalization');
    await tester.pumpWidget(MaterialApp(
        home: CloudGraphHistoryScreen(
            service: _History(), portal: _Portal(payload))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synthetic finalized graph'));
    await tester.pumpAndSettle();
    expect(find.byType(GraphCanvasScreen), findsNothing);
    expect(find.textContaining('could not be previewed'), findsOneWidget);
  });
}
