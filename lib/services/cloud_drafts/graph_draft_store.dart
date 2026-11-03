import '../../models/cloud_graph_draft.dart';
import 'graph_draft_recovery.dart';

abstract class GraphDraftStore {
  Future<GraphDraftRecovery?> read(String accountId, String id);
  Future<void> write(GraphDraftRecovery record);
  Future<List<LocalGraphDraftSummary>> list(String accountId);
}

class MemoryGraphDraftStore implements GraphDraftStore {
  final _records = <String, Map<String, Object?>>{};
  String _key(String accountId, String id) => '$accountId/$id';
  @override
  Future<GraphDraftRecovery?> read(String accountId, String id) async {
    final json = _records[_key(accountId, id)];
    if (json == null) return null;
    final record = GraphDraftRecovery.fromJson(copyGraphJson(json));
    if (record.accountId != accountId || record.id != id) {
      throw const FormatException('Recovery ownership did not match');
    }
    return record;
  }

  @override
  Future<void> write(GraphDraftRecovery record) async {
    _records[_key(record.accountId, record.id)] =
        copyGraphJson(record.toJson());
  }

  @override
  Future<List<LocalGraphDraftSummary>> list(String accountId) async => [
        for (final entry in _records.entries)
          if (entry.key.startsWith('$accountId/'))
            LocalGraphDraftSummary.forRecovery(
                GraphDraftRecovery.fromJson(copyGraphJson(entry.value)))
      ];
}
