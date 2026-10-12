import 'package:flutter/foundation.dart';
import '../../models/cloud_graph_draft.dart';

class GraphDraftException implements Exception {
  const GraphDraftException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Immutable local ownership scope supplied by a verified host identity.
/// This is distinct from editable employee attribution. The production host
/// binding remains disabled pending account migration/session-routing approval.
class GraphDraftAccount extends ChangeNotifier {
  GraphDraftAccount({required this.id, required this.displayName}) {
    if (!RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(id)) {
      throw const FormatException('An immutable account identity is required');
    }
  }
  final String id, displayName;
  bool _active = true;
  bool get active => _active;
  void invalidate() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }
}

abstract class GraphDraftService {
  Future<GraphDraftAuthors> authors();
  Future<GraphDraftPage> list({int limit = 100, String? cursor});
  Future<RemoteGraphDraft> get(String id);
  Future<GraphDraftWriteResult> save(GraphDraftPackage package,
      {required String? expectedRevision, String? authorId});
}
