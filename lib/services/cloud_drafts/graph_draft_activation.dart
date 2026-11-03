import 'graph_draft_workspace.dart';

/// No live host identity/session routing is assumed. The application never
/// creates a production cloud workspace while accountGraphDraftsActivated is
/// false. Tests can inject an isolated workspace and service explicitly.
GraphDraftWorkspace? createProductionGraphDraftWorkspace() {
  if (!accountGraphDraftsActivated) return null;
  throw StateError(
      'Verified account/session binding is required before activation.');
}
