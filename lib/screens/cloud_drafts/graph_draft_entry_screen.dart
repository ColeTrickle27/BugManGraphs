import 'graph_draft_session_scope.dart';
import 'dart:async';
import 'account_form_guard.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/customer_file.dart';
import '../../models/graph_document.dart';
import '../../models/job.dart';
import '../../models/cloud_graph_draft.dart';
import '../../services/customer_files_service.dart';
import '../../services/graph_repository.dart';
import '../../services/cloud_drafts/graph_draft_workspace.dart';
import '../new_job_screen.dart';
import '../graph_canvas_screen.dart';
import 'graph_draft_editor_screen.dart';
import 'account_graph_gallery.dart';

class GraphDraftEntryResolution {
  const GraphDraftEntryResolution({this.location, this.warning});
  final CustomerLocation? location;
  final String? warning;
}

/// Deep-link creation joins the authenticated workspace; raw query identities
/// still require the existing Customer Files lookup before becoming selection.
class GraphDraftContextCreateScreen extends StatefulWidget {
  const GraphDraftContextCreateScreen(
      {super.key,
      required this.workspace,
      required this.resolution,
      this.onSignOut,
      this.customerFilesService,
      this.legacyRepository,
      this.recoverWorkspace,
      this.resumeAccount});
  final Future<GraphDraftWorkspace> Function()? recoverWorkspace;
  final Future<GraphDraftWorkspace> Function(String, String, String)?
      resumeAccount;
  final GraphDraftWorkspace workspace;
  final Future<GraphDraftEntryResolution> resolution;
  final VoidCallback? onSignOut;
  final CustomerFilesService? customerFilesService;
  final GraphRepository? legacyRepository;
  @override
  State<GraphDraftContextCreateScreen> createState() =>
      _GraphDraftContextCreateScreenState();
}

class _GraphDraftContextCreateScreenState
    extends State<GraphDraftContextCreateScreen> {
  bool busy = true;
  String? error;
  late GraphDraftWorkspace workspace = widget.workspace;
  bool _ownsWorkspace = false;
  @override
  void didUpdateWidget(covariant GraphDraftContextCreateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.workspace, widget.workspace)) {
      if (_ownsWorkspace && !identical(workspace, widget.workspace)) {
        final previous = workspace;
        scheduleMicrotask(previous.dispose);
      }
      workspace = widget.workspace;
      _ownsWorkspace = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      final selected = await widget.resolution;
      await workspace.prepareEntryAuthors();
      if (!mounted || !workspace.account.active) return;
      final directory = workspace.directory ?? const GraphDraftAuthors('', []);
      GraphDraftAuthor? author = directory.authors
          .where((x) => x.id == directory.defaultAuthorId)
          .firstOrNull;
      final resumeAccount = widget.resumeAccount ??
          GraphDraftSessionScope.maybeOf(context)?.resume;
      final originalAccountId = workspace.account.id;
      final job = await Navigator.push<Job>(
          context,
          MaterialPageRoute(
              builder: (_) => AccountFormGuard(
                  workspace: workspace,
                  onRestored: (value, locallyOwned) {
                    if (_ownsWorkspace && !identical(workspace, value)) {
                      final previous = workspace;
                      scheduleMicrotask(previous.dispose);
                    }
                    workspace = value;
                    _ownsWorkspace = locallyOwned;
                  },
                  recoverWorkspace: widget.recoverWorkspace,
                  reauthenticate: resumeAccount == null
                      ? null
                      : (username, password) =>
                          resumeAccount(username, password, originalAccountId),
                  child: const SizedBox(),
                  formBuilder: (current) {
                    final refreshed = current.directory;
                    author = refreshed?.authors
                            .where((a) => a.id == author?.id)
                            .firstOrNull ??
                        refreshed?.authors
                            .where((a) => a.id == refreshed.defaultAuthorId)
                            .firstOrNull;
                    return NewJobScreen(
                        returnCreatedJob: true,
                        onCreateJob: (_) {},
                        customerFilesService: widget.customerFilesService,
                        preselectedLocation: selected.location,
                        resolutionWarning: selected.warning,
                        cloudAuthors: current.directory ??
                            const GraphDraftAuthors('', []),
                        cloudHistoricalAuthor: author,
                        cloudInitialAuthorId: author?.id,
                        onCloudAuthorChanged: (value) => author = value);
                  })));
      if (!mounted || job == null || !workspace.account.active) {
        if (mounted) setState(() => busy = false);
        return;
      }
      final session =
          await workspace.create(GraphDocument.forJob(job), author: author);
      if (!mounted || !workspace.account.active) return;
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => GraphDraftEditorScreen(session: session)));
      if (mounted) setState(() => busy = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'The customer graph could not be opened. Stored recovery was retained.';
        });
      }
    }
  }

  @override
  void dispose() {
    if (_ownsWorkspace) {
      final restored = workspace;
      scheduleMicrotask(restored.dispose);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => busy
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : error != null
          ? Scaffold(body: Center(child: Text(error!)))
          : AccountGraphGallery(
              workspace: workspace,
              legacyRepository: widget.legacyRepository,
              onSignOut: widget.onSignOut);
}

/// Shared-folder ownership is unknown. Loading keeps existing permissions;
/// explicit import creates a new account identity without overwriting the source.
class GraphDraftSharedEntryScreen extends StatelessWidget {
  const GraphDraftSharedEntryScreen(
      {super.key,
      required this.workspace,
      required this.document,
      required this.repository,
      required this.portalKey,
      this.onSignOut});
  final GraphDraftWorkspace workspace;
  final GraphDocument document;
  final GraphRepository repository;
  final String portalKey;
  final VoidCallback? onSignOut;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: workspace.account,
      builder: (context, _) => !workspace.account.active
          ? const Scaffold(
              body: Center(
                  child: Text(
                      'Sign in to the original account to access this graph.')))
          : Scaffold(
              appBar:
                  AppBar(title: const Text('Customer Files graph'), actions: [
                if (onSignOut != null)
                  TextButton(
                      onPressed: onSignOut, child: const Text('Sign out'))
              ]),
              body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(document.customer.displayName),
                    const SizedBox(height: 16),
                    const Text(
                        'This shared graph remains in Customer Files. Make an independent copy to autosave it in your account.'),
                    TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => AnimatedBuilder(
                                    animation: workspace.account,
                                    builder: (context, _) => !workspace
                                            .account.active
                                        ? const Scaffold(
                                            body: Center(
                                                child: Text(
                                                    'Sign in to the original account to access this graph.')))
                                        : GraphCanvasScreen(
                                            document: GraphDocument.fromJson(
                                                document.toJson()),
                                            repository: repository,
                                            portalKey: portalKey,
                                            onCreateAccountGraph:
                                                (GraphDocument next,
                                                    Map<String, Uint8List>
                                                        blobs) async {
                                              await workspace
                                                  .prepareEntryAuthors();
                                              final session =
                                                  await workspace.create(next,
                                                      blobs: blobs,
                                                      author: workspace
                                                          .directory?.authors
                                                          .where((a) =>
                                                              a.id ==
                                                              workspace
                                                                  .directory!
                                                                  .defaultAuthorId)
                                                          .firstOrNull);
                                              if (context.mounted &&
                                                  workspace.account.active) {
                                                await Navigator.push(
                                                    context,
                                                    MaterialPageRoute<void>(
                                                        builder: (_) =>
                                                            GraphDraftEditorScreen(
                                                                session:
                                                                    session)));
                                              }
                                            })))),
                        child: const Text('Open Customer Files graph')),
                    FilledButton(
                        onPressed: () async {
                          await workspace.prepareEntryAuthors();
                          final copy = await workspace.importCopy(document,
                              loadBlob: repository.loadBlob);
                          if (context.mounted && workspace.account.active) {
                            await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) =>
                                        GraphDraftEditorScreen(session: copy)));
                          }
                        },
                        child: const Text('Copy to My Graphs'))
                  ]))));
}

class GraphDraftPreparedJobScreen extends StatefulWidget {
  const GraphDraftPreparedJobScreen(
      {super.key, required this.workspace, required this.job});
  final GraphDraftWorkspace workspace;
  final Job job;
  @override
  State<GraphDraftPreparedJobScreen> createState() =>
      _GraphDraftPreparedJobScreenState();
}

class _GraphDraftPreparedJobScreenState
    extends State<GraphDraftPreparedJobScreen> {
  late final future = widget.workspace.create(GraphDocument.forJob(widget.job));
  @override
  Widget build(BuildContext context) => FutureBuilder(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
              body: Center(
                  child: Text('The new account graph could not be created.')));
        }
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return GraphDraftEditorScreen(session: snapshot.data!);
      });
}
