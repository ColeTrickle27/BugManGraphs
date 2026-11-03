import 'dart:ui';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/editor/label_presentation.dart';
import 'package:bugman_graphs/widgets/graph_annotations_painter.dart';

import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/services/export_bounds_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'PNG bounds include boundary callout box and distant arrow tip at every zoom',
      () {
    final document = GraphDocument.forJob(Job(
        customerName: 'Synthetic bounds',
        serviceAddress: '',
        pestPacLocationNumber: '',
        pestPacBillToNumber: '',
        serviceType: 'Inspection',
        createdBy: '',
        createdDate: DateTime(2026, 1, 1)));
    const callout = GraphAnnotation(
        id: 'boundary-callout',
        kind: GraphAnnotationKind.text,
        point: GraphPoint(x: -120, y: -70),
        label: 'Treatment needed near the boundary',
        extraProperties: {'calloutTipX': -1900.0, 'calloutTipY': 1700.0});
    document.replaceAnnotations([callout]);
    final before = document.toJson();
    for (final zoom in [0.03, 0.15, 1.0, 4.0]) {
      final labels = LabelPresentation(zoom: zoom, bounded: true);
      final expected = GraphAnnotationsPainter.textBounds(callout, labels);
      final bounds = ExportBoundsCalculator.forDocument(document,
          labels: labels, padding: 0);
      expect(bounds.left, lessThanOrEqualTo(expected.left));
      expect(bounds.right, greaterThanOrEqualTo(expected.right));
      expect(bounds.top, lessThanOrEqualTo(expected.top));
      expect(bounds.bottom, greaterThanOrEqualTo(expected.bottom));
      expect(bounds.contains(const Offset(-1900, 1700)), isTrue);
      expect(bounds.contains(Offset(-1900 - 15 / zoom, 1700)), isTrue);
    }
    expect(
        ExportBoundsCalculator.forDocument(document,
            inspectionsVisible: false, labels: const LabelPresentation()),
        const Rect.fromLTWH(0, 0, 1, 1));
    expect(document.toJson(), before);
  });

  test('export bounds follow graph content instead of full canvas', () {
    final document = GraphDocument.forJob(
      Job(
        customerName: 'Bounds',
        serviceAddress: '',
        pestPacLocationNumber: '',
        pestPacBillToNumber: '',
        serviceType: 'Inspection',
        createdBy: '',
        createdDate: DateTime(2026, 7, 19),
      ),
    )..replaceWallSegments(const [
        WallSegment(
          start: GraphPoint(x: 100, y: 200),
          end: GraphPoint(x: 300, y: 400),
        ),
      ]);

    final bounds = ExportBoundsCalculator.forDocument(
      document,
      padding: 20,
      canvasSize: const Size(3600, 2600),
    );

    expect(bounds, const Rect.fromLTRB(80, 180, 320, 420));
  });
}
