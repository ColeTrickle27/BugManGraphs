import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/graph_point.dart';
import '../editor/label_presentation.dart';
import '../models/wall_segment.dart';

@visibleForTesting
Offset wallMeasurementLabelCenter(
  WallSegment segment, {
  Offset? referencePoint,
}) {
  final start = segment.start.offset;
  final end = segment.end.offset;
  final dx = end.dx - start.dx;
  final dy = end.dy - start.dy;
  final length = math.sqrt((dx * dx) + (dy * dy));
  final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
  if (length == 0) {
    return midpoint;
  }
  final perpendicular = Offset(-dy / length, dx / length);
  // Keep the label clear of the line. The larger measurement tag is easier
  // to read when it consistently sits outside the structure rather than on
  // top of the drawing stroke.
  var labelCenter = midpoint + (perpendicular * 28);
  if (referencePoint != null) {
    final oppositeCenter = midpoint - (perpendicular * 28);
    if ((oppositeCenter - referencePoint).distanceSquared >
        (labelCenter - referencePoint).distanceSquared) {
      labelCenter = oppositeCenter;
    }
  }
  return labelCenter;
}

class WallSegmentsPainter extends CustomPainter {
  const WallSegmentsPainter({
    this.labels = const LabelPresentation(),
    required this.segments,
    required this.selectedSegmentIndex,
    this.hoveredSegmentIndex,
    required this.activeWallStart,
    required this.previewSegment,
    this.drawMeasurements = true,
    this.paintSegments = true,
    this.drawEndpoints = true,
    this.measurementReferencePoint,
    this.hiddenSegmentIndexes = const <int>{},
  });

  final List<WallSegment> segments;
  final LabelPresentation labels;
  final int? selectedSegmentIndex;
  final int? hoveredSegmentIndex;
  final GraphPoint? activeWallStart;
  final WallSegment? previewSegment;
  final bool drawMeasurements;
  final bool paintSegments;
  final bool drawEndpoints;
  final Offset? measurementReferencePoint;
  final Set<int> hiddenSegmentIndexes;

  @override
  void paint(Canvas canvas, Size size) {
    final wallOutlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9;
    if (paintSegments) {
      for (var i = 0; i < segments.length; i += 1) {
        if (hiddenSegmentIndexes.contains(i)) {
          continue;
        }

        final segment = segments[i];
        final curvePath = buildWallSegmentPath(segment);
        final wallPaint = Paint()
          ..color = segment.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = segment.strokeWidth;

        canvas.drawPath(curvePath, wallOutlinePaint);
        if (i == hoveredSegmentIndex && i != selectedSegmentIndex) {
          canvas.drawPath(
            curvePath,
            Paint()
              ..color = const Color(0xFF2F80ED).withValues(alpha: 0.42)
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = segment.strokeWidth + 8,
          );
        }
        _drawPatternedPath(canvas, curvePath, segment, wallPaint);
        if (segment.hasArrow) {
          _drawArrowHead(canvas, segment, wallPaint);
        }

        if (i == selectedSegmentIndex) {
          _drawSelectedSegment(canvas, segment);
        }
      }
    }

    for (var i = 0; i < segments.length; i += 1) {
      if (hiddenSegmentIndexes.contains(i)) {
        continue;
      }

      final segment = segments[i];
      if (drawEndpoints) {
        _drawEndpoint(canvas, segment.start, const Color(0xFF214D38));
        _drawEndpoint(canvas, segment.end, const Color(0xFF214D38));
      }
      if (drawMeasurements && !segment.hasArrow) {
        _drawMeasurementLabel(canvas, segment);
      }
    }

    final activePoint = activeWallStart;
    if (activePoint != null) {
      _drawEndpoint(canvas, activePoint, const Color(0xFFBC8A3D), radius: 8);
      _drawActiveStartLabel(canvas, activePoint);
    }

    final preview = previewSegment;
    if (preview != null) {
      _drawPreviewSegment(canvas, preview);
      if (drawMeasurements && !preview.hasArrow) {
        _drawMeasurementLabel(canvas, preview);
      }
    }
  }

  void _drawSelectedSegment(Canvas canvas, WallSegment segment) {
    final selectedPaint = Paint()
      ..color = const Color(0xFF2F80ED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(buildWallSegmentPath(segment), selectedPaint);
    _drawSelectionHandle(canvas, segment.start.offset);
    _drawSelectionHandle(canvas, segment.end.offset);

    final controlPoint = segment.controlPoint;
    if (controlPoint != null) {
      _drawSelectionHandle(canvas, controlPoint.offset);
    }
  }

  void _drawPatternedPath(
    Canvas canvas,
    Path path,
    WallSegment segment,
    Paint paint,
  ) {
    switch (segment.pattern) {
      case LinePattern.solid:
        canvas.drawPath(path, paint);
        return;
      case LinePattern.dashed:
        _drawDashedLine(canvas, segment, paint, dash: 24, gap: 14);
        return;
      case LinePattern.dottedSmall:
        _drawDottedLine(canvas, segment, paint, radius: 2.5, gap: 13);
        return;
      case LinePattern.dottedLarge:
        _drawDottedLine(canvas, segment, paint, radius: 4.5, gap: 18);
        return;
      case LinePattern.xMarks:
        _drawSymbolLine(canvas, segment, paint, symbol: _LineSymbol.x);
        return;
      case LinePattern.diamonds:
        _drawSymbolLine(canvas, segment, paint, symbol: _LineSymbol.diamond);
        return;
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    WallSegment segment,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final start = segment.start.offset;
    final end = segment.end.offset;
    final vector = end - start;
    final length = vector.distance;
    if (length == 0 || segment.isCurve) {
      canvas.drawPath(buildWallSegmentPath(segment), paint);
      return;
    }

    final direction = vector / length;
    var current = 0.0;
    while (current < length) {
      final dashEnd = math.min(current + dash, length);
      canvas.drawLine(
        start + (direction * current),
        start + (direction * dashEnd),
        paint,
      );
      current += dash + gap;
    }
  }

  void _drawDottedLine(
    Canvas canvas,
    WallSegment segment,
    Paint paint, {
    required double radius,
    required double gap,
  }) {
    final start = segment.start.offset;
    final end = segment.end.offset;
    final vector = end - start;
    final length = vector.distance;
    if (length == 0 || segment.isCurve) {
      canvas.drawPath(buildWallSegmentPath(segment), paint);
      return;
    }

    final direction = vector / length;
    for (var current = 0.0; current <= length; current += gap) {
      canvas.drawCircle(start + (direction * current), radius, paint);
    }
  }

  void _drawSymbolLine(
    Canvas canvas,
    WallSegment segment,
    Paint paint, {
    required _LineSymbol symbol,
  }) {
    final start = segment.start.offset;
    final end = segment.end.offset;
    final vector = end - start;
    final length = vector.distance;
    if (length == 0 || segment.isCurve) {
      canvas.drawPath(buildWallSegmentPath(segment), paint);
      return;
    }

    final direction = vector / length;
    final normal = Offset(-direction.dy, direction.dx);
    for (var current = 12.0; current < length; current += 26) {
      final center = start + (direction * current);
      if (symbol == _LineSymbol.x) {
        canvas.drawLine(
          center - (direction * 6) - (normal * 6),
          center + (direction * 6) + (normal * 6),
          paint,
        );
        canvas.drawLine(
          center - (direction * 6) + (normal * 6),
          center + (direction * 6) - (normal * 6),
          paint,
        );
      } else {
        final path = Path()
          ..moveTo((center - (direction * 7)).dx, (center - (direction * 7)).dy)
          ..lineTo((center + (normal * 6)).dx, (center + (normal * 6)).dy)
          ..lineTo((center + (direction * 7)).dx, (center + (direction * 7)).dy)
          ..lineTo((center - (normal * 6)).dx, (center - (normal * 6)).dy)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawArrowHead(Canvas canvas, WallSegment segment, Paint paint) {
    final end = segment.end.offset;
    final start = segment.controlPoint?.offset ?? segment.start.offset;
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final length = (end - start).distance;
    final size = math.min(18.0, math.max(7.0, length * 0.42));
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - (math.cos(angle - math.pi / 6) * size),
        end.dy - (math.sin(angle - math.pi / 6) * size),
      )
      ..lineTo(
        end.dx - (math.cos(angle + math.pi / 6) * size),
        end.dy - (math.sin(angle + math.pi / 6) * size),
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );
  }

  void _drawPreviewSegment(Canvas canvas, WallSegment segment) {
    final previewPaint = Paint()
      ..color = segment.color.withValues(alpha: 0.72)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = segment.strokeWidth;
    final endpointPaint = Paint()
      ..color = segment.color.withValues(alpha: 0.86);

    _drawPatternedPath(
      canvas,
      buildWallSegmentPath(segment),
      segment,
      previewPaint,
    );
    if (segment.hasArrow) {
      _drawArrowHead(canvas, segment, previewPaint);
    }
    canvas.drawCircle(segment.end.offset, 5, endpointPaint);
  }

  void _drawSelectionHandle(Canvas canvas, Offset center) {
    final rect = Rect.fromCenter(center: center, width: 12, height: 12);

    canvas.drawRect(rect, Paint()..color = Colors.white);
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF2F80ED)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawEndpoint(
    Canvas canvas,
    GraphPoint point,
    Color color, {
    double radius = 6,
  }) {
    final fillPaint = Paint()..color = Colors.white;
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(point.offset, radius, fillPaint);
    canvas.drawCircle(point.offset, radius, borderPaint);
  }

  void _drawMeasurementLabel(Canvas canvas, WallSegment segment) {
    final start = segment.start.offset;
    final end = segment.end.offset;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt((dx * dx) + (dy * dy));

    if (length == 0) {
      return;
    }

    var labelCenter = wallMeasurementLabelCenter(
      segment,
      referencePoint: measurementReferencePoint,
    );
    final textPainter = TextPainter(
      text: TextSpan(
        text: segment.measurementLabel,
        style: TextStyle(
          color: const Color(0xFF173C2B),
          fontSize: labels.fontSize(17),
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelRect = Rect.fromCenter(
      center: labelCenter,
      width: textPainter.width + 20,
      height: textPainter.height + 12,
    );
    final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final outward = labelCenter - midpoint;
    final normal = outward / outward.distance;
    final labelHalfExtent = (labelRect.width / 2) * normal.dx.abs() +
        (labelRect.height / 2) * normal.dy.abs();
    final minimumDistance = labelHalfExtent + 12;
    if (outward.distance < minimumDistance) {
      labelCenter = midpoint + (normal * minimumDistance);
    }
    final adjustedLabelRect = Rect.fromCenter(
      center: labelCenter,
      width: labelRect.width,
      height: labelRect.height,
    );
    final labelRRect = RRect.fromRectAndRadius(
      adjustedLabelRect,
      Radius.circular(adjustedLabelRect.height / 2),
    );
    final labelPath = Path()..addRRect(labelRRect);
    canvas.drawLine(
      midpoint + (normal * 6),
      labelCenter - (normal * labelHalfExtent),
      Paint()
        ..color = const Color(0xFF3E6752).withValues(alpha: 0.72)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawShadow(
      labelPath,
      Colors.black.withValues(alpha: 0.22),
      2,
      false,
    );
    canvas.drawRRect(
      labelRRect,
      Paint()..color = Colors.white.withValues(alpha: 0.97),
    );
    canvas.drawRRect(
      labelRRect,
      Paint()
        ..color = const Color(0xFF3E6752)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    textPainter.paint(
      canvas,
      Offset(
        labelCenter.dx - (textPainter.width / 2),
        labelCenter.dy - (textPainter.height / 2),
      ),
    );
  }

  void _drawActiveStartLabel(Canvas canvas, GraphPoint point) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Start',
        style: TextStyle(
          color: Color(0xFF1C2B22),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = point.offset + const Offset(0, -24);
    final labelRect = Rect.fromCenter(
      center: center,
      width: textPainter.width + 14,
      height: textPainter.height + 8,
    );
    final labelRRect = RRect.fromRectAndRadius(
      labelRect,
      const Radius.circular(5),
    );

    canvas.drawRRect(labelRRect, Paint()..color = const Color(0xFFFFF2B8));
    canvas.drawRRect(
      labelRRect,
      Paint()
        ..color = const Color(0xFFC7A93C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
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
  bool shouldRepaint(covariant WallSegmentsPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.selectedSegmentIndex != selectedSegmentIndex ||
        oldDelegate.hoveredSegmentIndex != hoveredSegmentIndex ||
        oldDelegate.activeWallStart != activeWallStart ||
        oldDelegate.previewSegment != previewSegment ||
        oldDelegate.drawMeasurements != drawMeasurements ||
        oldDelegate.hiddenSegmentIndexes != hiddenSegmentIndexes;
  }
}

@visibleForTesting
Path buildWallSegmentPath(WallSegment segment) {
  final path = Path()..moveTo(segment.start.x, segment.start.y);
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
  return path;
}

enum _LineSymbol {
  x,
  diamond,
}
