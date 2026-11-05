import 'dart:convert';
import 'dart:typed_data';

import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:bugman_graphs/services/bugman_portal_service_stub.dart';
import 'package:bugman_graphs/services/cloud_graph_history.dart';
import 'package:bugman_graphs/services/cloud_graph_preview_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
      'history retains exact timestamp offsets and rejects normalized invalid dates',
      () async {
    final service = HttpCloudGraphHistoryService(
      origin: Uri.parse('https://ops.example.test/'),
      client: MockClient((_) async => http.Response(
          jsonEncode({
            'graphs': [
              {
                'key': 'synthetic-valid',
                'updatedAt': '2026-11-01T01:30:00.123-05:00'
              },
              {'key': 'synthetic-invalid', 'updatedAt': '2026-02-30T00:00:00Z'},
              {'key': 'synthetic-missing'},
            ],
            'truncated': false,
          }),
          200)),
    );
    final page = await service.list();
    expect(page.graphs.first.updatedAtRaw, '2026-11-01T01:30:00.123-05:00');
    expect(
        page.graphs.first.updatedAt, DateTime.utc(2026, 11, 1, 6, 30, 0, 123));
    expect(page.graphs[1].updatedAt, isNull);
    expect(page.graphs[1].updatedAtRaw, '2026-02-30T00:00:00Z');
    expect(page.graphs[2].updatedAt, isNull);
    service.close();
  });
  test('history is GET only and preserves opaque pagination cursors', () async {
    final requests = <http.Request>[];
    final service = HttpCloudGraphHistoryService(
      origin: Uri.parse('https://ops.example.test/'),
      client: MockClient((request) async {
        requests.add(request);
        final first = request.url.queryParameters['cursor'] == null;
        return http.Response(
          jsonEncode({
            'graphs': first
                ? []
                : [
                    {
                      'key':
                          'bill-tos/synthetic/location/bugman-graphs/old.bgraph',
                      'name': 'Historical graph',
                      'updatedAt': '2026-01-01T00:00:00Z',
                      'finalization': {'locked': true},
                    },
                  ],
            'truncated': first,
            'nextCursor': first ? 'opaque+/= token' : null,
          }),
          200,
        );
      }),
    );
    final first = await service.list();
    expect(first.graphs, isEmpty);
    expect(first.nextCursor, 'opaque+/= token');
    final second = await service.list(cursor: first.nextCursor);
    expect(second.graphs.single.finalized, isTrue);
    expect(second.nextCursor, isNull);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    expect(
      requests.every((r) => r.url.path == '/api/bugman-graphs/recent'),
      isTrue,
    );
    expect(requests.last.url.queryParameters['cursor'], 'opaque+/= token');
    service.close();
  });

  test('authentication and authorization failures remain distinct', () async {
    for (final status in [401, 403]) {
      final service = HttpCloudGraphHistoryService(
        origin: Uri.parse('https://ops.example.test/'),
        client: MockClient((_) async => http.Response('{}', status)),
      );
      await expectLater(
        service.list(),
        throwsA(
          status == 401
              ? isA<PortalAuthenticationException>()
              : isA<CloudGraphHistoryAccessException>(),
        ),
      );
      service.close();
    }
  });

  test(
    'truncated history cannot silently finish or repeat its cursor',
    () async {
      for (final next in [null, '', 'same']) {
        final service = HttpCloudGraphHistoryService(
          origin: Uri.parse('https://ops.example.test/'),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'graphs': [], 'truncated': true, 'nextCursor': next}),
              200,
            ),
          ),
        );
        await expectLater(service.list(cursor: 'same'), throwsFormatException);
        service.close();
      }
    },
  );

  test(
    'HTML and malformed entries are failures, never an empty success',
    () async {
      for (final body in [
        '<html>Sign in</html>',
        jsonEncode({
          'graphs': [{}],
          'truncated': false,
        }),
      ]) {
        final service = HttpCloudGraphHistoryService(
          origin: Uri.parse('https://ops.example.test/'),
          client: MockClient((_) async => http.Response(body, 200)),
        );
        await expectLater(service.list(), throwsFormatException);
        service.close();
      }
    },
  );

  test(
      'old flat graph preview preserves geometry, photos and unknown fields without writes',
      () async {
    final source = <String, Object?>{
      'id': 'historical-id',
      'job': {
        'customerName': 'Synthetic historic customer',
        'pestPacAccountNumber': 'LEGACY-300',
      },
      'wallSegments': [
        {
          'start': {'x': 0, 'y': 0},
          'end': {'x': 24, 'y': 0},
        },
      ],
      'annotations': <Object?>[],
      'shapes': <Object?>[],
      'freehandStrokes': <Object?>[],
      'attachments': [
        {
          'id': 'photo',
          'name': 'photo.png',
          'blobKey': 'full',
          'thumbnailKey': 'thumb',
        },
      ],
      'legacyVendorField': 'retain',
    };
    final serializedSource = jsonEncode(source);
    final document = GraphDocument.fromJson(source);
    final full = Uint8List.fromList([1, 2, 3]);
    final thumb = Uint8List.fromList([4, 5]);
    final repository = CloudGraphPreviewRepository(
      PortalGraphPackage(
        document: document,
        blobs: {'full': full, 'thumb': thumb},
        name: 'Old graph',
      ),
    );
    expect((await repository.listGraphs()).single.id, 'historical-id');
    expect(
      (await repository.loadGraph('historical-id'))!
          .wallSegments
          .single
          .measurementLabel,
      '1 lf',
    );
    expect(document.customer.pestPacLocationNumber, 'LEGACY-300');
    expect(document.toJson()['legacyVendorField'], 'retain');
    expect(await repository.loadBlob('full'), full);
    expect(await repository.loadBlob('thumb'), thumb);
    expect(await repository.loadGraph('other-id'), isNull);
    await expectLater(repository.saveGraph(document), throwsUnsupportedError);
    await expectLater(
      repository.saveGraph(
        document,
        blobs: {
          'full': Uint8List.fromList([9]),
        },
        deletedBlobKeys: {'thumb'},
      ),
      throwsUnsupportedError,
    );
    await expectLater(
      repository.deleteGraph(document.id),
      throwsUnsupportedError,
    );
    final portal = UnavailableBugManPortalService();
    await expectLater(
      portal.saveGraph(document, {'full': full}, existingKey: 'original-key'),
      throwsUnsupportedError,
    );
    await expectLater(
      portal.uploadGraphExport(
        customer: document.customer,
        fileName: 'photo.png',
        bytes: full,
        contentType: 'image/png',
        graphCreatedAt: document.createdAt,
      ),
      throwsUnsupportedError,
    );
    expect(await repository.loadBlob('full'), full);
    expect(await repository.loadBlob('thumb'), thumb);
    expect(jsonEncode(source), serializedSource);
    expect(document.isDirty, isFalse);
  });
}
