import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/models/cloud_graph_draft.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_recovery.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_service.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_workspace.dart';
import '../support/crowded_canvas_fixture.dart';

const ownerA = '11111111-1111-4111-8111-111111111111',
    ownerB = '22222222-2222-4222-8222-222222222222';
const creator = GraphDraftAuthor('employee-1', 'Synthetic creator');
const otherCreator = GraphDraftAuthor('employee-2', 'Other synthetic creator');

class FixtureDraftService implements GraphDraftService {
  final writes = <Map<String, Object?>>[];
  final pending = <Completer<GraphDraftWriteResult>>[];
  bool hold = false;
  int? failCode;
  RemoteGraphDraft? remote;
  int counter = 0, listCalls = 0;
  final pages = <String?, GraphDraftPage>{null: const GraphDraftPage([], null)};
  @override
  Future<GraphDraftAuthors> authors() async =>
      const GraphDraftAuthors('employee-1', [creator, otherCreator]);
  @override
  Future<GraphDraftPage> list({int limit = 100, String? cursor}) async {
    listCalls++;
    return pages[cursor]!;
  }

  @override
  Future<RemoteGraphDraft> get(String id) async {
    if (remote == null) throw const GraphDraftException(404, 'Not found');
    return remote!;
  }

  @override
  Future<GraphDraftWriteResult> save(GraphDraftPackage package,
      {required String? expectedRevision, String? authorId}) async {
    writes.add({
      'package': package.toJson(),
      'expectedRevision': expectedRevision,
      'authorId': authorId
    });
    if (failCode != null) {
      throw GraphDraftException(failCode!, 'Synthetic cloud failure');
    }
    final result = GraphDraftWriteResult(
        package.id,
        (++counter).toRadixString(16).padLeft(32, '0'),
        DateTime.utc(2026, 10, 12),
        authorId == otherCreator.id ? otherCreator : creator);
    if (hold) {
      final c = Completer<GraphDraftWriteResult>();
      pending.add(c);
      return c.future;
    }
    return result;
  }
}

GraphDraftWorkspace workspace(
        FixtureDraftService api, MemoryGraphDraftStore store,
        {String scope = ownerA}) =>
    GraphDraftWorkspace(
        account: GraphDraftAccount(id: scope, displayName: 'Synthetic account'),
        service: api,
        store: store,
        debounce: const Duration(days: 1));
GraphDocument doc() => crowdedCanvasFixture();
Map<String, Object?> moved(GraphDraftEditorSession session) {
  final json = session.documentJson;
  final objects = json['graphObjects'] as Map;
  final segments = objects['wallSegments'] as List;
  ((segments.first as Map)['start'] as Map)['x'] = 1234.0;
  return json;
}

Future<void> tick() async => Future<void>.delayed(Duration.zero);
void main() {
  test('full-photo-only package survives model editing, persistence and upload',
      () async {
    final w = workspace(FixtureDraftService(), MemoryGraphDraftStore());
    final json = doc().toJson();
    json['attachments'] = [
      const GraphAttachment(
              id: 'photo-only',
              name: 'Synthetic',
              blobKey: 'photo-only',
              thumbnailKey: '')
          .toJson()
    ];
    final model = GraphDocument.fromJson(json);
    expect(model.attachments.single.thumbnailKey, isEmpty);
    final session = await w.create(model, blobs: {
      'photo-only': Uint8List.fromList([1, 2, 3])
    });
    session.capture(GraphDocument.fromJson(session.documentJson).toJson());
    await session.retry();
    expect(session.phase, GraphDraftPhase.synced);
    expect(session.recovery.package.toJson()['blobs'], {
      'photo-only': base64Encode([1, 2, 3])
    });
    w.dispose();
  });

  test('clean cached reopen revalidates remote but dirty recovery wins',
      () async {
    final api = FixtureDraftService(), store = MemoryGraphDraftStore();
    final w = workspace(api, store), d = doc();
    final first = await w.create(d);
    await first.retry();
    final remoteJson = moved(first);
    api.remote = RemoteGraphDraft(
        GraphDraftPackage.fromJson({
          'type': 'bugman-graph',
          'version': 1,
          'document': remoteJson,
          'blobs': <String, String>{}
        }),
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        otherCreator);
    final reopened = await w.open(d.id);
    expect(reopened.documentJson, remoteJson);
    expect(reopened.recovery.revision, api.remote!.revision);
    final localJson = reopened.documentJson..['title'] = 'Pending local';
    reopened.capture(localJson);
    expect(await w.open(d.id), same(reopened));
    expect(reopened.documentJson, localJson);
    await reopened.flushLocal();
    w.dispose();
  });

  test('new unadopted graph persists locally and creates using null revision',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store),
        d = doc();
    final before = d.toJson();
    final editor = await w.create(d);
    expect(editor.hasQueuedEdits, isTrue);
    expect(editor.phase, GraphDraftPhase.savedLocally);
    expect((await store.read(ownerA, d.id))!.document, before);
    await editor.retry();
    expect(api.writes.single['expectedRevision'], isNull);
    expect(editor.phase, GraphDraftPhase.synced);
    expect(d.toJson(), before);
    expect(accountGraphDraftsActivated, isFalse);
    w.dispose();
  });
  test(
      'stale acknowledgment cannot clear newer persisted edits and next write uses new revision',
      () async {
    final api = FixtureDraftService()..hold = true,
        store = MemoryGraphDraftStore(),
        w = workspace(api, store);
    final editor = await w.create(doc());
    final first = editor.retry();
    await tick();
    final newer = moved(editor);
    editor.capture(newer);
    await editor.flushLocal();
    expect(editor.recovery.generation, 2);
    api.pending.first.complete(GraphDraftWriteResult(
        editor.id, 'a' * 32, DateTime.utc(2026), creator));
    await tick();
    await tick();
    expect(api.writes, hasLength(2));
    expect(api.writes.last['expectedRevision'], 'a' * 32);
    expect(editor.recovery.document, newer);
    expect(editor.recovery.acknowledgedGeneration, 1);
    expect(editor.hasQueuedEdits, isTrue);
    api.pending.last.complete(GraphDraftWriteResult(
        editor.id, 'b' * 32, DateTime.utc(2026), creator));
    await first;
    expect(editor.phase, GraphDraftPhase.synced);
    expect((await store.read(ownerA, editor.id))!.document, newer);
    w.dispose();
  });
  for (final code in [0, 400, 401, 403, 404, 409, 413, 503]) {
    test('failure $code retains complete recovery and does not claim synced',
        () async {
      final api = FixtureDraftService()..failCode = code,
          store = MemoryGraphDraftStore(),
          w = workspace(api, store),
          d = doc();
      final before = d.toJson();
      final e = await w.create(d);
      await e.retry();
      final saved = await store.read(ownerA, d.id);
      expect(saved!.document, before);
      expect(saved.dirty, isTrue);
      expect(e.phase, isNot(GraphDraftPhase.synced));
      w.dispose();
    });
  }
  test(
      'offline reload resumes same scoped recovery without adopting legacy or other accounts',
      () async {
    final api = FixtureDraftService()..failCode = 0,
        store = MemoryGraphDraftStore(),
        w = workspace(api, store),
        d = doc();
    final e = await w.create(d);
    e.capture(moved(e));
    await e.retry();
    final recovery = e.documentJson;
    w.dispose();
    final next = workspace(api, store);
    api.failCode = null;
    final resumed = await next.open(d.id);
    expect(resumed.documentJson, recovery);
    await resumed.retry();
    expect(resumed.phase, GraphDraftPhase.synced);
    final other = workspace(api, store, scope: ownerB);
    expect(await other.localGraphs(), isEmpty);
    expect((await store.read(ownerA, d.id))!.document, recovery);
    next.dispose();
    other.dispose();
  });
  test(
      'complete photo and thumbnail bytes survive capture, store and sync without geometry changes',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store),
        d = doc();
    d.replaceAttachments([
      const GraphAttachment(
          id: 'photo-1',
          name: 'synthetic.jpg',
          blobKey: 'full-photo',
          thumbnailKey: 'small-photo')
    ]);
    final full = Uint8List.fromList(List.generate(4096, (n) => n % 256)),
        thumb = Uint8List.fromList([1, 2, 3]);
    final original = Uint8List.fromList(full);
    final e =
        await w.create(d, blobs: {'full-photo': full, 'small-photo': thumb});
    full[0] = 99;
    await e.retry();
    final raw = api.writes.single['package'] as Map;
    expect(
        base64Decode((raw['blobs'] as Map)['full-photo'] as String), original);
    expect(base64Decode((raw['blobs'] as Map)['small-photo'] as String), thumb);
    expect(raw['document'], d.toJson());
    w.dispose();
  });
  test(
      'missing full photo never uploads a thumbnail substitute; recovery stays available',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store),
        d = doc();
    d.replaceAttachments([
      const GraphAttachment(
          id: 'photo-1',
          name: 'synthetic.jpg',
          blobKey: 'full',
          thumbnailKey: 'thumb')
    ]);
    final e = await w.create(d, blobs: {
      'thumb': Uint8List.fromList([1, 2, 3])
    });
    await e.retry();
    expect(api.writes, isEmpty);
    expect(e.phase, GraphDraftPhase.needsPhoto);
    expect((await store.read(ownerA, d.id))!.document, d.toJson());
    e.capture(d.toJson(), pendingBlobs: {
      'full': Uint8List.fromList([4, 5, 6])
    });
    await e.retry();
    expect(e.phase, GraphDraftPhase.synced);
    expect((api.writes.single['package'] as Map)['blobs'],
        containsPair('full', base64Encode([4, 5, 6])));
    w.dispose();
  });
  test(
      'author selection changes attribution without changing immutable owner and old author ack cannot clear a newer choice',
      () async {
    final api = FixtureDraftService()..hold = true,
        store = MemoryGraphDraftStore(),
        w = workspace(api, store);
    await w.refreshAuthors();
    final e = await w.create(doc(), author: creator);
    final sending = e.retry();
    await tick();
    e.selectAuthor(otherCreator);
    await e.flushLocal();
    api.pending.first.complete(
        GraphDraftWriteResult(e.id, 'a' * 32, DateTime.utc(2026), creator));
    await tick();
    await tick();
    expect(e.recovery.accountId, ownerA);
    expect(api.writes.last['authorId'], otherCreator.id);
    expect(e.recovery.pendingAuthor!.id, otherCreator.id);
    api.pending.last.complete(GraphDraftWriteResult(
        e.id, 'b' * 32, DateTime.utc(2026), otherCreator));
    await sending;
    expect(e.recovery.author!.id, otherCreator.id);
    w.dispose();
  });
  test(
      'inactive historical author is retained by omitting authorId on ordinary edits',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store),
        d = doc();
    await store.write(GraphDraftRecovery(
        accountId: ownerA,
        document: d.toJson(),
        generation: 1,
        acknowledgedGeneration: 1,
        revision: 'a' * 32,
        author: const GraphDraftAuthor(
            'inactive-user', 'Historical synthetic name')));
    final e = await w.open(d.id);
    e.capture(moved(e));
    await e.retry();
    expect(api.writes.single['authorId'], isNull);
    expect(api.writes.single['expectedRevision'], 'a' * 32);
    w.dispose();
  });
  test(
      'all cursor pages including more than 300 graphs are traversed; key order does not masquerade as recency',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store);
    GraphDraftSummary summary(int n) => GraphDraftSummary(
        id: 'draft-$n',
        revision: 'a' * 32,
        title: 'Synthetic $n',
        updatedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: n)),
        author: creator);
    api.pages[null] =
        GraphDraftPage(List.generate(300, summary), 'opaque & cursor');
    api.pages['opaque & cursor'] =
        GraphDraftPage(List.generate(5, (n) => summary(n + 300)), null);
    final list = await w.remoteGraphs();
    expect(list, hasLength(305));
    expect(list.first.id, 'draft-304');
    expect(api.listCalls, 2);
    w.dispose();
  });
  test(
      'session invalidation pauses queued writes while retaining the original owner recovery',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store);
    final e = await w.create(doc());
    w.account.invalidate();
    await e.retry();
    expect(api.writes, isEmpty);
    expect(e.phase, GraphDraftPhase.signInRequired);
    expect((await store.read(ownerA, e.id))!.dirty, isTrue);
    w.dispose();
  });
}
