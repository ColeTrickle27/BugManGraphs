import 'dart:typed_data';
import '../../models/graph_document.dart';
import '../graph_repository.dart';
import 'graph_draft_workspace.dart';

/// Canvas local saves and photo reads remain scoped to this explicit editor
/// session. They never read/write the legacy unscoped graph repository.
class GraphDraftEditorRepository implements GraphRepository {
  GraphDraftEditorRepository(this.session);
  GraphDraftEditorSession session;
  Future<GraphDraftEditorSession> ensureSession(GraphDocument document,
      {Map<String, Uint8List> blobs = const {}}) async {
    if (session.id == document.id) return session;
    final old = session;
    session = await old.workspace.create(document,
        blobs: {...await old.allAvailableBlobs(), ...blobs},
        author: old.workspace.directory?.authors
            .where((a) => a.id == old.workspace.directory!.defaultAuthorId)
            .firstOrNull);
    return session;
  }

  @override
  Future<Uint8List?> loadBlob(String key) => session.loadBlob(key);
  @override
  Future<GraphDocument?> loadGraph(String id) async =>
      id == session.id ? GraphDocument.fromJson(session.documentJson) : null;
  @override
  Future<List<SavedGraphSummary>> listGraphs() async =>
      [summaryForDocument(GraphDocument.fromJson(session.documentJson))];
  @override
  Future<void> saveGraph(GraphDocument document,
      {Map<String, Uint8List> blobs = const {},
      Set<String> deletedBlobKeys = const {}}) async {
    await ensureSession(document, blobs: blobs);
    session.capture(document.toJson(),
        pendingBlobs: blobs, deletedBlobKeys: deletedBlobKeys);
    await session.flushLocal();
    if (session.hasUnpersistedEdits) {
      throw StateError('Recovery could not be saved on this device.');
    }
  }

  @override
  Future<void> deleteGraph(String id) async =>
      throw UnsupportedError('The account draft API has no delete operation.');
}
