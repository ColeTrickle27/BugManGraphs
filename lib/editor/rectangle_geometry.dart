import 'dart:ui';
import '../models/graph_point.dart';
import '../models/wall_segment.dart';

/// Rectangle edge edits keep both neighbouring walls perpendicular, including
/// rotated rectangles. The opposite edge stays fixed.
class RectangleGeometry {
  static bool isRectangle(List<WallSegment> segments) {
    if (segments.length != 4 || segments.any((s) => s.isCurve)) return false;
    for (var i = 0; i < 4; i++) {
      final a = segments[i];
      final b = segments[(i + 1) % 4];
      if (a.end.distanceTo(b.start) > 0.01) return false;
      final av = a.end.offset - a.start.offset;
      final bv = b.end.offset - b.start.offset;
      if (av.distance < 1 ||
          bv.distance < 1 ||
          (av.dx * bv.dx + av.dy * bv.dy).abs() >
              av.distance * bv.distance * 0.001) {
        return false;
      }
    }
    return true;
  }

  static List<WallSegment> moveEdge(
      List<WallSegment> segments, int edge, Offset delta) {
    if (!isRectangle(segments)) return segments;
    final a = segments[edge].start.offset;
    final b = segments[edge].end.offset;
    final tangent = (b - a) / (b - a).distance;
    final normal = Offset(-tangent.dy, tangent.dx);
    final amount = delta.dx * normal.dx + delta.dy * normal.dy;
    final opposite = segments[(edge + 2) % 4].start.offset - a;
    final thickness = opposite.dx * normal.dx + opposite.dy * normal.dy;
    if ((thickness - amount) * thickness.sign < 24) return segments;
    final points = segments.map((s) => s.start.offset).toList();
    points[edge] += normal * amount;
    points[(edge + 1) % 4] += normal * amount;
    return [
      for (var i = 0; i < 4; i++)
        segments[i].copyWith(
          start: GraphPoint.fromOffset(points[i]),
          end: GraphPoint.fromOffset(points[(i + 1) % 4]),
        )
    ];
  }
}
