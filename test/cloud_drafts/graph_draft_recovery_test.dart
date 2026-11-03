import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/models/cloud_graph_draft.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_recovery.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_workspace.dart';
import 'graph_draft_sync_test.dart'
    show FixtureDraftService, workspace, ownerA, ownerB, creator, doc, moved;

class FailingStore extends MemoryGraphDraftStore {
  bool fail = true;
  @override
  Future<void> write(GraphDraftRecovery record) async {
    if (fail) throw StateError('Synthetic quota failure');
    await super.write(record);
  }
}

void main() {
  test('Keep Both retains package extensions and full available data',
      () async {
    final store = MemoryGraphDraftStore();
    final scoped = workspace(FixtureDraftService(), store);
    await store.write(GraphDraftRecovery(
        accountId: ownerA,
        document: doc().toJson(),
        packageExtras: {
          'futurePackage': {'version': 2}
        }));
    final original = await scoped.open(doc().id);
    final fork = await scoped.keepBoth(original);
    expect(fork.recovery.package.toJson()['futurePackage'], {'version': 2});
    expect(original.recovery.package.toJson()['futurePackage'], {'version': 2});
    expect(fork.id, isNot(original.id));
    scoped.dispose();
  });
  test('context and authors are reserved API identities', () {
    for (final id in ['context', 'authors']) {
      expect(() => validateDraftId(id), throwsFormatException);
    }
  });

  test('layer trace and calibration extensions survive ordinary model capture',
      () {
    final json = copyGraphJson(doc().toJson());
    ((json['layers'] as Map)['structure'] as Map)['futureLayer'] = {'value': 1};
    ((json['traces'] as List).first as Map)['futureTrace'] = [1, 2];
    (json['measurementCalibration'] as Map)['futureCalibration'] = true;
    final result = GraphDocument.fromJson(json).toJson();
    expect(((result['layers'] as Map)['structure'] as Map)['futureLayer'],
        {'value': 1});
    expect(((result['traces'] as List).first as Map)['futureTrace'], [1, 2]);
    expect(
        (result['measurementCalibration'] as Map)['futureCalibration'], isTrue);
  });

  test(
      'removing an id-less shape does not transfer its future fields to the next shape',
      () {
    final json = doc().toJson();
    final shapes = (json['graphObjects'] as Map)['shapes'] as List;
    (shapes[0] as Map)['futureRemovedShape'] = true;
    (shapes[1] as Map)['futureSurvivorShape'] = true;
    final model = GraphDocument.fromJson(json);
    model.replaceShapes(model.shapes.skip(1));
    final result = (model.toJson()['graphObjects'] as Map)['shapes'] as List;
    expect((result.first as Map)['futureRemovedShape'], isNull);
    expect((result.first as Map)['futureSurvivorShape'], isTrue);
  });

  test(
      'deleting an id-less wall does not move its future fields to a surviving wall',
      () {
    final json = doc().toJson();
    final walls = (json['graphObjects'] as Map)['wallSegments'] as List;
    (walls[0] as Map)['futureWall'] = 'removed';
    (walls[1] as Map)['futureWall'] = 'survivor';
    final model = GraphDocument.fromJson(json);
    model.replaceWallSegments(model.wallSegments.skip(1));
    final result =
        (model.toJson()['graphObjects'] as Map)['wallSegments'] as List;
    expect((result.first as Map)['futureWall'], 'survivor');
    expect(
        result.whereType<Map>().any((wall) => wall['futureWall'] == 'removed'),
        isFalse);
  });

  test(
      'ack persistence failure stays nondurable and retry stores revision without uploading again',
      () async {
    final api = FixtureDraftService()..hold = true;
    final store = FailingStore()..fail = false;
    final w = workspace(api, store);
    final e = await w.create(doc());
    final saving = e.retry();
    await Future<void>.delayed(Duration.zero);
    store.fail = true;
    api.pending.single.complete(
        GraphDraftWriteResult(e.id, 'a' * 32, DateTime.utc(2026), creator));
    await saving;
    expect(e.hasUnpersistedEdits, isTrue);
    expect(e.phase, GraphDraftPhase.localError);
    expect((await store.read(ownerA, e.id))!.revision, isNull);
    store.fail = false;
    await e.retry();
    expect(e.hasUnpersistedEdits, isFalse);
    expect(e.phase, GraphDraftPhase.synced);
    expect((await store.read(ownerA, e.id))!.revision, 'a' * 32);
    expect(api.writes, hasLength(1));
    w.dispose();
  });
  test(
      'model editing retains nested future fields without resurrecting removed attachments',
      () async {
    final w = workspace(FixtureDraftService(), MemoryGraphDraftStore());
    final json = doc().toJson();
    (json['customer'] as Map)['futureCustomer'] = {'version': 2};
    (json['graphObjects'] as Map)['futureGeometry'] = {
      'data': [1, 2]
    };
    (((json['graphObjects'] as Map)['wallSegments'] as List).first
        as Map)['futureWall'] = 'retained';
    json['attachments'] = [
      {
        ...const GraphAttachment(
                id: 'future-photo', name: 'Synthetic', blobKey: 'full')
            .toJson(),
        'futureAttachment': {'data': true}
      },
      {
        ...const GraphAttachment(
                id: 'removed', name: 'Removed', blobKey: 'removed')
            .toJson(),
        'futureAttachment': 42
      }
    ];
    final loaded = GraphDocument.fromJson(json);
    loaded.replaceAttachments([loaded.attachments.first]);
    final e = await w.create(loaded, blobs: {
      'full': Uint8List.fromList([1])
    });
    e.capture(moved(e));
    await e.retry();
    final result = e.recovery.package.document;
    expect((result['customer'] as Map)['futureCustomer'], {'version': 2});
    expect((result['graphObjects'] as Map)['futureGeometry'], {
      'data': [1, 2]
    });
    expect(
        (((result['graphObjects'] as Map)['wallSegments'] as List).first
            as Map)['futureWall'],
        'retained');
    expect((result['attachments'] as List), hasLength(1));
    expect(((result['attachments'] as List).single as Map)['futureAttachment'],
        {'data': true});
    w.dispose();
  });

  test(
      'storage failure retains in-memory work, does not upload or claim locally saved, and can retry',
      () async {
    final api = FixtureDraftService(),
        store = FailingStore(),
        w = workspace(api, store),
        document = doc();
    final e = await w.create(document);
    expect(e.phase, GraphDraftPhase.localError);
    expect(e.hasUnpersistedEdits, isTrue);
    expect(api.writes, isEmpty);
    final latest = moved(e);
    e.capture(latest);
    await e.retry();
    expect(e.documentJson, latest);
    expect(api.writes, isEmpty);
    store.fail = false;
    await e.retry();
    expect((await store.read(ownerA, e.id))!.document, latest);
    expect(e.phase, GraphDraftPhase.synced);
    w.dispose();
  });
  test(
      'closing with a pending debounce flushes its original scoped recovery rather than dropping it',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store);
    final e = await w.create(doc());
    final latest = moved(e);
    e.capture(latest);
    await w.closeGracefully();
    expect((await store.read(ownerA, e.id))!.document, latest);
    expect(api.writes, isEmpty);
    w.dispose();
  });
  test(
      'a conflict retains local and full remote copies, and keep-both creates a new identity without overwriting either',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store);
    final document = doc();
    final remote = GraphDraftPackage.fromJson({
      'type': 'bugman-graph',
      'version': 1,
      'document': document.toJson(),
      'blobs': {}
    });
    api.remote = RemoteGraphDraft(remote, 'a' * 32, creator);
    api.failCode = 409;
    final e = await w.create(document);
    e.capture(moved(e));
    await e.retry();
    final local = e.documentJson;
    expect(e.recovery.conflict!.package.toJson(), remote.toJson());
    expect(e.documentJson, local);
    final fork = await w.keepBoth(e);
    expect(fork.id, isNot(e.id));
    expect(fork.recovery.revision, isNull);
    final copied = fork.documentJson..['id'] = e.id;
    expect(copied, local);
    expect((await store.read(ownerA, e.id))!.document, local);
    expect(e.recovery.conflict!.package.toJson(), remote.toJson());
    w.dispose();
  });
  test('manual portal key survives reload without clearing pending cloud edits',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store);
    final e = await w.create(doc());
    await e.updatePortalKey('synthetic/customer-folder/graph.bgraph');
    expect(e.hasQueuedEdits, isTrue);
    expect(api.writes, isEmpty);
    w.dispose();
    final next = workspace(api, store);
    final reopened = await next.open(e.id);
    expect(reopened.portalKey, 'synthetic/customer-folder/graph.bgraph');
    expect(reopened.hasQueuedEdits, isTrue);
    next.dispose();
  });
  test(
      'employee attribution reuse never adopts recovery from a recreated account',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        a = workspace(api, store);
    await a.refreshAuthors();
    final e = await a.create(doc(), author: creator);
    a.dispose();
    final recreated = workspace(api, store, scope: ownerB);
    await recreated.refreshAuthors();
    expect(recreated.directory!.defaultAuthorId, creator.id);
    expect(await recreated.localGraphs(), isEmpty);
    expect(await store.read(ownerB, e.id), isNull);
    expect(await store.read(ownerA, e.id), isNotNull);
    recreated.dispose();
  });
  test(
      'explicit import preserves original legacy geometry and full photo bytes under a new identity',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store),
        legacy = doc();
    final original = legacy.toJson();
    final e = await w.importCopy(legacy,
        loadBlob: (_) async => Uint8List.fromList([1, 2, 3]));
    final imported = e.documentJson..['id'] = legacy.id;
    expect(imported, original);
    expect(legacy.toJson(), original);
    expect(e.id, isNot(legacy.id));
    w.dispose();
  });
  test(
      'cursor cycles fail explicitly instead of returning a silently truncated gallery',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store);
    api.pages[null] = const GraphDraftPage([], 'loop');
    api.pages['loop'] = const GraphDraftPage([], 'loop');
    await expectLater(w.remoteGraphs(), throwsFormatException);
    w.dispose();
  });
  test(
      'full-photo deletion is explicit, unknown blobs survive edits, and in-session undo still has original bytes',
      () async {
    final api = FixtureDraftService(),
        store = MemoryGraphDraftStore(),
        w = workspace(api, store),
        document = doc();
    final json = document.toJson();
    json['attachments'] = [
      {
        'id': 'photo',
        'name': 'synthetic',
        'blobKey': 'full',
        'thumbnailKey': 'thumb'
      }
    ];
    final full = Uint8List.fromList([1, 2, 3]),
        thumbnail = Uint8List.fromList([4, 5, 6]);
    final e = await w.create(GraphDocument.fromJson(json), blobs: {
      'full': full,
      'thumb': thumbnail,
      'unknown': Uint8List.fromList([7, 8, 9])
    });
    final deleted = e.documentJson;
    deleted['attachments'] = [];
    e.capture(deleted, deletedBlobKeys: {'full', 'thumb'});
    await e.flushLocal();
    expect(e.recovery.blobs.containsKey('full'), isFalse);
    expect(e.recovery.blobs.containsKey('thumb'), isFalse);
    expect(e.recovery.blobs['unknown'], base64Encode([7, 8, 9]));
    expect(await e.loadBlob('full'), full);
    e.capture(json);
    await e.flushLocal();
    expect(e.recovery.blobs['full'], base64Encode(full));
    expect(e.recovery.blobs['thumb'], base64Encode(thumbnail));
    w.dispose();
  });
}
