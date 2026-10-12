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
      this.recoverWorkspace});
  final GraphDraftWorkspace workspace;
  final Widget child;
  final ValueChanged<GraphDraftWorkspace> onRestored;
  final Future<GraphDraftWorkspace> Function()? recoverWorkspace;
  @override
  State<AccountFormGuard> createState() => _AccountFormGuardState();
}

class _AccountFormGuardState extends State<AccountFormGuard> {
  late GraphDraftWorkspace current = widget.workspace;
  bool busy = false;
  String? error;
  Future<void> _resume() async {
    GraphDraftWorkspace? next;
    if (widget.recoverWorkspace != null) {
      next = await widget.recoverWorkspace!();
    } else {
      final username = TextEditingController(),
          password = TextEditingController();
      var submitting = false;
      try {
        next = await showDialog<GraphDraftWorkspace>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
                  title: const Text('Sign in to the original account'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: username,
                        decoration:
                            const InputDecoration(labelText: 'Username')),
                    TextField(
                        controller: password,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: 'Password')),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () async {
                          if (submitting) return;
                          submitting = true;
                          final auth = createGraphDraftAuthentication();
                          try {
                            final service = await auth.login(
                                username.text.trim(), password.text);
                            final restored = GraphDraftWorkspace(
                                account: service.account,
                                service: service,
                                store: current.store,
                                onDispose: auth.close);
                            // The HTTP service shares this client; keep it alive with the resumed workspace.
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, restored);
                            } else {
                              restored.dispose();
                            }
                          } catch (_) {
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            auth.close();
                          } finally {
                            if (dialogContext.mounted) password.clear();
                          }
                        },
                        child: const Text('Sign in'))
                  ],
                ));
      } finally {
        username.dispose();
        password.dispose();
      }
    }
    if (next == null) return;
    if (!mounted) {
      next.dispose();
      return;
    }
    if (!next.account.active ||
        next.account.id != widget.workspace.account.id) {
      next.dispose();
      setState(() => error =
          'This is a different account. Sign in to the original account to recover this form.');
      return;
    }
    try {
      await next.refreshAuthors();
    } catch (_) {
      next.dispose();
      rethrow;
    }
    if (!mounted) {
      next.dispose();
      return;
    }
    widget.onRestored(next);
    setState(() {
      current = next!;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: current.account,
      child: widget.child,
      builder: (context, form) => Stack(children: [
            Offstage(
                offstage: !current.account.active,
                child: IgnorePointer(
                    ignoring: !current.account.active, child: form!)),
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
          ]));
}
