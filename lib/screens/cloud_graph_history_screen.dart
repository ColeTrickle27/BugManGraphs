import 'package:flutter/material.dart';

import '../services/bugman_portal_service.dart';
import '../services/cloud_graph_history.dart';
import '../services/portal_sign_in.dart';
import 'cloud_graph_package_preview.dart';

class CloudGraphHistoryScreen extends StatefulWidget {
  const CloudGraphHistoryScreen({
    super.key,
    required this.service,
    required this.portal,
  });
  final CloudGraphHistoryService service;
  final BugManPortalService portal;
  @override
  State<CloudGraphHistoryScreen> createState() =>
      _CloudGraphHistoryScreenState();
}

class _CloudGraphHistoryScreenState extends State<CloudGraphHistoryScreen> {
  final Map<String, CloudGraphHistoryEntry> _graphs = {};
  final Set<String> _visitedCursors = {};
  String? _cursor;
  String? _error;
  String? _signInUrl;
  bool _loading = false;
  bool _opening = false;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant CloudGraphHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.portal != widget.portal) {
      _generation++;
      _loading = false;
      _opening = false;
      _graphs.clear();
      _cursor = null;
      _load(reset: true);
    }
  }

  bool _current(int generation) => mounted && generation == _generation;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    final generation = ++_generation;
    final service = widget.service;
    setState(() {
      _loading = true;
      _error = null;
      _signInUrl = null;
    });
    try {
      final requested = reset ? null : _cursor;
      final page = await service.list(cursor: requested);
      if (!_current(generation)) return;
      if (!reset &&
          page.nextCursor != null &&
          _visitedCursors.contains(page.nextCursor)) {
        throw const FormatException('Repeated history page.');
      }
      setState(() {
        if (reset) {
          _graphs.clear();
          _visitedCursors.clear();
        }
        if (requested != null) _visitedCursors.add(requested);
        for (final graph in page.graphs) {
          _graphs[graph.key] = graph;
        }
        _cursor = page.nextCursor;
      });
    } on PortalAuthenticationException catch (error) {
      if (_current(generation)) {
        setState(() {
          _graphs.clear();
          _cursor = null;
          _signInUrl = error.signInUrl;
          _error = 'Sign in to OpsBrain, then refresh cloud history.';
        });
      }
    } on CloudGraphHistoryAccessException {
      if (_current(generation)) {
        setState(() {
          _graphs.clear();
          _cursor = null;
          _error = 'Your OpsBrain session cannot access shared graph history.';
        });
      }
    } catch (_) {
      if (_current(generation)) {
        setState(() {
          _signInUrl = opsBrainHomeUrl(Uri.base);
          _error =
              'Cloud history could not be loaded. Sign in to OpsBrain if needed, then refresh. Local graphs remain on this device.';
        });
      }
    } finally {
      if (_current(generation)) setState(() => _loading = false);
    }
  }

  Future<void> _open(CloudGraphHistoryEntry entry) async {
    if (_opening) return;
    final generation = _generation;
    final portal = widget.portal;
    setState(() => _opening = true);
    try {
      final package = await portal.loadGraph(entry.key);
      if (!mounted || generation != _generation) return;
      if (entry.finalized && !package.isFinalized) {
        throw const PortalFinalizationException();
      }
      // Never route through ?graph=, which saves into the local repository.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CloudGraphPackagePreview(package: package),
        ),
      );
    } on PortalAuthenticationException catch (error) {
      if (_current(generation)) {
        setState(() {
          _graphs.clear();
          _cursor = null;
          _signInUrl = error.signInUrl;
          _error = 'Sign in to OpsBrain, then refresh cloud history.';
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This cloud graph could not be previewed. The saved file is unchanged.',
            ),
          ),
        );
      }
    } finally {
      if (_current(generation)) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final graphs = _graphs.values.toList()
      ..sort(
        (a, b) =>
            (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
      );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud graph history'),
        actions: [
          IconButton(
            tooltip: 'Refresh cloud history',
            onPressed: _loading || _opening ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Shared saved graphs from Customer Files and company uploads, available through your OpsBrain session. Open a read-only preview. Local graphs remain in Your Graphs.',
            ),
          ),
          if (_loading || _opening) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          if (_signInUrl != null)
            TextButton(
              onPressed: () => openPortalSignIn(_signInUrl!),
              child: const Text('Sign in in new tab'),
            ),
          Expanded(
            child: graphs.isEmpty && !_loading && _error == null
                ? Center(
                    child: Text(
                      _cursor == null
                          ? 'No shared cloud graphs found.'
                          : 'No graphs on this page. Load more to continue history.',
                    ),
                  )
                : ListView.builder(
                    itemCount: graphs.length,
                    itemBuilder: (context, index) {
                      final graph = graphs[index];
                      return ListTile(
                        leading: Icon(
                          graph.finalized ? Icons.lock_outline : Icons.history,
                        ),
                        title: Text(graph.name),
                        subtitle: Text(
                          [
                            graph.customerName,
                            graph.serviceAddress,
                            if (graph.updatedAt != null)
                              graph.updatedAt!.toLocal().toString(),
                            if (graph.finalized) 'Finalized',
                          ].where((s) => s.isNotEmpty).join('\n'),
                        ),
                        trailing: const Icon(Icons.visibility_outlined),
                        onTap: _opening || _loading ? null : () => _open(graph),
                      );
                    },
                  ),
          ),
          if (_cursor != null)
            SafeArea(
              top: false,
              child: TextButton(
                onPressed: _loading || _opening ? null : () => _load(),
                child: const Text('Load more history'),
              ),
            ),
        ],
      ),
    );
  }
}
