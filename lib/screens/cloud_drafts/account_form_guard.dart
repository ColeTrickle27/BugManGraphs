import 'package:flutter/material.dart';
import '../../services/cloud_drafts/graph_draft_authentication_factory.dart';
import '../../services/cloud_drafts/graph_draft_workspace.dart';

/// Keeps controllers scoped to the original owner while a session is interrupted.
class AccountFormGuard extends StatefulWidget {
  const AccountFormGuard(
      {super.key,
      required this.workspace,
      required this.child,
      required this.onRestored,
      this.recoverWorkspace,
      this.reauthenticate,
      this.formBuilder});
  final GraphDraftWorkspace workspace;
  final Widget child;
  final Widget Function(GraphDraftWorkspace)? formBuilder;
  Widget get initialForm => child;
  final Future<GraphDraftWorkspace> Function(String, String)? reauthenticate;
  final void Function(GraphDraftWorkspace workspace, bool locallyOwned)
      onRestored;
  final Future<GraphDraftWorkspace> Function()? recoverWorkspace;
  @override
  State<AccountFormGuard> createState() => _AccountFormGuardState();
}

class _AccountFormGuardState extends State<AccountFormGuard> {
  late GraphDraftWorkspace current = widget.workspace;
  late Widget form = widget.initialForm;
  bool busy = false;
  String? error;
  Future<void> _resume() async {
    GraphDraftWorkspace? next;
    if (widget.recoverWorkspace != null) {
      next = await widget.recoverWorkspace!();
    } else {
      next = await showDialog<GraphDraftWorkspace>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _OriginalAccountLoginDialog(
                  authenticate: (username, password) async {
                if (widget.reauthenticate != null) {
                  return widget.reauthenticate!(username, password);
                }
                final auth = createGraphDraftAuthentication();
                try {
                  final service = await auth.login(username, password);
                  return GraphDraftWorkspace(
                      account: service.account,
                      service: service,
                      store: current.store,
                      onDispose: auth.close);
                } catch (_) {
                  auth.close();
                  rethrow;
                }
              }));
    }
    final locallyOwned =
        widget.recoverWorkspace != null || widget.reauthenticate == null;
    if (next == null) return;
    if (!mounted) {
      if (locallyOwned) next.dispose();
      return;
    }
    if (!next.account.active ||
        next.account.id != widget.workspace.account.id) {
      if (locallyOwned) next.dispose();
      setState(() => error =
          'This is a different account. Sign in to the original account to recover this form.');
      return;
    }
    try {
      await next.prepareEntryAuthors();
    } catch (_) {
      if (locallyOwned) next.dispose();
      rethrow;
    }
    if (!mounted) {
      if (locallyOwned) next.dispose();
      return;
    }
    widget.onRestored(next, locallyOwned);
    setState(() {
      current = next!;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: current.account,
      builder: (context, _) {
        if (current.account.active && widget.formBuilder != null) {
          form = widget.formBuilder!(current);
        }
        if (!current.account.active) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
        return Stack(children: [
          Offstage(
              offstage: !current.account.active,
              child: ExcludeFocus(
                  excluding: !current.account.active,
                  child: IgnorePointer(
                      ignoring: !current.account.active, child: form))),
          if (!current.account.active)
            Scaffold(
                appBar: AppBar(title: const Text('New graph interrupted')),
                body: Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text(
                              'Entered details are retained for the original account and hidden while signed out. Sign in to that account to resume. Going back discards this unfinished form.'),
                          if (error != null) Text(error!),
                          TextButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      setState(() => busy = true);
                                      try {
                                        await _resume();
                                      } catch (_) {
                                        if (mounted) {
                                          setState(() => error =
                                              'Sign-in could not complete. Your form is retained.');
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => busy = false);
                                        }
                                      }
                                    },
                              child: const Text('Resume original form')),
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Discard form and go back')),
                        ])))),
        ]);
      });
}

class _OriginalAccountLoginDialog extends StatefulWidget {
  const _OriginalAccountLoginDialog({required this.authenticate});
  final Future<GraphDraftWorkspace> Function(String, String) authenticate;
  @override
  State<_OriginalAccountLoginDialog> createState() =>
      _OriginalAccountLoginDialogState();
}

class _OriginalAccountLoginDialogState
    extends State<_OriginalAccountLoginDialog> {
  final username = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next =
          await widget.authenticate(username.text.trim(), password.text);
      if (mounted) Navigator.pop(context, next);
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Sign in to the original account. Your entered graph details remain retained.');
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          password.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Sign in to the original account'),
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: username,
              decoration: const InputDecoration(labelText: 'Username')),
          TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password')),
          if (error != null) Text(error!),
        ]),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: busy ? null : _login, child: const Text('Sign in')),
        ],
      ));
}
