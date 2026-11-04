import 'package:flutter/material.dart';

import '../services/bugman_portal_service.dart';
import '../services/bugman_portal_service_stub.dart';
import '../services/cloud_graph_history.dart';
import '../services/cloud_graph_preview_repository.dart';
import '../services/portal_sign_in.dart';
import 'graph_canvas_screen.dart';

class CloudGraphHistoryScreen extends StatefulWidget {
  const CloudGraphHistoryScreen({super.key, required this.service,
    required this.portal});
  final CloudGraphHistoryService service;
  final BugManPortalService portal;
  @override
  State<CloudGraphHistoryScreen> createState() => _CloudGraphHistoryScreenState();
}

class _CloudGraphHistoryScreenState extends State<CloudGraphHistoryScreen> {
  final Map<String, CloudGraphHistoryEntry> _graphs = {};
  final Set<String> _visitedCursors = {};
  String? _cursor;
  String? _error;
  String? _signInUrl;
  bool _loading = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; _signInUrl = null; });
    try {
      final requested = reset ? null : _cursor;
      final page = await widget.service.list(cursor: requested);
      if (!mounted) return;
      if (!reset && page.nextCursor != null &&
          _visitedCursors.contains(page.nextCursor)) {
        throw const FormatException('Repeated history page.');
      }
      setState(() {
        if (reset) { _graphs.clear(); _visitedCursors.clear(); }
        if (requested != null) _visitedCursors.add(requested);
        for (final graph in page.graphs) { _graphs[graph.key] = graph; }
        _cursor = page.nextCursor;
      });
    } on PortalAuthenticationException catch (error) {
      if (mounted) setState(() {
        _graphs.clear(); _cursor = null;
        _signInUrl = error.signInUrl;
        _error = 'Sign in to OpsBrain, then refresh cloud history.';
      });
    } on CloudGraphHistoryAccessException {
      if (mounted) setState(() {
        _graphs.clear(); _cursor = null;
        _error = 'Your OpsBrain session cannot access shared graph history.';
      });
    } catch (_) {
      if (mounted) setState(() {
        _signInUrl = opsBrainHomeUrl(Uri.base);
        _error = 'Cloud history could not be loaded. Sign in to OpsBrain if needed, then refresh. Local graphs remain on this device.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(CloudGraphHistoryEntry entry) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final package = await widget.portal.loadGraph(entry.key);
      if (!mounted) return;
      // Never route through ?graph=, which saves into the local repository.
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        Scaffold(
          appBar: AppBar(title: const Text('Cloud history · read only')),
          body: GraphCanvasScreen(document: package.document,
            repository: CloudGraphPreviewRepository(package),
            portalService: UnavailableBugManPortalService(),
            presentationMode: true, completePackagePreview: true),
        )));
    } on PortalAuthenticationException catch (error) {
      if (mounted) setState(() {
        _graphs.clear(); _cursor = null; _signInUrl = error.signInUrl;
        _error = 'Sign in to OpsBrain, then refresh cloud history.';
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This cloud graph could not be previewed. The saved file is unchanged.')));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final graphs = _graphs.values.toList()..sort((a, b) =>
      (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud graph history'), actions: [
        IconButton(tooltip: 'Refresh cloud history',
          onPressed: _loading || _opening ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text(
          'Shared saved graphs from Customer Files and company uploads, available through your OpsBrain session. Open a read-only preview. Local graphs remain in Your Graphs.')),
        if (_loading || _opening) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        if (_signInUrl != null) TextButton(onPressed: () => openPortalSignIn(_signInUrl!),
          child: const Text('Sign in in new tab')),
        Expanded(child: graphs.isEmpty && !_loading && _error == null
          ? Center(child: Text(_cursor == null ? 'No shared cloud graphs found.' :
              'No graphs on this page. Load more to continue history.'))
          : ListView.builder(itemCount: graphs.length, itemBuilder: (context, index) {
            final graph = graphs[index];
            return ListTile(leading: Icon(graph.finalized ? Icons.lock_outline : Icons.history),
              title: Text(graph.name),
              subtitle: Text([graph.customerName, graph.serviceAddress,
                if (graph.updatedAt != null) graph.updatedAt!.toLocal().toString(),
                if (graph.finalized) 'Finalized'].where((s) => s.isNotEmpty).join('\n')),
              trailing: const Icon(Icons.visibility_outlined),
              onTap: _opening || _loading ? null : () => _open(graph));
          })),
        if (_cursor != null) SafeArea(top: false, child: TextButton(
          onPressed: _loading || _opening ? null : () => _load(),
          child: const Text('Load more history'))),
      ]),
    );
  }
}
