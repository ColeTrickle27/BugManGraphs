import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/graph_file_handoff_factory.dart';
import '../../services/cloud_drafts/graph_draft_workspace.dart';
import '../../services/cloud_drafts/employee_access.dart';
import '../../screens/cloud_drafts/graph_draft_remote_preview.dart';

Future<GraphDraftEditorSession?> showGraphDraftSyncPanel(
        BuildContext context, GraphDraftEditorSession session) =>
    showModalBottomSheet<GraphDraftEditorSession>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: AnimatedBuilder(
                animation:
                    Listenable.merge([session, session.workspace.account]),
                builder: (context, _) => !session.workspace.account.active
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text(
                              'Sign in to the original account to access its recovery copies.'),
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'))
                        ]))
                    : SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(session.statusText,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 8),
                                  const Text(
                                      'Account drafts stay separate from saving a graph into Customer Files.'),
                                  if (session.reason != null)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Text(session.reason!)),
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    if (session.phase ==
                                            GraphDraftPhase.unavailable ||
                                        session.phase ==
                                            GraphDraftPhase.signInRequired)
                                      TextButton(
                                          onPressed: () {
                                            try {
                                              openGraphEmployeeAccess();
                                            } catch (_) {}
                                          },
                                          child: const Text(
                                              'Verify employee access in a new tab')),
                                    if (session.phase !=
                                        GraphDraftPhase.conflict)
                                      FilledButton.icon(
                                          onPressed: () => session.retry(),
                                          icon: const Icon(Icons.sync),
                                          label: const Text('Retry sync')),
                                    if (session.recovery.conflict != null)
                                      TextButton.icon(
                                          icon: const Icon(
                                              Icons.visibility_outlined),
                                          label:
                                              const Text('Review cloud copy'),
                                          onPressed: () {
                                            final cloud =
                                                session.recovery.conflict!;
                                            Navigator.push(
                                                context,
                                                MaterialPageRoute<void>(
                                                    builder: (_) =>
                                                        GraphDraftRemotePreview(
                                                            remote: cloud,
                                                            account: session
                                                                .workspace
                                                                .account)));
                                          }),
                                    if (session.phase ==
                                        GraphDraftPhase.conflict)
                                      FilledButton.icon(
                                          icon: const Icon(
                                              Icons.copy_all_outlined),
                                          label: const Text('Keep both copies'),
                                          onPressed: () async {
                                            final fork = await session.workspace
                                                .keepBoth(session);
                                            if (context.mounted) {
                                              Navigator.pop(context, fork);
                                            }
                                          }),
                                    TextButton.icon(
                                        icon:
                                            const Icon(Icons.download_outlined),
                                        label: const Text(
                                            'Download recovery copy'),
                                        onPressed: () async {
                                          await session.flushLocal();
                                          final record = session.recovery;
                                          final json = {
                                            ...record.packageExtras,
                                            'type': 'bugman-graph',
                                            'version': 1,
                                            'document': record.document,
                                            'blobs': record.blobs,
                                            if (record.author != null)
                                              'authorSnapshot':
                                                  record.author!.toJson()
                                          };
                                          final file = createGraphFileHandoff()
                                              .prepare(
                                                  Uint8List.fromList(
                                                      utf8.encode(
                                                          jsonEncode(json))),
                                                  'graph-recovery-${record.id}.bgraph',
                                                  'application/json');
                                          try {
                                            file.download();
                                          } catch (_) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content: Text(
                                                          'Recovery download could not start. Keep the graph open.')));
                                            }
                                          }
                                        }),
                                    TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Close')),
                                  ]),
                                ]))))));
