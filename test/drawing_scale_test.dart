import 'package:bugman_graphs/editor/drawing_scale.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/widgets/graph_shapes_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final feet in [10.0, 60.0]) {
    test('$feet foot square preserves measurements through ratio and reload', () {
      final side = feet * WallSegment.pixelsPerFoot;
      final points = [Offset.zero, Offset(side, 0), Offset(side, side), Offset(0, side)];
      final segments = [for (var i = 0; i < 4; i++) WallSegment(
        start: GraphPoint.fromOffset(points[i]),
        end: GraphPoint.fromOffset(points[(i + 1) % 4]),
      )];
      const shape = GraphShape(name: 'Structure', segmentIndexes: [0,1,2,3],
        fillColor: null, fillOpacity: 0, borderColor: Colors.black,
        borderWidth: 3, pattern: GraphShapePattern.none, closed: true,
        rotationDegrees: 0, preset: GraphDrawingPreset.mainStructure);
      final document = GraphDocument(customer: GraphCustomerInfo.fromJob(Job(
        customerName: 'Scale test', serviceAddress: '', pestPacLocationNumber: '',
        pestPacBillToNumber: '', serviceType: 'Inspection', createdBy: '',
        createdDate: DateTime(2026,9,21))), wallSegments: segments, shapes: [shape]);
      final saved = document.toJson();
      final measurements = shapeExportMeasurements(shape, segments);
      expect(measurements.join(' '), contains('${feet.toInt() * feet.toInt()}'));
      for (final ratio in [1.0,2.0,3.0]) {
        final scale = DrawingScale(feetPerGridUnit: ratio);
        expect(scale.displayedGridUnitsForFeet(feet), feet / ratio);
        expect(scale.feetForDisplayedGridUnits(feet / ratio), feet);
        expect(scale.toDisplay(Offset(side,0)).dx / DrawingScale.displayedMinorSpacing, feet / ratio);
        expect(scale.toCanonical(scale.toDisplay(Offset(side,side))), Offset(side,side));
        final loaded = GraphDocument.fromJson(document.toJson());
        expect(loaded.toJson(), saved);
        expect(shapeExportMeasurements(loaded.shapes.single, loaded.wallSegments), measurements);
      }
    });
  }
}
