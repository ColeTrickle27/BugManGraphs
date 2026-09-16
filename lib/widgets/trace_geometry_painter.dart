import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/trace_geometry.dart';
import '../models/graph_point.dart';
import '../services/trace_presentation.dart';
import '../services/measurement_format.dart';
import '../services/measurement_service.dart';
import '../services/trace_projection_service.dart';

class TraceGeometryPainter extends CustomPainter {
  const TraceGeometryPainter({
    required this.traces,
    this.selectedTraceIndex,
    this.hoveredTraceIndex,
  });

  final List<TraceGeometry> traces;
  final int? selectedTraceIndex;
  final int? hoveredTraceIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final displayScale = TracePresentation.labelScale(traces);
    canvas.save();
    canvas.scale(displayScale);
    for (var traceIndex = 0; traceIndex < traces.length; traceIndex += 1) {
      final source = traces[traceIndex];
      // This temporary paint view leaves every vertex in the same world
      // location while text is sized independently of geographic measurements.
      final trace = source.copyWith(
        canvasPoints: [
          for (final p in source.canvasPoints)
            GraphPoint(x: p.x / displayScale, y: p.y / displayScale)
        ],
        metersPerCanvasUnit: source.metersPerCanvasUnit == null
            ? null
            : source.metersPerCanvasUnit! * displayScale,
      );
      final selected = traceIndex == selectedTraceIndex;
      final hovered = traceIndex == hoveredTraceIndex;
      if (trace.canvasPoints.length < 2) continue;
      final path = Path()
        ..moveTo(trace.canvasPoints.first.x, trace.canvasPoints.first.y);
      for (final point in trace.canvasPoints.skip(1)) {
        path.lineTo(point.x, point.y);
      }
      if (trace.closed && trace.canvasPoints.length >= 3) path.close();
      if (trace.closed) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0x223B82F6)
            ..style = PaintingStyle.fill,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = selected
              ? const Color(0xFF1976D2)
              : hovered
                  ? const Color(0xFFFF6F00)
                  : const Color(0xFFCC2000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 7 : 5
          ..strokeJoin = StrokeJoin.round,
      );
      for (final point in trace.canvasPoints) {
        canvas.drawCircle(
          point.offset,
          selected ? 10 : 7,
          Paint()
            ..color =
                selected ? const Color(0xFF1976D2) : const Color(0xFFCC2000),
        );
      }
      _drawSegmentMeasurements(canvas, trace);
      _drawSummary(canvas, trace);
      _drawScaleBar(canvas, trace);
      if (selected) _drawRotationHandle(canvas, trace);
    }
    canvas.restore();
  }

  static Rect? canvasBounds(TraceGeometry trace) {
    if (trace.canvasPoints.isEmpty) return null;
    final left = trace.canvasPoints.map((point) => point.x).reduce(math.min);
    final right = trace.canvasPoints.map((point) => point.x).reduce(math.max);
    final top = trace.canvasPoints.map((point) => point.y).reduce(math.min);
    final bottom = trace.canvasPoints.map((point) => point.y).reduce(math.max);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Offset? rotationHandleCenter(TraceGeometry trace,
      {double displayScale = 1}) {
    final bounds = canvasBounds(trace);
    return bounds == null
        ? null
        : bounds.topCenter - Offset(0, 42 * displayScale);
  }

  void _drawSegmentMeasurements(Canvas canvas, TraceGeometry trace) {
    final pointCount = trace.canvasPoints.length < trace.geoPoints.length
        ? trace.canvasPoints.length
        : trace.geoPoints.length;
    if (pointCount < 2) return;
    final edgeCount =
        trace.closed && pointCount > 2 ? pointCount : pointCount - 1;
    final center = Offset(
      trace.canvasPoints
              .take(pointCount)
              .map((point) => point.x)
              .reduce((a, b) => a + b) /
          pointCount,
      trace.canvasPoints
              .take(pointCount)
              .map((point) => point.y)
              .reduce((a, b) => a + b) /
          pointCount,
    );

    final placedLabelRects = <Rect>[];
    for (var index = 0; index < edgeCount; index += 1) {
      final nextIndex = (index + 1) % pointCount;
      final start = trace.canvasPoints[index].offset;
      final end = trace.canvasPoints[nextIndex].offset;
      final segment = end - start;
      final segmentLength = segment.distance;
      if (segmentLength <= 0.01) continue;

      final midpoint = Offset(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2,
      );
      var normal =
          Offset(-segment.dy / segmentLength, segment.dx / segmentLength);
      final towardMidpoint = midpoint - center;
      if ((normal.dx * towardMidpoint.dx) + (normal.dy * towardMidpoint.dy) <
          0) {
        normal = Offset(-normal.dx, -normal.dy);
      }

      final linearFeet = MeasurementService.geodesicDistanceMeters(
            trace.geoPoints[index],
            trace.geoPoints[nextIndex],
          ) *
          3.280839895013123;
      final label = TextPainter(
        text: TextSpan(
          text: MeasurementFormat.linearFeet(linearFeet),
          style: const TextStyle(
            color: Color(0xFF0F3D77),
            fontFamily: 'Roboto',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const horizontalPadding = 10.0;
      const verticalPadding = 6.0;
      final labelWidth = label.width + (horizontalPadding * 2);
      final labelHeight = label.height + (verticalPadding * 2);
      final labelHalfExtent = (labelWidth / 2) * normal.dx.abs() +
          (labelHeight / 2) * normal.dy.abs();
      var labelCenter = midpoint + (normal * (labelHalfExtent + 12));
      var labelRect = Rect.fromCenter(
        center: labelCenter,
        width: labelWidth,
        height: labelHeight,
      );
      // Compact or irregular traces can place neighboring labels near the
      // same corner. Keep each tag moving outward from its edge until it
      // reads as a distinct, orderly callout.
      while (placedLabelRects.any(
            (placed) => placed.inflate(4).overlaps(labelRect),
          ) &&
          (labelCenter - midpoint).distance < 92) {
        labelCenter += normal * 14;
        labelRect = Rect.fromCenter(
          center: labelCenter,
          width: labelWidth,
          height: labelHeight,
        );
      }
      placedLabelRects.add(labelRect);
      final labelRRect = RRect.fromRectAndRadius(
        labelRect,
        Radius.circular(labelRect.height / 2),
      );
      final labelPath = Path()..addRRect(labelRRect);
      canvas.drawLine(
        midpoint + (normal * 6),
        labelCenter - (normal * labelHalfExtent),
        Paint()
          ..color = const Color(0xFF2B6CB0).withValues(alpha: 0.72)
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
          ..color = const Color(0xFF2B6CB0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      label.paint(
        canvas,
        labelRect.topLeft + const Offset(horizontalPadding, verticalPadding),
      );
    }
  }

  void _drawSummary(Canvas canvas, TraceGeometry trace) {
    final measurement = MeasurementService.measureTrace(
      trace,
      status: MeasurementAccuracyStatus.estimated,
    );
    final center = Offset(
      trace.canvasPoints.map((point) => point.x).reduce((a, b) => a + b) /
          trace.canvasPoints.length,
      trace.canvasPoints.map((point) => point.y).reduce((a, b) => a + b) /
          trace.canvasPoints.length,
    );
    final text = TextPainter(
      text: TextSpan(
        text: '${trace.label}\n'
            '${MeasurementFormat.linearFeet(measurement.linearFeet)} • '
            '${MeasurementFormat.squareFeet(measurement.squareFeet)} • '
            '${MeasurementFormat.acres(measurement.acres)}',
        style: const TextStyle(
          color: Color(0xFF0E3056),
          fontFamily: 'Roboto',
          fontSize: 17,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 320);
    final rect = Rect.fromCenter(
      center: center,
      width: text.width + 28,
      height: text.height + 18,
    );
    final summaryRRect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(10),
    );
    final summaryPath = Path()..addRRect(summaryRRect);
    canvas.drawShadow(
      summaryPath,
      Colors.black.withValues(alpha: 0.18),
      2,
      false,
    );
    canvas.drawRRect(
      summaryRRect,
      Paint()..color = Colors.white.withValues(alpha: 0.96),
    );
    canvas.drawRRect(
      summaryRRect,
      Paint()
        ..color = const Color(0xFF2B6CB0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    text.paint(canvas, rect.topLeft + const Offset(14, 9));
  }

  void _drawScaleBar(Canvas canvas, TraceGeometry trace) {
    final metersPerCanvasUnit = trace.metersPerCanvasUnit;
    if (metersPerCanvasUnit == null || metersPerCanvasUnit <= 0) return;
    final feet = TraceProjectionService.scaleBarFeet(metersPerCanvasUnit);
    final width = feet / (metersPerCanvasUnit * 3.280839895013123);
    final left = trace.canvasPoints.map((point) => point.x).reduce(math.min);
    final top = trace.canvasPoints.map((point) => point.y).reduce(math.min);
    final start = Offset(left, top - 54);
    final end = start + Offset(width, 0);
    final paint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 4;
    canvas.drawLine(start, end, paint);
    canvas.drawLine(
        start - const Offset(0, 8), start + const Offset(0, 8), paint);
    canvas.drawLine(end - const Offset(0, 8), end + const Offset(0, 8), paint);
    final label = TextPainter(
      text: TextSpan(
        text: '${feet.round()} ft',
        style: const TextStyle(
          color: Color(0xFF0E3056),
          fontFamily: 'Roboto',
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelRect = Rect.fromCenter(
      center: Offset((start.dx + end.dx) / 2, start.dy - 21),
      width: label.width + 14,
      height: label.height + 8,
    );
    final labelRRect = RRect.fromRectAndRadius(
      labelRect,
      Radius.circular(labelRect.height / 2),
    );
    canvas.drawRRect(
      labelRRect,
      Paint()..color = Colors.white.withValues(alpha: 0.96),
    );
    canvas.drawRRect(
      labelRRect,
      Paint()
        ..color = const Color(0xFF2B6CB0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25,
    );
    label.paint(canvas, labelRect.topLeft + const Offset(7, 4));
  }

  void _drawRotationHandle(Canvas canvas, TraceGeometry trace) {
    final bounds = canvasBounds(trace);
    final handleCenter = rotationHandleCenter(trace);
    if (bounds == null || handleCenter == null) return;
    final paint = Paint()
      ..color = const Color(0xFF1976D2)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(bounds.topCenter, handleCenter, paint);
    canvas.drawCircle(
      handleCenter,
      13,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(handleCenter, 13, paint);
    canvas.drawArc(
      Rect.fromCircle(center: handleCenter, radius: 7),
      -math.pi / 3,
      math.pi * 1.45,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant TraceGeometryPainter oldDelegate) =>
      oldDelegate.traces != traces ||
      oldDelegate.selectedTraceIndex != selectedTraceIndex ||
      oldDelegate.hoveredTraceIndex != hoveredTraceIndex;
}
