import 'graph_draft_session_scope.dart';
import '../../services/cloud_drafts/graph_draft_service.dart';
import 'package:flutter/material.dart';
import '../../services/graph_repository.dart';
import '../../services/cloud_drafts/graph_draft_authentication.dart';
import '../../services/cloud_drafts/graph_draft_authentication_factory.dart';
import '../../services/cloud_drafts/graph_draft_store.dart';
import '../../services/cloud_drafts/graph_draft_store_factory.dart';
import '../../services/cloud_drafts/graph_draft_workspace.dart';
import '../../services/cloud_drafts/graph_draft_http_service.dart';
import 'account_graph_gallery.dart';
import '../../services/cloud_drafts/employee_access.dart';

class GraphDraftSessionScreen extends StatefulWidget {
  const GraphDraftSessionScreen(
      {super.key,
      this.authentication,
      this.store,
      this.legacyRepository,
      this.authenticatedBuilder});
  final GraphDraftAuthentication? authentication;
  final GraphDraftStore? store;
  final GraphRepository? legacyRepository;
  final Widget Function(BuildContext, GraphDraftWorkspace, VoidCallback)?
      authenticatedBuilder;
  @override
  State<GraphDraftSessionScreen> createState() =>
      _GraphDraftSessionScreenState();
}

class _GraphDraftSessionScreenState extends State<GraphDraftSessionScreen> {
  late final auth = widget.authentication ?? createGraphDraftAuthentication();
  late final store = widget.store ?? createGraphDraftStore();
  final username = TextEditingController(), password = TextEditingController();
  GraphDraftWorkspace? workspace;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _accept(await auth.connect());
    } catch (_) {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _accept(HttpGraphDraftService service) async {
    if (!mounted) {
      service.account.invalidate();
      return;
    }
    final old = workspace;
    old?.account.removeListener(_accountChanged);
    old?.dispose();
    final next = GraphDraftWorkspace(
        account: service.account, service: service, store: store);
    next.account.addListener(_accountChanged);
    setState(() {
      workspace = next;
      busy = false;
      error = null;
    });
  }

  void _accountChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Preserve outstanding recovery before changing the browser's session.
      final old = workspace;
      if (old != null) await old.flushRecovery();
      await _accept(await auth.login(username.text.trim(), password.text));
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Sign-in could not complete. Stored recovery was retained.';
        });
      }
    } finally {
      password.clear();
    }
  }

  Future<GraphDraftWorkspace> _resumeForm(
      String username, String password, String expectedAccountId) async {
    final service = await auth.login(username, password);
    if (service.account.id != expectedAccountId) {
      service.account.invalidate();
      throw const GraphDraftException(
          409, 'Sign in to the original account to resume this form.');
    }
    await _accept(service);
    return workspace!;
  }

  Future<void> _logout() async {
    setState(() => busy = true);
    try {
      await workspace!.flushRecovery();
      await auth.logout();
      workspace!.account.invalidate();
      workspace!.account.removeListener(_accountChanged);
      workspace!.dispose();
      if (mounted) {
        setState(() {
          workspace = null;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Sign-out could not complete. Keep this session open and retry.';
        });
      }
    }
  }

  @override
  void dispose() {
    workspace?.account.removeListener(_accountChanged);
    workspace?.dispose();
    if (widget.authentication == null) auth.close();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Keep the owning entry state mounted while its pushed form is interrupted.
    if (workspace != null && widget.authenticatedBuilder != null) {
      return Stack(children: [
        Offstage(
            offstage: !workspace!.account.active,
            child: GraphDraftSessionScope(
                resume: _resumeForm,
                child: widget.authenticatedBuilder!(
                    context, workspace!, _logout))),
        if (!workspace!.account.active) _signIn(),
      ]);
    }
    if (workspace?.account.active == true) {
      return GraphDraftSessionScope(
          resume: _resumeForm,
          child: AccountGraphGallery(
              workspace: workspace!,
              legacyRepository: widget.legacyRepository,
              onSignOut: _logout,
              sessionMessage: error));
    }
    return _signIn();
  }

  Widget _signIn() => Scaffold(
      appBar: AppBar(title: const Text('Sign in to BugMan Graphs')),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'Use your existing Holloman account. Your account graphs stay separate from Customer Files.'),
                    TextButton(
                        onPressed: () {
                          try {
                            openGraphEmployeeAccess();
                          } catch (_) {
                            setState(() => error =
                                'Employee access is available on the official Graphs host.');
                          }
                        },
                        child:
                            const Text('Verify employee access in a new tab')),
                    const SizedBox(height: 20),
                    TextField(
                        controller: username,
                        autofillHints: const [AutofillHints.username],
                        decoration:
                            const InputDecoration(labelText: 'Username')),
                    TextField(
                        controller: password,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration:
                            const InputDecoration(labelText: 'Password')),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(error!)),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _login, child: const Text('Sign in'))
                  ])))));
}
