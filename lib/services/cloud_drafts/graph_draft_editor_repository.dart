import 'package:flutter/foundation.dart';
import '../../models/graph_document.dart';
import '../graph_repository.dart';
import 'graph_draft_workspace.dart';

/// Canvas local saves and photo reads remain scoped to this explicit editor
/// session. They never read/write the legacy unscoped graph repository.
class GraphDraftEditorRepository extends ChangeNotifier
    implements GraphRepository {
  GraphDraftEditorRepository(this._session);
  GraphDraftEditorSession _session;
  GraphDraftEditorSession get session => _session;
  set session(GraphDraftEditorSession value) {
    _session = value;
    notifyListeners();
  }

  Future<GraphDraftEditorSession>? _transition;
  Future<void> flushCurrent() async {
    while (_transition != null) {
      await _transition;
    }
    await session.flushLocal();
  }

  Future<GraphDraftEditorSession> ensureSession(GraphDocument document,
      {Map<String, Uint8List> blobs = const {}}) {
    if (session.id == document.id) return Future.value(session);
    final pending = _transition;
    if (pending != null) {
      return pending.then((_) => ensureSession(document, blobs: blobs));
    }
    final transition = _createSession(document, blobs);
    _transition = transition;
    return transition.whenComplete(() {
      if (identical(_transition, transition)) _transition = null;
    });
  }

  Future<GraphDraftEditorSession> _createSession(
      GraphDocument document, Map<String, Uint8List> blobs) async {
    final old = session;
    session = await old.workspace.create(document,
        packageExtras: old.recovery.packageExtras,
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
