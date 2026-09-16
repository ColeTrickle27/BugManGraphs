import 'package:flutter/material.dart';

import 'models/customer_file.dart';
import 'models/graph_document.dart';
import 'models/job.dart';
import 'screens/graph_canvas_screen.dart';
import 'screens/home_screen.dart';
import 'screens/new_job_screen.dart';
import 'services/bugman_portal_service_factory.dart';
import 'services/customer_files_service.dart';
import 'services/customer_files_service_factory.dart';
import 'services/graph_repository.dart';
import 'services/graph_repository_factory.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const BugManGraphsApp());
}

class BugManGraphsApp extends StatefulWidget {
  const BugManGraphsApp({super.key});

  @override
  State<BugManGraphsApp> createState() => _BugManGraphsAppState();
}

class _BugManGraphsAppState extends State<BugManGraphsApp> {
  late final GraphRepository _repository = createGraphRepository();
  late final _portalService = createBugManPortalService();
  late final CustomerFilesService _customerFilesService =
      createCustomerFilesService();
  late final String? _portalKey = _readPortalKey();
  late final bool _presentationMode =
      Uri.base.queryParameters['mode'] == 'presentation';
  late final Set<String> _presentationMarkerIds = Uri
          .base.queryParametersAll['marker']
          ?.map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet() ??
      const <String>{};
  late final Future<GraphDocument?>? _portalGraph =
      _portalKey == null ? null : _loadPortalGraph(_portalKey);
  late final _JobPreselectionRequest? _jobPreselectionRequest =
      _portalKey == null ? _readJobPreselectionRequest() : null;
  late final Future<_ResolvedPreselection>? _jobPreselection = () {
    final request = _jobPreselectionRequest;
    return request == null ? null : _resolveJobPreselection(request);
  }();
  final List<Job> _jobs = <Job>[];

  String? _readPortalKey() {
    final key = Uri.base.queryParameters['graph'];
    if (key == null || key.trim().isEmpty || !_portalService.isAvailable) {
      return null;
    }
    return key;
  }

  Future<GraphDocument?> _loadPortalGraph(String key) async {
    final package = await _portalService.loadGraph(key);
    await _repository.saveGraph(package.document, blobs: package.blobs);
    package.document.markClean();
    return package.document;
  }

  /// Reads `?billTo=...&location=...` deep-link params (e.g. from Sales
  /// Brain's "Create New" action). Only considered when there is no
  /// `?graph=` key -- a specific saved graph link always wins.
  _JobPreselectionRequest? _readJobPreselectionRequest() {
    final params = Uri.base.queryParameters;
    final billTo = params['billTo']?.trim();
    final location = params['location']?.trim();
    if (billTo == null ||
        billTo.isEmpty ||
        location == null ||
        location.isEmpty) {
      return null;
    }
    return _JobPreselectionRequest(billTo: billTo, location: location);
  }

  /// Resolves a deep-linked Bill-To/Location against Ops Brain before ever
  /// treating it as the selected customer -- raw query parameters are
  /// never trusted on their own.
  Future<_ResolvedPreselection> _resolveJobPreselection(
    _JobPreselectionRequest request,
  ) async {
    if (!_customerFilesService.isAvailable) {
      return const _ResolvedPreselection(
        warning:
            'Customer lookup is unavailable here. Enter this job\'s PestPac '
            'Bill-To and Location numbers manually, or search once this '
            'page is opened from Ops Brain.',
      );
    }
    try {
      final location = await _customerFilesService.getLocation(
        request.billTo,
        request.location,
      );
      if (location == null) {
        return _ResolvedPreselection(
          warning: 'Bill-To ${request.billTo} / Location ${request.location} '
              'was not found in Ops Brain. Search or enter the customer '
              'manually -- do not guess the PestPac numbers.',
        );
      }
      return _ResolvedPreselection(location: location);
    } catch (_) {
      return const _ResolvedPreselection(
        warning: 'Could not verify this customer with Holloman Ops Brain. '
            'Search or enter the customer manually.',
      );
    }
  }

  void _addJob(Job job) {
    setState(() => _jobs.insert(0, job));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BugManGraphs',
      debugShowCheckedModeBanner: false,
      theme: buildBugManTheme(),
      home: _portalGraph != null
          ? FutureBuilder<GraphDocument?>(
              future: _portalGraph,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _PortalOpenError(message: snapshot.error.toString());
                }
                return GraphCanvasScreen(
                  document: snapshot.data!,
                  repository: _repository,
                  portalKey: _portalKey,
                  presentationMode: _presentationMode,
                  presentationMarkerIds: _presentationMarkerIds,
                );
              },
            )
          : _jobPreselection != null
              ? FutureBuilder<_ResolvedPreselection>(
                  future: _jobPreselection,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final resolved = snapshot.data;
                    return NewJobScreen(
                      onCreateJob: _addJob,
                      customerFilesService: _customerFilesService,
                      preselectedLocation: resolved?.location,
                      resolutionWarning: resolved?.warning,
                    );
                  },
                )
              : HomeScreen(jobs: _jobs, repository: _repository),
      routes: {
        NewJobScreen.routeName: (context) => NewJobScreen(
              onCreateJob: _addJob,
              customerFilesService: _customerFilesService,
            ),
      },
      onGenerateRoute: (settings) {
        if (settings.name == GraphCanvasScreen.routeName) {
          final job = settings.arguments as Job;

          return MaterialPageRoute<void>(
            builder: (context) => GraphCanvasScreen(
              job: job,
              repository: _repository,
            ),
          );
        }

        return null;
      },
    );
  }
}

/// A raw `?billTo=&location=` deep-link request, before resolution against
/// Ops Brain. Never used directly as the selected customer.
class _JobPreselectionRequest {
  const _JobPreselectionRequest({required this.billTo, required this.location});

  final String billTo;
  final String location;
}

/// Outcome of resolving a [_JobPreselectionRequest] against Ops Brain:
/// either a confirmed [CustomerLocation], or a [warning] to surface when
/// resolution wasn't possible (not found, lookup unavailable, or failed).
class _ResolvedPreselection {
  const _ResolvedPreselection({this.location, this.warning});

  final CustomerLocation? location;
  final String? warning;
}

class _PortalOpenError extends StatelessWidget {
  const _PortalOpenError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BugManGraphs')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text('This uploaded graph could not be opened.'),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
