import 'dart:ui';

import '../models/graph_document.dart';
import '../models/graph_annotation.dart';
import '../models/graph_marker_catalog.dart';
import '../models/graph_point.dart';
import '../models/graph_shape.dart';
import 'trace_presentation.dart';

class ExportBoundsCalculator {
  const ExportBoundsCalculator._();

  static Rect forDocument(
    GraphDocument document, {
    double padding = 48,
    Size? canvasSize,
    bool structureVisible = true,
    bool shapesVisible = true,
    bool inspectionsVisible = true,
    bool treatmentVisible = true,
    bool photosVisible = true,
    bool traceVisible = true,
  }) {
    final shapeSegmentIndexes = <int>{};
    final visibleShapeSegmentIndexes = <int>{};
    for (final shape in document.shapes) {
      shapeSegmentIndexes.addAll(shape.segmentIndexes);
      final visible = shape.preset == GraphDrawingPreset.treatmentArea
          ? treatmentVisible
          : shapesVisible;
      if (visible) visibleShapeSegmentIndexes.addAll(shape.segmentIndexes);
    }
    final points = <GraphPoint>[
      for (var index = 0; index < document.wallSegments.length; index += 1)
        if ((shapeSegmentIndexes.contains(index)
            ? visibleShapeSegmentIndexes.contains(index)
            : structureVisible))
          for (final segment in [document.wallSegments[index]]) ...[
            segment.start,
            segment.end,
            if (segment.controlPoint != null) segment.controlPoint!,
          ],
      for (final annotation in document.annotations)
        if (_annotationVisible(
          annotation,
          structureVisible: structureVisible,
          inspectionsVisible: inspectionsVisible,
          treatmentVisible: treatmentVisible,
          photosVisible: photosVisible,
        ))
          annotation.point,
      if (structureVisible)
        for (final stroke in document.freehandStrokes) ...stroke.points,
      if (traceVisible)
        for (final trace in document.traces) ...trace.canvasPoints,
    ];

    if (points.isEmpty) {
      final fallback = Offset.zero & (canvasSize ?? const Size(1, 1));
      return fallback;
    }

    var left = points.first.x;
    var top = points.first.y;
    var right = points.first.x;
    var bottom = points.first.y;
    for (final point in points.skip(1)) {
      if (point.x < left) left = point.x;
      if (point.x > right) right = point.x;
      if (point.y < top) top = point.y;
      if (point.y > bottom) bottom = point.y;
    }

    var bounds = Rect.fromLTRB(
      left - padding,
      top - padding,
      right + padding,
      bottom + padding,
    );
    if (traceVisible) {
      final traceBounds = TracePresentation.paintedBounds(document.traces);
      if (traceBounds != null) bounds = bounds.expandToInclude(traceBounds);
    }
    if (bounds.width < 1 || bounds.height < 1) {
      return Rect.fromLTWH(bounds.left, bounds.top, 1, 1);
    }
    return bounds;
  }

  static bool _annotationVisible(
    GraphAnnotation annotation, {
    required bool structureVisible,
    required bool inspectionsVisible,
    required bool treatmentVisible,
    required bool photosVisible,
  }) =>
      switch (annotation.kind) {
        GraphAnnotationKind.photo => photosVisible,
        GraphAnnotationKind.text => inspectionsVisible,
        GraphAnnotationKind.marker
            when utilityMarkerTypes.contains(annotation.markerType) =>
          structureVisible,
        GraphAnnotationKind.marker
            when isTreatmentMarker(annotation.markerType) =>
          treatmentVisible,
        GraphAnnotationKind.marker => inspectionsVisible,
      };
}
