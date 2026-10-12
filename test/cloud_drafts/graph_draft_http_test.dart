import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bugman_graphs/models/cloud_graph_draft.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_http_service.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_service.dart';
import '../support/crowded_canvas_fixture.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_workspace.dart';

const scope = '11111111-1111-4111-8111-111111111111';
final origin = Uri.parse('https://fixture.invalid');
GraphDraftPackage package(
        {Map<String, Object?>? document,
        Map<String, String> blobs = const {}}) =>
    GraphDraftPackage.fromJson({
      'type': 'bugman-graph',
      'version': 1,
      'document': document ?? crowdedCanvasFixture().toJson(),
      'blobs': blobs,
      'unknownPackageField': {'keep': 'unchanged'}
    });
HttpGraphDraftService service(MockClient client,
        {GraphDraftAccount? account}) =>
    HttpGraphDraftService(
        client: client,
        origin: origin,
        currentOrigin: origin,
        account: account ??
            GraphDraftAccount(id: scope, displayName: 'Synthetic account'));
Map<String, Object?> ack(String id) => {
      'id': id,
      'revision': 'a' * 32,
      'updatedAt': '2026-10-12T12:00:00Z',
      'author': {'id': 'employee-1', 'name': 'Synthetic creator'}
    };
void main() {
  test(
      'server context pins every draft request and account switch preserves original recovery',
      () async {
    var actualAccount = scope;
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/context')) {
        return http.Response(jsonEncode({'accountId': actualAccount}), 200);
      }
      expect(request.headers['X-Graph-Expected-Account-Id'], scope);
      if (actualAccount != scope) {
        return http.Response(
            jsonEncode({'error': 'Account scope mismatch'}), 409);
      }
      if (request.url.path.endsWith('/authors')) {
        return http.Response(
            jsonEncode({
              'defaultAuthorId': 'employee-1',
              'authors': [
                {'id': 'employee-1', 'name': 'Synthetic'}
              ]
            }),
            200);
      }
      if (request.url.path == '/api/graph-drafts') {
        return http.Response(
            jsonEncode({'drafts': [], 'nextCursor': null}), 200);
      }
      if (request.method == 'GET') {
        return http.Response(
            jsonEncode({...ack(package().id), 'package': package().toJson()}),
            200);
      }
      return http.Response(jsonEncode(ack(package().id)), 201);
    });
    final bound = await HttpGraphDraftService.connect(
        client: client, origin: origin, currentOrigin: origin);
    expect(bound.account.id, scope);
    await bound.authors();
    await bound.list();
    await bound.get(package().id);
    final store = MemoryGraphDraftStore();
    final w = GraphDraftWorkspace(
        account: bound.account,
        service: bound,
        store: store,
        debounce: const Duration(days: 1));
    final editor = await w.create(crowdedCanvasFixture());
    final before = editor.documentJson;
    actualAccount = '22222222-2222-4222-8222-222222222222';
    await editor.retry();
    expect(editor.phase, GraphDraftPhase.signInRequired);
    expect(bound.account.active, isFalse);
    expect((await store.read(scope, editor.id))!.document, before);
    expect(await store.list(actualAccount), isEmpty);
    final writes = requests.where((request) => request.method == 'POST').length;
    await editor.retry();
    expect(
        requests.where((request) => request.method == 'POST').length, writes);
    await expectLater(
        HttpGraphDraftService.connect(
            client: client,
            origin: origin,
            currentOrigin: origin,
            expectedAccountId: scope),
        throwsA(isA<GraphDraftException>()));
    w.dispose();
  });

  test(
      'same-origin endpoints use exact revisions and attribution without assigning ownership',
      () async {
    final requests = <http.Request>[];
    final p = package();
    final api = service(MockClient((r) async {
      requests.add(r);
      return http.Response(jsonEncode(ack(p.id)),
          r.body.contains('expectedRevision":null') ? 201 : 200);
    }));
    await api.save(p, expectedRevision: null, authorId: 'employee-1');
    await api.save(p, expectedRevision: 'b' * 32);
    expect(
        requests
            .every((r) => r.url.origin == origin.origin && !r.followRedirects),
        isTrue);
    final create = jsonDecode(requests.first.body) as Map,
        update = jsonDecode(requests.last.body) as Map;
    expect(create['expectedRevision'], isNull);
    expect(create['authorId'], 'employee-1');
    expect(update['expectedRevision'], 'b' * 32);
    expect(update.containsKey('authorId'), isFalse);
    expect(create.containsKey('ownerId'), isFalse);
    expect(create.containsKey('accountId'), isFalse);
    expect(create['package'], p.toJson());
  });
  test('opaque cursor query values are encoded once and preserved', () async {
    http.Request? request;
    final api = service(MockClient((r) async {
      request = r;
      return http.Response(jsonEncode({'drafts': [], 'nextCursor': null}), 200);
    }));
    await api.list(limit: 300, cursor: 'opaque & cursor/+==');
    expect(request!.url.queryParameters['cursor'], 'opaque & cursor/+==');
    expect(request!.url.queryParameters['limit'], '300');
  });
  test(
      'minimal active directory validates default identity and does not expose extra fields',
      () async {
    final api = service(MockClient((_) async => http.Response(
        jsonEncode({
          'defaultAuthorId': 'employee-1',
          'authors': [
            {
              'id': 'employee-1',
              'name': 'Synthetic creator',
              'phone': 'not retained'
            }
          ]
        }),
        200)));
    final authors = await api.authors();
    expect(authors.defaultAuthorId, 'employee-1');
    expect(authors.authors.single.toJson(),
        {'id': 'employee-1', 'name': 'Synthetic creator'});
  });
  for (final status in [400, 401, 403, 404, 409, 413, 503]) {
    test('API status $status remains explicit without losing caller package',
        () async {
      final p = package(), before = p.toJson();
      final api = service(MockClient(
          (_) async => http.Response('{"error":"Synthetic failure"}', status)));
      await expectLater(
          api.save(p, expectedRevision: null),
          throwsA(isA<GraphDraftException>()
              .having((e) => e.status, 'status', status)));
      expect(p.toJson(), before);
    });
  }
  test('only durable 200/201 responses count as successful saves', () async {
    final p = package(),
        api = service(
            MockClient((_) async => http.Response(jsonEncode(ack(p.id)), 202)));
    await expectLater(api.save(p, expectedRevision: null),
        throwsA(isA<GraphDraftException>()));
  });
  test(
      'wrong or malformed returned identity/revision never becomes an acknowledgment',
      () async {
    final p = package();
    for (final invalid in [
      {'id': 'another-draft', 'revision': 'a' * 32},
      {'id': p.id, 'revision': '*'}
    ]) {
      final api = service(MockClient((_) async =>
          http.Response(jsonEncode({...ack(p.id), ...invalid}), 200)));
      await expectLater(
          api.save(p, expectedRevision: null), throwsFormatException);
    }
  });
  test(
      'cross-origin, reserved IDs, wildcard preconditions and account aliases are rejected before requests',
      () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    expect(
        () => HttpGraphDraftService(
            client: client,
            origin: origin,
            currentOrigin: Uri.parse('https://other.invalid'),
            account: GraphDraftAccount(id: scope, displayName: 'Synthetic')),
        throwsFormatException);
    expect(() => GraphDraftAccount(id: 'employee-1', displayName: 'Synthetic'),
        throwsFormatException);
    final api = service(client);
    await expectLater(api.get('authors'), throwsFormatException);
    await expectLater(
        api.save(package(), expectedRevision: '*'), throwsFormatException);
    expect(requests, 0);
  });
  test(
      '8 MiB full photo plus thumbnail remains exact through HTTP JSON and GET',
      () async {
    final doc = crowdedCanvasFixture().toJson();
    doc['attachments'] = [
      {'id': 'photo', 'blobKey': 'full', 'thumbnailKey': 'thumb'}
    ];
    final full = Uint8List(8 * 1024 * 1024)..fillRange(0, 8 * 1024 * 1024, 17),
        thumbnail = Uint8List.fromList([1, 2, 3]);
    final p = package(
        document: doc,
        blobs: {'full': base64Encode(full), 'thumb': base64Encode(thumbnail)});
    Map? sent;
    final api = service(MockClient((r) async {
      if (r.method == 'POST') {
        sent = jsonDecode(r.body) as Map;
        return http.Response(jsonEncode(ack(p.id)), 201);
      }
      return http.Response(
          jsonEncode({
            'id': p.id,
            'package': p.toJson(),
            'revision': 'a' * 32,
            'author': {'id': 'employee-1', 'name': 'Synthetic creator'}
          }),
          200);
    }));
    await api.save(p, expectedRevision: null);
    final loaded = await api.get(p.id);
    expect(sent!['package'], p.toJson());
    expect(loaded.package.toJson(), p.toJson());
    expect(loaded.package.decodeBlobs()['full'], full);
    expect(loaded.package.decodeBlobs()['thumb'], thumbnail);
  });
  test(
      'conservative complete-request size cap preserves oversize package without sending or trimming',
      () async {
    var count = 0;
    final doc = crowdedCanvasFixture().toJson();
    doc['attachments'] = [
      {'id': 'large', 'blobKey': 'large', 'thumbnailKey': ''}
    ];
    final data = base64Encode(Uint8List(20 * 1024 * 1024));
    final p = package(document: doc, blobs: {'large': data});
    final api = service(MockClient((_) async {
      count++;
      return http.Response('{}', 200);
    }));
    await expectLater(
        api.save(p, expectedRevision: null),
        throwsA(
            isA<GraphDraftException>().having((e) => e.status, 'status', 413)));
    expect(count, 0);
    expect((p.toJson()['blobs'] as Map)['large'], data);
  });
  test('session invalidation during a response rejects its acknowledgment',
      () async {
    final account = GraphDraftAccount(id: scope, displayName: 'Synthetic'),
        p = package();
    final api = service(MockClient((_) async {
      account.invalidate();
      return http.Response(jsonEncode(ack(p.id)), 201);
    }), account: account);
    await expectLater(
        api.save(p, expectedRevision: null),
        throwsA(
            isA<GraphDraftException>().having((e) => e.status, 'status', 401)));
  });
}
