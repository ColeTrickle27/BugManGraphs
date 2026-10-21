import 'screens/trace_workspace_screen.dart';
import 'services/trace_map_provider.dart';
import 'services/address_suggestion_service_stub.dart';
import 'models/trace_geometry.dart';
import 'screens/home_screen.dart';
import 'screens/new_job_screen.dart';
import 'services/ops_user_service.dart';
import 'package:flutter/services.dart';
import 'models/graph_annotation.dart';
import 'models/graph_point.dart';
import 'services/page4_review_fixture.dart';
import 'package:flutter/material.dart';
import 'models/graph_document.dart';
import 'models/job.dart';
import 'screens/graph_canvas_screen.dart';
import 'services/bugman_portal_service_stub.dart';
import 'services/graph_repository_stub.dart';
import 'theme/app_theme.dart';

/// Local-only entry point. Synthetic data and in-memory saves; no portal writes.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final job = Job(
      id: 'page4-synthetic',
      customerName: 'Page 4 preview — synthetic',
      serviceAddress: 'Preview property',
      pestPacLocationNumber: '',
      pestPacBillToNumber: '',
      serviceType: 'Preview',
      createdBy: 'Preview',
      createdDate: DateTime(2026, 10, 20));
  final document = GraphDocument.forJob(job);
  final review = page4ReviewParameters['exportReview'] == '1';
  if (review) {
    populateReviewFixture(
        document, page4ReviewParameters['fixture'] ?? 'standard');
  }
  final repository = MemoryGraphRepository();
  if (review &&
      (page4ReviewParameters['fixture'] ?? 'standard') == 'standard') {
    final photo =
        (await rootBundle.load('assets/branding/holloman_exterminators.png'))
            .buffer
            .asUint8List();
    document.replaceAnnotations([
      ...document.annotations,
      const GraphAnnotation(
          id: 'review-photo',
          kind: GraphAnnotationKind.photo,
          point: GraphPoint(x: 300, y: 280),
          label: 'Synthetic photos',
          attachmentIds: ['review-1', 'review-2', 'review-3'])
    ]);
    document.replaceAttachments([
      for (var i = 1; i <= 3; i++)
        GraphAttachment(
            id: 'review-$i',
            name: 'Synthetic logo $i.png',
            annotationId: 'review-photo',
            blobKey: 'review-$i',
            thumbnailKey: 'review-$i')
    ]);
    await repository.saveGraph(document,
        blobs: {for (var i = 1; i <= 3; i++) 'review-$i': photo});
  }
  if (page4ReviewParameters['reviewRoute'] == 'homeSaved') {
    await repository.saveGraph(document);
  }
  runApp(MaterialApp(
      theme: buildBugManTheme(),
      home: const ['home', 'homeSaved']
              .contains(page4ReviewParameters['reviewRoute'])
          ? HomeScreen(repository: repository)
          : const ['newJob', 'editJob']
                  .contains(page4ReviewParameters['reviewRoute'])
              ? NewJobScreen(
                  initialJob: page4ReviewParameters['reviewRoute'] == 'editJob'
                      ? job
                      : null,
                  opsUserService: UnavailableOpsUserService(),
                  onCreateJob: (_) {})
              : page4ReviewParameters['reviewRoute'] == 'trace'
                  ? TraceWorkspaceScreen(
                      address: '',
                      canvasSize: const Size(1800, 1200),
                      traceLabel: 'Preview',
                      provider: _OfflineMap(),
                      addressService: UnsupportedAddressSuggestionService(),
                      autoSelectJobAddress: false)
                  : GraphCanvasScreen(
                      presentationMode: page4ReviewParameters['reviewRoute'] ==
                          'presentation',
                      document: document,
                      repository: repository,
                      portalService: review
                          ? Page4ReviewPortal()
                          : UnavailableBugManPortalService())));
}

class _OfflineMap implements TraceMapProvider {
  @override
  Future<void> initialize() async {
    throw const TraceMapConfigurationException(
        'Local preview: live maps are disabled.');
  }

  @override
  Widget buildMap(
          {required GeoPoint center,
          required GeoPoint selectedAddress,
          required List<GeoPoint> points,
          required ValueChanged<GeoPoint> onMapTap,
          required void Function(int index, GeoPoint point) onVertexMoved}) =>
      const SizedBox();
}
