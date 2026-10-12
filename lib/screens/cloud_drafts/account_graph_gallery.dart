import 'graph_draft_session_scope.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/cloud_graph_draft.dart';
import '../../services/graph_repository.dart';
import '../../services/cloud_drafts/graph_draft_recovery.dart';
import '../../services/cloud_drafts/graph_draft_workspace.dart';
import 'graph_draft_editor_screen.dart';
import 'graph_draft_entry_screen.dart';

class AccountGraphGallery extends StatefulWidget {
  const AccountGraphGallery(
      {super.key,
      required this.workspace,
      this.legacyRepository,
      this.onSignOut,
      this.sessionMessage,
      this.recoverWorkspace});
  final Future<GraphDraftWorkspace> Function()? recoverWorkspace;
  final GraphDraftWorkspace workspace;
  final GraphRepository? legacyRepository;
  final VoidCallback? onSignOut;
  final String? sessionMessage;
  @override
  State<AccountGraphGallery> createState() => _AccountGraphGalleryState();
}

class _AccountGraphGalleryState extends State<AccountGraphGallery>
    with WidgetsBindingObserver {
  Timer? _queueTimer;
  bool _draining = false;
  Future<void> _drainQueue() async {
    if (_draining || !widget.workspace.account.active) return;
    _draining = true;
    final workspace = widget.workspace;
    try {
      await workspace.retryQueued();
      final local = await workspace.localGraphs();
      if (mounted && identical(workspace, widget.workspace)) {
        setState(() => _local = local);
      }
    } catch (_) {
      // Recovery remains local; refresh or the next reconnect tick retries.
    } finally {
      _draining = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_drainQueue());
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_accountChanged);
    _queueTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _accountChanged() {
    if (!mounted) return;
    setState(() {
      if (!widget.workspace.account.active) {
        _remote = [];
        _local = [];
      }
    });
  }

  bool _loading = true;
  String? _error;
  List<GraphDraftSummary> _remote = [];
  List<LocalGraphDraftSummary> _local = [];
  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_accountChanged);
    WidgetsBinding.instance.addObserver(this);
    _queueTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _drainQueue());
    _refresh();
  }

  @override
  void didUpdateWidget(covariant AccountGraphGallery old) {
    super.didUpdateWidget(old);
    if (old.workspace != widget.workspace) {
      old.workspace.removeListener(_accountChanged);
      widget.workspace.addListener(_accountChanged);
      _remote = [];
      _local = [];
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final workspace = widget.workspace;
    setState(() => _loading = true);
    try {
      await _drainQueue();
      final local = await workspace.localGraphs();
      if (!mounted || workspace != widget.workspace) return;
      setState(() => _local = local);
      final remote = await workspace.remoteGraphs();
      await workspace.refreshAuthors();
      if (!mounted ||
          workspace != widget.workspace ||
          !workspace.account.active) {
        return;
      }
      setState(() {
        _remote = remote;
        _error = null;
      });
    } catch (_) {
      if (mounted && workspace == widget.workspace) {
        setState(() => _error =
            'Cloud graphs could not be refreshed. Recovery copies on this device remain available.');
      }
    } finally {
      if (mounted && workspace == widget.workspace) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(String id) async {
    final workspace = widget.workspace;
    try {
      final session = await workspace.open(id);
      if (!mounted || workspace != widget.workspace) return;
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => GraphDraftEditorScreen(session: session)));
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'This graph could not be opened. Its recovery copy was not replaced.')));
      }
    }
  }

  Future<void> _new() async {
    final workspace = widget.workspace;
    if (!workspace.account.active) return;
    final resumeAccount = GraphDraftSessionScope.maybeOf(context)?.resume;
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => GraphDraftContextCreateScreen(
                workspace: workspace,
                resolution: Future.value(const GraphDraftEntryResolution()),
                legacyRepository: widget.legacyRepository,
                recoverWorkspace: widget.recoverWorkspace,
                resumeAccount: resumeAccount)));
    if (mounted) _refresh();
  }

  Future<void> _import() async {
    final repository = widget.legacyRepository, workspace = widget.workspace;
    if (repository == null) return;
    final graphs = await repository.listGraphs();
    if (!mounted) return;
    final selected = await showDialog<SavedGraphSummary>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Import a local copy'),
                content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'Older local graphs have no account owner. Choose only a graph you are authorized to use. The original stays unchanged.'),
                      for (final graph in graphs)
                        ListTile(
                            title: Text(graph.job.customerName),
                            subtitle:
                                const Text('Import a copy into your account'),
                            onTap: () => Navigator.pop(context, graph)),
                    ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'))
                ]));
    if (selected == null || !mounted || workspace != widget.workspace) return;
    final document = await repository.loadGraph(selected.id);
    if (document == null) return;
    final session =
        await workspace.importCopy(document, loadBlob: repository.loadBlob);
    if (!mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => GraphDraftEditorScreen(session: session)));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.workspace.account.active) {
      return const Scaffold(
          body: SafeArea(
              child: Center(
                  child: Text(
                      'Sign in to the original account to access its graphs. Recovery copies remain stored on this device.'))));
    }
    final local = {for (final graph in _local) graph.id: graph},
        remote = {for (final graph in _remote) graph.id: graph};
    final ids = {...local.keys, ...remote.keys}.toList()
      ..sort((a, b) => (local[b]?.updatedAt ?? remote[b]!.updatedAt)
          .compareTo(local[a]?.updatedAt ?? remote[a]!.updatedAt));
    return Scaffold(
        appBar: AppBar(title: const Text('My Graphs'), actions: [
          if (widget.onSignOut != null)
            TextButton(
                onPressed: widget.onSignOut, child: const Text('Sign out')),
          IconButton(
              tooltip: 'Refresh my graphs',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh)),
          if (widget.legacyRepository != null)
            IconButton(
                tooltip: 'Import a local copy',
                onPressed: _import,
                icon: const Icon(Icons.file_open_outlined))
        ]),
        body: SafeArea(
            child: Column(children: [
          if (_loading) const LinearProgressIndicator(),
          if (widget.sessionMessage != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.sessionMessage!)),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          Expanded(
              child: ids.isEmpty
                  ? const Center(
                      child: Text('Your account graphs will appear here.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: ids.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final id = ids[index],
                            recovery = local[id],
                            cloud = remote[id];
                        final pending = recovery?.dirty ?? false;
                        final title = pending
                            ? recovery!.title
                            : cloud?.title ?? recovery!.title;
                        final author = pending
                            ? recovery?.author
                            : cloud?.author ?? recovery?.author;
                        final status = recovery?.errorCode == 409
                            ? 'Cloud copy differs'
                            : pending
                                ? 'Saved on this device · waiting to sync'
                                : 'Synced';
                        return Card(
                            child: ListTile(
                                minVerticalPadding: 12,
                                leading: const Icon(Icons.polyline_outlined),
                                title: Text(
                                    title.isEmpty ? 'Untitled graph' : title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text([
                                  if (author != null)
                                    'Created by ${author.name}',
                                  status
                                ].join('\n')),
                                isThreeLine: author != null,
                                onTap: () => _open(id),
                                trailing: const Icon(Icons.chevron_right)));
                      })),
        ])),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: widget.workspace.directory == null ? null : _new,
            icon: const Icon(Icons.add),
            label: const Text('New Graph')));
  }
}
