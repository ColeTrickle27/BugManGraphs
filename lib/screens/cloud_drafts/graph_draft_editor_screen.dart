import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/graph_document.dart';
import '../../services/bugman_portal_service.dart';
import '../../services/cloud_drafts/graph_draft_workspace.dart';
import '../../services/cloud_drafts/graph_draft_editor_repository.dart';
import '../graph_canvas_screen.dart';

class GraphDraftEditorScreen extends StatefulWidget {
  const GraphDraftEditorScreen(
      {super.key, required this.session, this.portalService});
  final GraphDraftEditorSession session;
  final BugManPortalService? portalService;
  @override
  State<GraphDraftEditorScreen> createState() => _GraphDraftEditorScreenState();
}

class _GraphDraftEditorScreenState extends State<GraphDraftEditorScreen>
    with WidgetsBindingObserver {
  Timer? _retryTimer;
  bool _retrying = false;
  Future<void> _retry() async {
    if (_retrying || !widget.session.workspace.account.active) return;
    _retrying = true;
    try {
      await widget.session.retry();
    } finally {
      _retrying = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _retryTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_retry()));
    unawaited(_retry());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_retry());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  late final GraphDocument _document =
      GraphDocument.fromJson(widget.session.documentJson);
  late final _repository = GraphDraftEditorRepository(widget.session);
  bool _allowPop = false, _closing = false;
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (popped, result) async {
        if (popped || _closing) return;
        _closing = true;
        // Let the canvas's coalesced document/attachment notification finish.
        await Future<void>.delayed(Duration.zero);
        await _repository.flushCurrent();
        if (!mounted || !context.mounted) return;
        if (_repository.session.hasUnpersistedEdits) {
          _closing = false;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Recovery could not be saved. Keep this graph open and save a recovery copy.')));
          return;
        }
        unawaited(_repository.session.retry());
        setState(() => _allowPop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && context.mounted) Navigator.pop(context, result);
      },
      child: GraphCanvasScreen(
          document: _document,
          repository: _repository,
          portalKey: widget.session.portalKey,
          portalService: widget.portalService,
          cloudDraftSession: widget.session));
}
