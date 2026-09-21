import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/graph_shape.dart';
import '../editor/rectangle_geometry.dart';
import '../models/wall_segment.dart';
import '../services/measurement_format.dart';
import 'wall_segments_painter.dart';

@visibleForTesting
bool usesStyledSegmentRendering(GraphShape shape) =>
    shape.preset?.kind == GraphDrawingPresetKind.line ||
    const {'wall', 'arrow', 'curve'}
        .contains(shape.extraProperties['sourceTool']) ||
    (!shape.closed && shape.fillColor == null);

String shapeMeasurementSummary(
  GraphShape shape,
  List<WallSegment> shapeSegments,
) {
  final preset = shape.preset;
  if (preset == null || shapeSegments.isEmpty) {
    return '';
  }

  final squareFeet = _shapeAreaSquareFeet(shape, shapeSegments);
  final linearFeet = shapeSegments.fold<double>(
    0,
    (total, segment) => total + segment.lengthFeet,
  );
  if (preset.showsLinearAndAreaMeasurements) {
    if (!shape.closed || shapeSegments.length < 3) {
      return MeasurementFormat.linearFeet(linearFeet);
    }
    return '${MeasurementFormat.linearFeet(linearFeet)} • '
        '${MeasurementFormat.squareFeet(squareFeet)}';
  }

  if (preset.showsPropertyAreaMeasurements && shape.closed) {
    final acres = squareFeet / 43560;
    return '${MeasurementFormat.acres(acres)} • '
        '${MeasurementFormat.squareFeet(squareFeet)} • '
        '${MeasurementFormat.linearFeet(linearFeet)}';
  }

  if (preset == GraphDrawingPreset.fenceLine ||
      preset == GraphDrawingPreset.measurementLine) {
    return MeasurementFormat.linearFeet(linearFeet);
  }

  return '';
}

/// Measurements used by exports. Unlike the on-canvas summary, this includes
/// every drawn shape or line that has usable geometry.
List<String> shapeExportMeasurements(
  GraphShape shape,
  List<WallSegment> shapeSegments,
) {
  if (shapeSegments.isEmpty) {
    return const [];
  }

  final measurements = <String>[];
  if (shape.closed && shapeSegments.length >= 3) {
    measurements.add(
      MeasurementFormat.squareFeet(_shapeAreaSquareFeet(shape, shapeSegments)),
    );
  }
  final linearFeet = shapeSegments.fold<double>(
    0,
    (total, segment) => total + segment.lengthFeet,
  );
  if (linearFeet > 0) {
    measurements.add(MeasurementFormat.linearFeet(linearFeet));
  }
  return measurements;
}

double _shapeAreaSquareFeet(
  GraphShape shape,
  List<WallSegment> shapeSegments,
) {
  if (!shape.closed || shapeSegments.length < 3) {
    return 0;
  }

  final points = shapeSegments.map((segment) => segment.start).toList();
  var areaPixels = 0.0;
  for (var i = 0; i < points.length; i += 1) {
    final current = points[i];
    final next = points[(i + 1) % points.length];
    areaPixels += (current.x * next.y) - (next.x * current.y);
  }
  return areaPixels.abs() /
      2 /
      (WallSegment.pixelsPerFoot * WallSegment.pixelsPerFoot);
}

class GraphShapesPainter extends CustomPainter {
  const GraphShapesPainter({
    required this.shapes,
    required this.segments,
    required this.selectedShapeIndex,
    this.hoveredShapeIndex,
    this.structureVisible = true,
    this.treatmentVisible = true,
  });

  final List<GraphShape> shapes;
  final List<WallSegment> segments;
  final int? selectedShapeIndex;
  final int? hoveredShapeIndex;
  final bool structureVisible;
  final bool treatmentVisible;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < shapes.length; i += 1) {
      final shape = shapes[i];
      final isTreatment = shape.preset == GraphDrawingPreset.treatmentArea;
      if ((isTreatment && !treatmentVisible) ||
          (!isTreatment && !structureVisible)) {
        continue;
      }
      final shapeSegments = _segmentsForShape(shape);
      if (shapeSegments.isEmpty) {
        continue;
      }

      final path = _pathForShape(shape, shapeSegments);
      final bounds = path.getBounds();
      final isStyledLine = usesStyledSegmentRendering(shape);
      final isQuickMeasure = shape.preset == GraphDrawingPreset.measurementLine;

      if (isStyledLine) {
        WallSegmentsPainter(
          segments: shapeSegments,
          selectedSegmentIndex: null,
          hoveredSegmentIndex: null,
          activeWallStart: null,
          previewSegment: null,
          drawMeasurements: true,
          measurementReferencePoint: shape.closed ? bounds.center : null,
        ).paint(canvas, size);
      } else if (shape.fillColor != null && (!isQuickMeasure || shape.closed)) {
        canvas.drawPath(
          path,
          Paint()
            ..color = shape.fillColor!.withValues(alpha: shape.fillOpacity),
        );
      }

      if (!isStyledLine && isQuickMeasure) {
        WallSegmentsPainter(
          segments: shapeSegments,
          selectedSegmentIndex: null,
          hoveredSegmentIndex: null,
          activeWallStart: null,
          previewSegment: null,
          measurementReferencePoint: bounds.center,
        ).paint(canvas, size);
      } else if (!isStyledLine) {
        _drawPattern(canvas, shape.pattern, path, bounds);
        _drawShapeBorder(canvas, shape, path);
        if (shape.preset?.showsLinearAndAreaMeasurements ?? false) {
          WallSegmentsPainter(
            segments: shapeSegments,
            selectedSegmentIndex: null,
            hoveredSegmentIndex: null,
            activeWallStart: null,
            previewSegment: null,
            paintSegments: false,
            drawEndpoints: false,
            measurementReferencePoint: bounds.center,
          ).paint(canvas, size);
        }
      }

      final measurementSummary = shapeMeasurementSummary(shape, shapeSegments);
      final shapeLabel = shape.text.trim().isEmpty ? shape.name : shape.text;
      final foundationLabel = shape.preset == GraphDrawingPreset.mainStructure
          ? shape.foundationType?.label
          : null;
      final labelLines = <String>[
        shapeLabel,
        if (foundationLabel != null) foundationLabel,
        if (measurementSummary.isNotEmpty) measurementSummary,
      ];
      _drawShapeName(
        canvas,
        labelLines.join('\n'),
        shape.preset == GraphDrawingPreset.propertyLine
            ? _propertyLineLabelPosition(shapeSegments, bounds)
            : bounds.center,
      );

      if (i == hoveredShapeIndex && i != selectedShapeIndex) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF2F80ED).withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      }

      if (i == selectedShapeIndex) {
        _drawSelectedShape(canvas, shape, shapeSegments, path, bounds);
      }
    }
  }

  Offset _propertyLineLabelPosition(
    List<WallSegment> segments,
    Rect bounds,
  ) {
    final longest = segments.reduce(
      (current, candidate) =>
          candidate.lengthFeet > current.lengthFeet ? candidate : current,
    );
    final start = longest.start.offset;
    final end = longest.end.offset;
    final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final vector = end - start;
    if (vector.distance == 0) return midpoint;
    var normal = Offset(-vector.dy, vector.dx) / vector.distance;
    final towardCenter = bounds.center - midpoint;
    if ((normal.dx * towardCenter.dx) + (normal.dy * towardCenter.dy) > 0) {
      normal = -normal;
    }
    return midpoint +
        (normal * math.min(96, math.max(72, bounds.shortestSide / 3)));
  }

  void _drawShapeBorder(Canvas canvas, GraphShape shape, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..color = shape.borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.borderWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawSelectedShape(
    Canvas canvas,
    GraphShape shape,
    List<WallSegment> shapeSegments,
    Path path,
    Rect bounds,
  ) {
    final selectedPaint = Paint()
      ..color = const Color(0xFF2F80ED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, selectedPaint);

    final kind = shape.extraProperties['basicShapeKind']?.toString();
    final legacyName = shape.name.toLowerCase();
    final supportsVertices = kind != 'circle' &&
        kind != 'ellipse' &&
        !legacyName.startsWith('circle') &&
        !legacyName.startsWith('ellipse');
    final handleCenters = supportsVertices
        ? <Offset>{
            for (final segment in shapeSegments) segment.start.offset,
            for (final segment in shapeSegments) segment.end.offset,
          }
        : <Offset>{
            bounds.topLeft,
            bounds.topRight,
            bounds.bottomLeft,
            bounds.bottomRight,
          };

    for (final handleCenter in handleCenters) {
      final handle = Rect.fromCenter(
        center: handleCenter,
        width: 12,
        height: 12,
      );
      canvas.drawRect(handle, Paint()..color = Colors.white);
      canvas.drawRect(handle, selectedPaint);
    }

    if (RectangleGeometry.isRectangle(shapeSegments)) {
      for (final segment in shapeSegments) {
        final center = (segment.start.offset + segment.end.offset) / 2;
        canvas.drawCircle(center, 7, Paint()..color = Colors.white);
        canvas.drawCircle(center, 7, selectedPaint);
      }
    }

    final rotationHandleCenter = bounds.topCenter - const Offset(0, 28);
    canvas.drawLine(bounds.topCenter, rotationHandleCenter, selectedPaint);
    canvas.drawCircle(rotationHandleCenter, 6, Paint()..color = Colors.white);
    canvas.drawCircle(rotationHandleCenter, 6, selectedPaint);
  }

  List<WallSegment> _segmentsForShape(GraphShape shape) {
    return shape.segmentIndexes
        .where((index) => index >= 0 && index < segments.length)
        .map((index) => segments[index])
        .toList();
  }

  Path _pathForShape(GraphShape shape, List<WallSegment> shapeSegments) {
    final path = Path()
      ..moveTo(shapeSegments.first.start.x, shapeSegments.first.start.y);

    for (final segment in shapeSegments) {
      final controlPoint = segment.controlPoint;
      if (controlPoint == null) {
        path.lineTo(segment.end.x, segment.end.y);
      } else {
        path.quadraticBezierTo(
          controlPoint.x,
          controlPoint.y,
          segment.end.x,
          segment.end.y,
        );
      }
    }

    if (shape.closed) {
      path.close();
    }

    return path;
  }

  void _drawPattern(
    Canvas canvas,
    GraphShapePattern pattern,
    Path path,
    Rect bounds,
  ) {
    switch (pattern) {
      case GraphShapePattern.none:
        return;
      case GraphShapePattern.diagonal:
        _drawLinePattern(canvas, path, bounds, _PatternLine.diagonal);
        return;
      case GraphShapePattern.reverseDiagonal:
        _drawLinePattern(canvas, path, bounds, _PatternLine.reverseDiagonal);
        return;
      case GraphShapePattern.crossHatch:
        _drawLinePattern(canvas, path, bounds, _PatternLine.diagonal);
        _drawLinePattern(canvas, path, bounds, _PatternLine.reverseDiagonal);
        return;
      case GraphShapePattern.horizontal:
        _drawLinePattern(canvas, path, bounds, _PatternLine.horizontal);
        return;
      case GraphShapePattern.vertical:
        _drawLinePattern(canvas, path, bounds, _PatternLine.vertical);
        return;
      case GraphShapePattern.grid:
        _drawLinePattern(canvas, path, bounds, _PatternLine.horizontal);
        _drawLinePattern(canvas, path, bounds, _PatternLine.vertical);
        return;
      case GraphShapePattern.dots:
        _drawDotPattern(canvas, path, bounds, spacing: 24, radius: 2.8);
        return;
      case GraphShapePattern.largeDots:
        _drawDotPattern(canvas, path, bounds, spacing: 34, radius: 4.2);
        return;
      case GraphShapePattern.checker:
        _drawCheckerPattern(canvas, path, bounds);
        return;
    }
  }

  void _drawLinePattern(
    Canvas canvas,
    Path path,
    Rect bounds,
    _PatternLine lineType,
  ) {
    canvas.save();
    canvas.clipPath(path);

    final patternPaint = Paint()
      ..color = const Color.fromRGBO(28, 43, 34, 0.16)
      ..strokeWidth = 2;
    switch (lineType) {
      case _PatternLine.diagonal:
        final startX = bounds.left - bounds.height;
        final endX = bounds.right + bounds.height;
        for (double x = startX; x <= endX; x += 22) {
          canvas.drawLine(
            Offset(x, bounds.bottom + 20),
            Offset(x + bounds.height + 40, bounds.top - 20),
            patternPaint,
          );
        }
        break;
      case _PatternLine.reverseDiagonal:
        final startX = bounds.left - bounds.height;
        final endX = bounds.right + bounds.height;
        for (double x = startX; x <= endX; x += 22) {
          canvas.drawLine(
            Offset(x, bounds.top - 20),
            Offset(x + bounds.height + 40, bounds.bottom + 20),
            patternPaint,
          );
        }
        break;
      case _PatternLine.horizontal:
        for (double y = bounds.top; y <= bounds.bottom; y += 22) {
          canvas.drawLine(
            Offset(bounds.left - 20, y),
            Offset(bounds.right + 20, y),
            patternPaint,
          );
        }
        break;
      case _PatternLine.vertical:
        for (double x = bounds.left; x <= bounds.right; x += 22) {
          canvas.drawLine(
            Offset(x, bounds.top - 20),
            Offset(x, bounds.bottom + 20),
            patternPaint,
          );
        }
        break;
    }

    canvas.restore();
  }

  void _drawDotPattern(
    Canvas canvas,
    Path path,
    Rect bounds, {
    required double spacing,
    required double radius,
  }) {
    canvas.save();
    canvas.clipPath(path);

    final dotPaint = Paint()..color = const Color.fromRGBO(28, 43, 34, 0.18);

    for (double x = bounds.left; x <= bounds.right; x += spacing) {
      for (double y = bounds.top; y <= bounds.bottom; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, dotPaint);
      }
    }

    canvas.restore();
  }

  void _drawCheckerPattern(Canvas canvas, Path path, Rect bounds) {
    canvas.save();
    canvas.clipPath(path);

    final checkerPaint = Paint()
      ..color = const Color.fromRGBO(28, 43, 34, 0.12);
    const size = 24.0;
    var row = 0;

    for (double y = bounds.top; y <= bounds.bottom; y += size) {
      var column = 0;
      for (double x = bounds.left; x <= bounds.right; x += size) {
        if ((row + column).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, size, size), checkerPaint);
        }
        column += 1;
      }
      row += 1;
    }

    canvas.restore();
  }

  void _drawShapeName(Canvas canvas, String name, Offset center) {
    if (name.trim().isEmpty) {
      return;
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Color(0xFFCC2000),
          fontSize: 15,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 220);
    final labelRect = Rect.fromCenter(
      center: center,
      width: textPainter.width + 18,
      height: textPainter.height + 10,
    );
    final labelRRect = RRect.fromRectAndRadius(
      labelRect,
      const Radius.circular(5),
    );

    canvas.drawRRect(
      labelRRect,
      Paint()..color = const Color(0xFFE6E6E6),
    );
    canvas.drawRRect(
      labelRRect,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke,
    );
    textPainter.paint(
      canvas,
      Offset(
        center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant GraphShapesPainter oldDelegate) {
    return oldDelegate.shapes != shapes ||
        oldDelegate.segments != segments ||
        oldDelegate.selectedShapeIndex != selectedShapeIndex ||
        oldDelegate.hoveredShapeIndex != hoveredShapeIndex;
  }
}

enum _PatternLine {
  diagonal,
  reverseDiagonal,
  horizontal,
  vertical,
}
