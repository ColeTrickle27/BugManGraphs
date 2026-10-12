import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store_indexed.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_recovery.dart';
import 'graph_draft_sync_test.dart' show ownerA, ownerB, doc;

void main() {
  test(
      'IndexedDB cursor reads every recovery summary immediately and scopes accounts',
      () async {
    final store = IndexedDbGraphDraftStore(newIdbFactoryMemory());
    for (final id in ['one', 'two', 'three']) {
      final json = doc().toJson()..['id'] = id;
      await store.write(GraphDraftRecovery(accountId: ownerA, document: json));
    }
    await store.write(GraphDraftRecovery(
        accountId: ownerB, document: doc().toJson()..['id'] = 'other-owner'));
    expect((await store.list(ownerA)).map((row) => row.id),
        ['one', 'three', 'two']);
    expect((await store.list(ownerB)).map((row) => row.id), ['other-owner']);
    expect((await store.read(ownerA, 'two'))!.document['id'], 'two');
    expect(await store.read(ownerA, 'other-owner'), isNull);
    expect((await store.list(ownerA)), hasLength(3));
  });
}
