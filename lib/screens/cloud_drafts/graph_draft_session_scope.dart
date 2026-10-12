import 'package:flutter/material.dart';
import '../../services/cloud_drafts/graph_draft_workspace.dart';

/// Lets a pushed account form resume through its owning authenticated route.
class GraphDraftSessionScope extends InheritedWidget {
  const GraphDraftSessionScope(
      {super.key, required this.resume, required super.child});
  final Future<GraphDraftWorkspace> Function(
      String username, String password, String expectedAccountId) resume;
  static GraphDraftSessionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GraphDraftSessionScope>();
  @override
  bool updateShouldNotify(GraphDraftSessionScope oldWidget) => false;
}
