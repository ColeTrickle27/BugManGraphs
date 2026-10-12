import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/cloud_graph_draft.dart';
import '../../models/graph_document.dart';
import 'graph_draft_service.dart';
import 'graph_draft_store.dart';
import 'graph_draft_recovery.dart';

enum GraphDraftPhase {
  savedLocally,
  savingLocally,
  syncing,
  synced,
  offline,
  signInRequired,
  unavailable,
  conflict,
  tooLarge,
  invalidData,
  needsPhoto,
  localError
}

/// Production activation is deliberately off. The verified host/account binding
/// and same-origin session routing must be reviewed before changing this flag.
const accountGraphDraftsActivated = false;

class GraphDraftWorkspace extends ChangeNotifier {
  GraphDraftWorkspace(
      {required this.account,
      required this.service,
      required this.store,
      this.debounce = const Duration(milliseconds: 700)}) {
    account.addListener(_accountChanged);
  }
  void _accountChanged() {
    directory = null;
    notifyListeners();
  }

  void _requireAccess() {
    if (!account.active || _closed) {
      throw const GraphDraftException(401,
          'Sign in to the original account to access its recovery copies.');
    }
  }

  final GraphDraftAccount account;
  final GraphDraftService service;
  final GraphDraftStore store;
  final Duration debounce;
  GraphDraftAuthors? directory;
  final _sessions = <String, GraphDraftEditorSession>{};
  final _creating = <String, Future<GraphDraftEditorSession>>{};
  bool _closed = false;
  Future<void> refreshAuthors() async {
    if (!account.active || _closed) {
      throw const GraphDraftException(
          401, 'Sign in to choose an active creator.');
    }
    final result = await service.authors();
    if (!account.active || _closed) return;
    directory = result;
    notifyListeners();
  }

  Future<List<GraphDraftSummary>> remoteGraphs() async {
    if (!account.active) {
      throw const GraphDraftException(
          401, 'Sign in to view your cloud graphs.');
    }
    final result = <String, GraphDraftSummary>{}, cursors = <String>{};
    String? cursor;
    do {
      final page = await service.list(cursor: cursor);
      if (!account.active || _closed) {
        throw const GraphDraftException(401, 'The signed-in account changed.');
      }
      for (final draft in page.drafts) {
        result[draft.id] = draft;
      }
      cursor = page.nextCursor;
      if (cursor != null && (cursor.isEmpty || !cursors.add(cursor))) {
        throw const FormatException(
            'The graph list could not finish. Retry to refresh it.');
      }
    } while (cursor != null);
    return result.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<List<LocalGraphDraftSummary>> localGraphs() {
    _requireAccess();
    return store.list(account.id).then((rows) {
      _requireAccess();
      return rows;
    });
  }

  Future<GraphDraftEditorSession> open(String id) async {
    _requireAccess();
    final cached = _sessions[id];
    if (cached != null && cached.hasQueuedEdits) return cached;
    // Flush local-only metadata before replacing a clean cached editor.
    if (cached != null) await cached.flushLocal();
    _requireAccess();
    if (cached != null && cached.hasQueuedEdits) return cached;
    var record = await store.read(account.id, id);
    _requireAccess();
    // Pending recovery always wins over a remote refresh. Neither side is lost.
    if ((record == null || !record.dirty) && account.active && !_closed) {
      try {
        final remote = await service.get(id);
        _requireAccess();
        // An edit made while revalidation was in flight must win.
        if (cached != null && cached.hasQueuedEdits) return cached;
        if (!account.active || _closed) {
          throw const GraphDraftException(
              401, 'The signed-in account changed.');
        }
        final extras = remote.package.toJson()
          ..removeWhere((key, _) =>
              const {'type', 'version', 'document', 'blobs'}.contains(key));
        record = GraphDraftRecovery(
            accountId: account.id,
            document: remote.package.document,
            blobs: (remote.package.toJson()['blobs'] as Map)
                .cast<String, String>(),
            packageExtras: extras,
            generation: record?.generation ?? 1,
            acknowledgedGeneration: record?.generation ?? 1,
            revision: remote.revision,
            author: remote.author,
            portalKey: record?.portalKey);
        await store.write(record);
      } catch (_) {
        if (record == null) rethrow;
      }
    }
    _requireAccess();
    if (record == null) {
      throw const GraphDraftException(
          401, 'Sign in to open this account graph.');
    }
    final session = GraphDraftEditorSession._(this, record);
    _sessions[id] = session;
    return session;
  }

  /// Called only for an explicit new graph/import/fork action, never while
  /// enumerating legacy IndexedDB documents or after signing into a new account.
  Future<GraphDraftEditorSession> create(GraphDocument document,
      {Map<String, Uint8List> blobs = const {},
      Map<String, Object?> packageExtras = const {},
      GraphDraftAuthor? author}) {
    final pending = _creating[document.id];
    if (pending != null) return pending;
    final future = _create(document,
        blobs: blobs, packageExtras: packageExtras, author: author);
    _creating[document.id] = future;
    return future.whenComplete(() => _creating.remove(document.id));
  }

  Future<GraphDraftEditorSession> _create(GraphDocument document,
      {Map<String, Uint8List> blobs = const {},
      Map<String, Object?> packageExtras = const {},
      GraphDraftAuthor? author}) async {
    _requireAccess();
    validateDraftId(document.id);
    if (_sessions.containsKey(document.id) ||
        await store.read(account.id, document.id) != null) {
      throw StateError('This local draft already exists. Open it instead.');
    }
    final record = GraphDraftRecovery(
        accountId: account.id,
        document: document.toJson(),
        packageExtras: packageExtras,
        generation: 0);
    final session = GraphDraftEditorSession._(this, record);
    _sessions[document.id] = session;
    if (author != null) session.selectAuthor(author);
    session.capture(document.toJson(), pendingBlobs: blobs);
    await session.flushLocal();
    return session;
  }

  Future<GraphDraftEditorSession> importCopy(GraphDocument legacy,
      {required Future<Uint8List?> Function(String) loadBlob}) async {
    final json = legacy.toJson();
    json['id'] = newGraphId();
    final copy = GraphDocument.fromJson(json);
    final blobs = <String, Uint8List>{};
    for (final attachment in copy.attachments) {
      for (final key in [
        attachment.blobKey,
        if (attachment.thumbnailKey.isNotEmpty) attachment.thumbnailKey
      ]) {
        final bytes = await loadBlob(key);
        if (bytes != null) blobs[key] = bytes;
      }
    }
    return create(copy,
        blobs: blobs,
        author: directory?.authors
            .where((a) => a.id == directory!.defaultAuthorId)
            .firstOrNull);
  }

  Future<void> retryQueued() async {
    for (final summary in await localGraphs()) {
      if (!summary.dirty && _sessions[summary.id]?.hasQueuedEdits != true) {
        continue;
      }
      final session = await open(summary.id);
      await session.retry();
    }
  }

  Future<GraphDraftEditorSession> keepBoth(
      GraphDraftEditorSession original) async {
    await original.flushLocal();
    final json = original.documentJson;
    json['id'] = newGraphId();
    final copy = GraphDocument.fromJson(json);
    final blobs = await original.allAvailableBlobs();
    final fork = await create(copy,
        blobs: blobs,
        packageExtras: original.recovery.packageExtras,
        author: directory?.authors
            .where((a) => a.id == directory!.defaultAuthorId)
            .firstOrNull);
    // Original pending recovery + current remote conflict remain intact.
    return fork;
  }

  Future<void> closeGracefully() async {
    account.invalidate();
    for (final session in _sessions.values) {
      await session.flushLocal();
      if (session.hasUnpersistedEdits) {
        throw StateError(
            'The latest recovery could not be saved. Keep the graph open.');
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    account.removeListener(_accountChanged);
    account.invalidate();
    for (final session in _sessions.values) {
      session.close();
    }
    super.dispose();
  }
}

class _DraftCapture {
  const _DraftCapture(this.document, this.token, this.portalKey);
  final Map<String, Object?> document;
  final int token;
  final String? portalKey;
}

class GraphDraftEditorSession extends ChangeNotifier {
  GraphDraftEditorSession._(this.workspace, this._record) {
    _persistedGeneration = _record.generation;
    _authorIntent = _record.authorIntent;
    _desiredAuthor = _record.pendingAuthor;
    phase =
        _record.dirty ? GraphDraftPhase.savedLocally : GraphDraftPhase.synced;
  }
  final GraphDraftWorkspace workspace;
  GraphDraftRecovery _record;
  Timer? _timer;
  _DraftCapture? _pending;
  int _captureToken = 0, _persistedGeneration = 0, _authorIntent = 0;
  GraphDraftAuthor? _desiredAuthor;
  final _blobCache = <String, Uint8List>{};
  final _suppliedReferences = <String, Uint8List>{};
  final _deletedBlobKeys = <String>{};
  Future<void> _localTail = Future.value();
  bool _sending = false, _closed = false;
  bool _metadataDirty = false;
  GraphDraftPhase phase = GraphDraftPhase.savedLocally;
  String? reason;
  GraphDraftRecovery get recovery =>
      GraphDraftRecovery.fromJson(copyGraphJson(_record.toJson()));
  Map<String, Object?> get documentJson =>
      copyGraphJson(_pending?.document ?? _record.document);
  String get id => _record.id;
  bool get hasUnpersistedEdits =>
      _pending != null ||
      _persistedGeneration < _record.generation ||
      _metadataDirty;
  bool get hasQueuedEdits =>
      _record.dirty || _pending != null || _metadataDirty;
  GraphDraftAuthor? get displayedAuthor => _desiredAuthor ?? _record.author;
  String? get portalKey => _pending?.portalKey ?? _record.portalKey;
  String get statusText => switch (phase) {
        GraphDraftPhase.savingLocally => 'Saving on this device…',
        GraphDraftPhase.savedLocally =>
          'Saved on this device · waiting to sync',
        GraphDraftPhase.syncing => 'Saved on this device · syncing…',
        GraphDraftPhase.synced => 'Synced to your account',
        GraphDraftPhase.offline =>
          'Saved on this device · retry when connected',
        GraphDraftPhase.signInRequired =>
          'Saved on this device · sign in to resume sync',
        GraphDraftPhase.unavailable =>
          'Saved on this device · cloud sync unavailable',
        GraphDraftPhase.conflict => 'Saved on this device · cloud copy differs',
        GraphDraftPhase.tooLarge =>
          'Saved on this device · too large for cloud sync',
        GraphDraftPhase.invalidData =>
          'Saved on this device · sync needs review',
        GraphDraftPhase.needsPhoto =>
          'Drawing saved on this device · photo data needs recovery',
        GraphDraftPhase.localError =>
          'Recovery could not be saved. Keep this graph open.',
      };
  void _changed() {
    if (!_closed) notifyListeners();
  }

  void selectAuthor(GraphDraftAuthor author) {
    final canonical = workspace.directory?.authors
        .where((a) => a.id == author.id)
        .firstOrNull;
    if (canonical == null) {
      throw const GraphDraftException(
          400, 'Choose a currently active creator.');
    }
    _desiredAuthor = canonical;
    _authorIntent++;
    capture(documentJson);
  }

  void capture(Map<String, Object?> document,
      {Map<String, Uint8List> pendingBlobs = const {},
      Set<String> deletedBlobKeys = const {},
      String? portalKey}) {
    if (_closed) return;
    if (document['id'] != id) {
      throw const FormatException(
          'Open the new graph as its own account draft.');
    }
    for (final entry in pendingBlobs.entries) {
      // Source photo buffers are immutable in the editor. Copy a new buffer
      // once, rather than copying megabytes on every vertex-drag notification.
      if (!identical(_suppliedReferences[entry.key], entry.value)) {
        _blobCache[entry.key] = Uint8List.fromList(entry.value);
        _suppliedReferences[entry.key] = entry.value;
      }
    }
    _deletedBlobKeys.addAll(deletedBlobKeys);
    _pending = _DraftCapture(
        copyGraphJson(document), ++_captureToken, portalKey ?? this.portalKey);
    phase = GraphDraftPhase.savingLocally;
    reason = null;
    _changed();
    _timer?.cancel();
    _timer = Timer(workspace.debounce, () {
      unawaited(flushLocal().then((_) => _sync()));
    });
  }

  Future<Uint8List?> loadBlob(String key) async {
    var bytes = _blobCache[key];
    final encoded = _record.blobs[key];
    if (bytes == null && encoded != null) {
      _blobCache[key] = bytes = base64Decode(encoded);
    }
    return bytes?.asUnmodifiableView();
  }

  Future<Map<String, Uint8List>> allAvailableBlobs() async {
    final result = <String, Uint8List>{};
    for (final key in {..._record.blobs.keys, ..._blobCache.keys}) {
      final bytes = await loadBlob(key);
      if (bytes != null) result[key] = bytes;
    }
    return result;
  }

  Future<void> flushLocal() {
    _timer?.cancel();
    final capture = _pending;
    if (capture == null) {
      return _localTail.then((_) async {
        if (_metadataDirty) await _persistMetadata();
      });
    }
    _localTail = _localTail.catchError((_) {}).then((_) async {
      if (capture.token != _pending?.token) return;
      final blobs = _record.blobs;
      final referenced = {
        for (final a in (capture.document['attachments'] as List? ?? []))
          (a as Map)['blobKey'],
        for (final a in (capture.document['attachments'] as List? ?? []))
          (a as Map)['thumbnailKey']
      };
      for (final key in _deletedBlobKeys) {
        if (!referenced.contains(key)) blobs.remove(key);
      }
      for (final entry in _blobCache.entries) {
        if (!_deletedBlobKeys.contains(entry.key) ||
            referenced.contains(entry.key)) {
          blobs[entry.key] = base64Encode(entry.value);
        }
      }
      final attachments = capture.document['attachments'] as List? ?? [];
      for (final item in attachments) {
        final attachment = item as Map;
        for (final key in [attachment['blobKey'], attachment['thumbnailKey']]) {
          if (key is! String || key.isEmpty) continue;
          final bytes = await loadBlob(key);
          if (bytes != null) blobs[key] = base64Encode(bytes);
        }
      }
      if (capture.token != _pending?.token) return;
      final candidate = _record.copyWith(
          document: capture.document,
          blobs: blobs,
          generation: _record.generation + 1,
          pendingAuthor: _desiredAuthor,
          clearPendingAuthor: _desiredAuthor == null,
          authorIntent: _authorIntent,
          portalKey: _pending?.portalKey ?? capture.portalKey,
          clearError: false);
      final changed = _record.generation == 0 ||
          candidate.fingerprint != _record.fingerprint ||
          _desiredAuthor?.id != _record.pendingAuthor?.id;
      _record = changed
          ? candidate.copyWith(clearError: _record.errorCode != 409)
          : candidate.copyWith(
              generation: _record.generation,
              acknowledgedGeneration: _record.acknowledgedGeneration);
      try {
        // Persist even incomplete recovery. Never send a partial package.
        await workspace.store.write(_record);
        _persistedGeneration = _record.generation;
        if (capture.token == _pending?.token) _pending = null;
        try {
          _record.package;
          phase = _record.errorCode == 409
              ? GraphDraftPhase.conflict
              : _record.dirty
                  ? GraphDraftPhase.savedLocally
                  : GraphDraftPhase.synced;
        } catch (error) {
          phase = GraphDraftPhase.needsPhoto;
          reason = error.toString();
        }
      } catch (error) {
        phase = GraphDraftPhase.localError;
        reason = 'Device recovery could not be saved.';
      }
      _changed();
    });
    return _localTail;
  }

  Future<void> retry() async {
    await flushLocal();
    await _sync();
  }

  Future<void> _persistMetadata() {
    _metadataDirty = true;
    _localTail = _localTail.catchError((_) {}).then((_) async {
      try {
        await workspace.store.write(_record);
        _persistedGeneration = _record.generation;
        _metadataDirty = false;
        if (phase == GraphDraftPhase.localError) {
          phase = _record.dirty
              ? GraphDraftPhase.savedLocally
              : GraphDraftPhase.synced;
        }
      } catch (_) {
        phase = GraphDraftPhase.localError;
        reason = 'Device recovery could not be saved.';
      }
    });
    return _localTail;
  }

  Future<void> _sync() async {
    if (_closed ||
        _sending ||
        _pending != null ||
        _persistedGeneration < _record.generation ||
        !_record.dirty ||
        _record.errorCode == 409) {
      return;
    }
    if (!workspace.account.active) {
      phase = GraphDraftPhase.signInRequired;
      _changed();
      return;
    }
    GraphDraftPackage package;
    try {
      package = _record.package;
    } catch (error) {
      phase = GraphDraftPhase.needsPhoto;
      reason = error.toString();
      _changed();
      return;
    }
    _sending = true;
    try {
      while (!_closed &&
          workspace.account.active &&
          _record.dirty &&
          _pending == null) {
        final sent = _record;
        try {
          package = sent.package;
        } catch (error) {
          phase = GraphDraftPhase.needsPhoto;
          reason = error.toString();
          break;
        }
        phase = GraphDraftPhase.syncing;
        _changed();
        final ack = await workspace.service.save(package,
            expectedRevision: sent.revision, authorId: sent.pendingAuthor?.id);
        if (ack.id != id) {
          throw const GraphDraftException(
              503, 'Cloud acknowledgment did not match this graph.');
        }
        draftRevision(ack.revision);
        if (!workspace.account.active || _closed) {
          phase = GraphDraftPhase.signInRequired;
          break;
        }
        final clearsAuthor = sent.authorIntent == _authorIntent;
        if (clearsAuthor) _desiredAuthor = null;
        _record = _record.copyWith(
            revision: ack.revision,
            author: ack.author,
            acknowledgedGeneration:
                sent.generation > _record.acknowledgedGeneration
                    ? sent.generation
                    : _record.acknowledgedGeneration,
            clearPendingAuthor: clearsAuthor,
            clearError: true);
        await _persistMetadata();
        if (phase == GraphDraftPhase.localError) break;
        phase = hasUnpersistedEdits
            ? GraphDraftPhase.savingLocally
            : _record.dirty
                ? GraphDraftPhase.savedLocally
                : GraphDraftPhase.synced;
        _changed();
      }
    } catch (error) {
      final code = error is GraphDraftException ? error.status : 0;
      phase = switch (code) {
        401 || 403 || 428 => GraphDraftPhase.signInRequired,
        400 => GraphDraftPhase.invalidData,
        409 => GraphDraftPhase.conflict,
        413 => GraphDraftPhase.tooLarge,
        404 || 503 => GraphDraftPhase.unavailable,
        _ => GraphDraftPhase.offline
      };
      reason = error is GraphDraftException
          ? error.message
          : 'Cloud sync could not finish.';
      _record = _record.copyWith(errorCode: code, errorMessage: reason);
      if (code == 409) {
        try {
          final remote = await workspace.service.get(id);
          if (workspace.account.active) {
            _record = _record.copyWith(conflict: remote);
          }
        } catch (_) {}
      }
      await _persistMetadata();
    } finally {
      _sending = false;
      _changed();
    }
  }

  Future<void> updatePortalKey(String key) async {
    if (_pending != null) {
      _pending = _DraftCapture(_pending!.document, _pending!.token, key);
    }
    _record = _record.copyWith(portalKey: key);
    await _persistMetadata();
    _changed();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    unawaited(flushLocal().whenComplete(() {
      _blobCache.clear();
      _suppliedReferences.clear();
    }));
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
