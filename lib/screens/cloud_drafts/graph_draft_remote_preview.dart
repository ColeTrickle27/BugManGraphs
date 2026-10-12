import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/cloud_graph_draft.dart';
import '../../models/graph_document.dart';
import '../../services/graph_repository_stub.dart';
import '../graph_canvas_screen.dart';

/// A complete remote package preview. No editing or publication actions exist.
class GraphDraftRemotePreview extends StatefulWidget {
  const GraphDraftRemotePreview({super.key, required this.remote});
  final RemoteGraphDraft remote;
  @override
  State<GraphDraftRemotePreview> createState() =>
      _GraphDraftRemotePreviewState();
}

class _GraphDraftRemotePreviewState extends State<GraphDraftRemotePreview> {
  late final document = GraphDocument.fromJson(widget.remote.package.document);
  late final blobs = (widget.remote.package.toJson()['blobs'] as Map).map(
      (key, value) => MapEntry(key as String, base64Decode(value as String)));
  late final repository = MemoryGraphRepository();
  late final Future<void> ready = repository.saveGraph(document, blobs: blobs);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cloud copy · read only'), actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ]),
        body: FutureBuilder<void>(
            future: ready,
            builder: (context, snapshot) => snapshot.connectionState !=
                    ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    Expanded(
                        child: GraphCanvasScreen(
                            document: document,
                            repository: repository,
                            presentationMode: true,
                            completePackagePreview: true)),
                    if (document.attachments.isNotEmpty)
                      SizedBox(
                          height: 164,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final attachment in document.attachments)
                                SizedBox(
                                    width: 180,
                                    child: Column(children: [
                                      Expanded(
                                          child: Image.memory(
                                              blobs[attachment.blobKey] ??
                                                  Uint8List(0),
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, error, stack) =>
                                                  const Center(
                                                      child: Text(
                                                          'Photo unavailable')))),
                                      Text(
                                          attachment.referenceLabel.isEmpty
                                              ? attachment.name
                                              : attachment.referenceLabel,
                                          maxLines: 2),
                                    ]))
                            ],
                          ))
                  ])),
      );
}
