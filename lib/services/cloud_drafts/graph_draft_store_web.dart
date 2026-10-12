import 'dart:convert';
import 'package:idb_shim/idb_browser.dart';
import 'graph_draft_recovery.dart';
import 'graph_draft_store.dart';

GraphDraftStore createDraftStore() => IndexedDbGraphDraftStore();

/// A separate account-scoped cache; no legacy documents or photo-blobs store
/// is opened or adopted. Full recovery data and its small summary commit together.
class IndexedDbGraphDraftStore implements GraphDraftStore {
  static const databaseName = 'bugman-account-graph-drafts';
  static const _records = 'recovery', _summaries = 'summaries';
  Database? _database;
  Future<Database> get _db async => _database ??= await idbFactoryBrowser
          .open(databaseName, version: 1, onUpgradeNeeded: (e) {
        e.database.createObjectStore(_records);
        e.database.createObjectStore(_summaries);
      });
  String _key(String scope, String id) => '$scope/$id';
  @override
  Future<GraphDraftRecovery?> read(String accountId, String id) async {
    final db = await _db, t = db.transaction(_records, idbModeReadOnly);
    final raw = await t.objectStore(_records).getObject(_key(accountId, id));
    await t.completed;
    if (raw == null) return null;
    final record = GraphDraftRecovery.fromJson(
        (jsonDecode(raw as String) as Map).cast<String, Object?>());
    if (record.accountId != accountId || record.id != id) {
      throw const FormatException('Recovery ownership did not match');
    }
    return record;
  }

  @override
  Future<void> write(GraphDraftRecovery record) async {
    final db = await _db,
        t = db.transaction([_records, _summaries], idbModeReadWrite),
        key = _key(record.accountId, record.id);
    await t.objectStore(_records).put(jsonEncode(record.toJson()), key);
    await t.objectStore(_summaries).put(
        jsonEncode(LocalGraphDraftSummary.forRecovery(record).toJson()), key);
    await t.completed;
  }

  @override
  Future<List<LocalGraphDraftSummary>> list(String accountId) async {
    final db = await _db,
        t = db.transaction(_summaries, idbModeReadOnly),
        result = <LocalGraphDraftSummary>[];
    final range = KeyRange.bound('$accountId/', '$accountId/\uffff');
    final cursor = await t
        .objectStore(_summaries)
        .openCursor(range: range, autoAdvance: true)
        .toList();
    for (final row in cursor) {
      final raw = row.value;
      if (raw is String) {
        result.add(LocalGraphDraftSummary.fromJson(
            (jsonDecode(raw) as Map).cast<String, Object?>()));
      }
    }
    await t.completed;
    return result;
  }
}
