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
  runApp(MaterialApp(
      theme: buildBugManTheme(),
      home: GraphCanvasScreen(
          document: document,
          repository: repository,
          portalService: review
              ? Page4ReviewPortal()
              : UnavailableBugManPortalService())));
}
