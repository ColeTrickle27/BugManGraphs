import 'dart:math' as math;
import 'dart:ui';

import '../models/trace_geometry.dart';

/// Display-only dimensions. Never changes geographic points or calibration.
class TracePresentation {
  const TracePresentation._();

  static Rect? bounds(Iterable<TraceGeometry> traces) {
    Rect? result;
    for (final trace in traces) {
      for (final point in trace.canvasPoints) {
        final rect = Rect.fromLTWH(point.x, point.y, 0, 0);
        result = result == null ? rect : result.expandToInclude(rect);
      }
    }
    return result;
  }

  // At fit-to-page, keep 17-unit lettering approximately 11–13pt on
  // landscape letter paper instead of shrinking it with the property.
  static double labelScale(Iterable<TraceGeometry> traces) {
    final rect = bounds(traces);
    if (rect == null) return 1;
    return math.max(1, math.max(rect.width / 800, rect.height / 500));
  }

  static Rect? paintedBounds(Iterable<TraceGeometry> traces) =>
      bounds(traces)?.inflate(120 * labelScale(traces));

  static Rect sceneBounds(Size baseSize, Iterable<TraceGeometry> traces) {
    final base = Offset.zero & baseSize;
    final traceBounds = paintedBounds(traces);
    return traceBounds == null ? base : base.expandToInclude(traceBounds);
  }
}
