import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/graph_document.dart';
import '../services/graph_file_handoff.dart';

enum GraphFileAction { savePng, savePdf, emailPdf }

class PreparedGraphExport {
  const PreparedGraphExport(this.file, this.revision);
  final PreparedGraphFile file;
  final int revision;
}

class GraphFileHandoffDialog extends StatefulWidget {
  const GraphFileHandoffDialog(
      {super.key,
      required this.action,
      required this.document,
      required this.prepare,
      required this.revision});
  final GraphFileAction action;
  final GraphDocument document;
  final Future<PreparedGraphExport?> Function() prepare;
  final int Function() revision;
  @override
  State<GraphFileHandoffDialog> createState() => _GraphFileHandoffDialogState();
}

class _GraphFileHandoffDialogState extends State<GraphFileHandoffDialog> {
  late Future<PreparedGraphExport?> _future;
  bool _sharing = false;
  String? _status;
  bool get _png => widget.action == GraphFileAction.savePng;
  String get _kind => _png ? 'PNG' : 'PDF';
  bool get _mobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  bool get _offerShare => _mobile || widget.action == GraphFileAction.emailPdf;
  @override
  void initState() {
    super.initState();
    _future = widget.prepare();
    widget.document.addListener(_changed);
  }

  @override
  void dispose() {
    widget.document.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {
        _future = widget.prepare();
        _status = null;
      });
    }
  }

  Future<void> _share(PreparedGraphExport export) async {
    if (export.revision != widget.revision()) {
      _changed();
      return;
    }
    setState(() => _sharing = true);
    final result = await export.file.share();
    if (!mounted) return;
    setState(() {
      _sharing = false;
      _status = switch (result) {
        FileHandoffResult.handedOff =>
          'File handed off. Finish saving or sending in the app you choose.',
        FileHandoffResult.cancelled =>
          'Share cancelled. Nothing was saved or sent by Graphs.',
        FileHandoffResult.unavailable =>
          'This browser cannot share files. You can download the file instead.',
        FileHandoffResult.failed =>
          'The share sheet could not open. Try again or download the file.',
      };
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(switch (widget.action) {
          GraphFileAction.savePng => 'Save PNG',
          GraphFileAction.savePdf => 'Save PDF',
          GraphFileAction.emailPdf => 'Email PDF'
        }),
        content: SizedBox(
            width: 340,
            child: FutureBuilder<PreparedGraphExport?>(
                future: _future,
                builder: (context, snapshot) {
                  final export =
                      snapshot.connectionState == ConnectionState.done
                          ? snapshot.data
                          : null;
                  final current =
                      export != null && export.revision == widget.revision();
                  return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(switch (widget.action) {
                          GraphFileAction.savePng => _mobile
                              ? 'If Save Image is offered in the share sheet, choose it to keep the PNG in Photos. Otherwise download and save the image manually.'
                              : 'Download the PNG. Your browser controls the save location.',
                          GraphFileAction.savePdf => _mobile
                              ? 'Choose Save to Files if offered in the share sheet, or download the PDF and choose its destination yourself.'
                              : 'Download the PDF. Your browser controls the save location.',
                          GraphFileAction.emailPdf =>
                            'Share this PDF with an available email app, then review the attachment, recipient and sending account. Gmail may not be offered.',
                        }),
                        const SizedBox(height: 12),
                        if (snapshot.connectionState != ConnectionState.done)
                          const Row(children: [
                            SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 12),
                            Text('Preparing file…')
                          ])
                        else if (!current)
                          Text(snapshot.hasError
                              ? 'The file could not be prepared: ${snapshot.error}. Close this panel and try again.'
                              : 'The file could not be prepared. Close this panel and try again.')
                        else ...[
                          if (!_offerShare)
                            const Text(
                                'Check your browser downloads after saving.')
                          else if (!export.file.canShare)
                            const Text(
                                'File sharing is unavailable in this browser. Download the file and choose its destination yourself.')
                          else
                            const Text(
                                'Available destinations depend on your browser and installed apps.'),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            if (_offerShare && export.file.canShare)
                              FilledButton.icon(
                                  onPressed:
                                      _sharing ? null : () => _share(export),
                                  icon: const Icon(Icons.ios_share),
                                  label: Text(_sharing
                                      ? 'Opening…'
                                      : 'Open share sheet')),
                            TextButton.icon(
                                onPressed: _sharing
                                    ? null
                                    : () {
                                        if (export.revision !=
                                            widget.revision()) {
                                          _changed();
                                          return;
                                        }
                                        try {
                                          export.file.download();
                                          setState(() => _status =
                                              'Download requested. Check your browser’s downloads.');
                                        } catch (_) {
                                          setState(() => _status =
                                              'The download could not start.');
                                        }
                                      },
                                icon: const Icon(Icons.download),
                                label: Text('Download $_kind')),
                          ]),
                        ],
                        if (_status != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(_status!)),
                      ]);
                })),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      );
}
