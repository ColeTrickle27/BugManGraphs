import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/widgets/graph_annotations_painter.dart';
import 'package:bugman_graphs/editor/label_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    for (final withTrace in [false, true]) {
      testWidgets(
        'fit and reopen include painted note bounds at $size (trace: $withTrace)',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = size;
          addTearDown(t.view.reset);
          final doc =
              GraphDocument.forJob(
                  Job(
                    customerName: 'Synthetic fit',
                    serviceAddress: '',
                    pestPacLocationNumber: '',
                    pestPacBillToNumber: '',
                    serviceType: 'Inspection',
                    createdBy: '',
                    createdDate: DateTime(2026),
                  ),
                )
                ..replaceWallSegments(const [
                  WallSegment(
                    start: GraphPoint(x: 100, y: 100),
                    end: GraphPoint(x: 460, y: 364),
                  ),
                ])
                ..replaceAnnotations(const [
                  GraphAnnotation(
                    kind: GraphAnnotationKind.text,
                    point: GraphPoint(x: 780, y: 480),
                    label: 'LONG SYNTHETIC NOTE AT THE EDGE',
                    fontSize: 20.4,
                  ),
                ])
                ..markClean();
          if (withTrace) {
            doc.replaceTraces(const [
              TraceGeometry(
                id: 'fit-yard',
                label: 'Yard',
                geoPoints: [
                  GeoPoint(latitude: 35, longitude: -78),
                  GeoPoint(latitude: 35.001, longitude: -78),
                  GeoPoint(latitude: 35.001, longitude: -77.999),
                ],
                canvasPoints: [
                  GraphPoint(x: 100, y: 100),
                  GraphPoint(x: 500, y: 100),
                  GraphPoint(x: 500, y: 400),
                ],
              ),
            ]);
            doc.markClean();
          }
          final before = doc.toJson();
          await t.pumpWidget(
            MaterialApp(
              home: GraphCanvasScreen(document: doc, fitToContentOnOpen: true),
            ),
          );
          await t.pumpAndSettle();
          void verify() {
            final f = find.byType(InteractiveViewer);
            final viewer = t.widget<InteractiveViewer>(f);
            final matrix = viewer.transformationController!.value;
            final scale = matrix.getMaxScaleOnAxis();
            final bounds = GraphAnnotationsPainter.textBounds(
              doc.annotations.single,
              LabelPresentation(zoom: scale, bounded: true),
            );
            final screen = MatrixUtils.transformRect(matrix, bounds);
            final viewport = Offset.zero & t.getSize(f);
            expect(
              screen.left,
              greaterThanOrEqualTo(size.width >= 700 ? 208 : 0),
            );
            expect(screen.right, lessThanOrEqualTo(viewport.right));
            expect(screen.top, greaterThanOrEqualTo(0));
            expect(screen.bottom, lessThanOrEqualTo(viewport.bottom));
          }

          verify();
          if (find.byTooltip('Fit drawing').evaluate().isEmpty) {
            await t.tap(find.byTooltip('Canvas options'));
            await t.pumpAndSettle();
            await t.tap(find.text('Fit drawing'));
          } else {
            await t.tap(find.byTooltip('Fit drawing'));
          }
          await t.pumpAndSettle();
          verify();
          expect(doc.toJson(), before);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
