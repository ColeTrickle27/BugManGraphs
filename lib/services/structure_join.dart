import '../models/graph_point.dart';
import '../models/wall_segment.dart';

GraphPoint projectOntoStraightEdge(GraphPoint point, WallSegment edge) {
  final dx = edge.end.x - edge.start.x, dy = edge.end.y - edge.start.y;
  final length = dx * dx + dy * dy;
  final t = length == 0
      ? 0.0
      : (((point.x - edge.start.x) * dx + (point.y - edge.start.y) * dy) /
              length)
          .clamp(0.0, 1.0);
  return GraphPoint(x: edge.start.x + t * dx, y: edge.start.y + t * dy);
}

/// Copy the existing ring boundary between two joins without mutating it.
/// Curved existing boundaries require an explicit split operation and are
/// deliberately excluded rather than replaced with inaccurate chords.
List<WallSegment>? structureBoundaryBetween(
    List<WallSegment> edges, GraphPoint from, GraphPoint to) {
  final forward = _forwardBoundaryBetween(edges, from, to);
  final reverse = _forwardBoundaryBetween(
      edges.reversed
          .map((e) => e.copyWith(start: e.end, end: e.start))
          .toList(),
      from,
      to);
  if (forward == null) return reverse;
  if (reverse == null) return forward;
  double length(List<WallSegment> list) =>
      list.fold(0, (sum, e) => sum + e.lengthPixels);
  return length(forward) <= length(reverse) ? forward : reverse;
}

List<WallSegment>? _forwardBoundaryBetween(
    List<WallSegment> edges, GraphPoint from, GraphPoint to) {
  if (edges.isEmpty || edges.any((s) => s.isCurve)) return null;
  int edgeAt(GraphPoint p) => edges
      .indexWhere((e) => projectOntoStraightEdge(p, e).distanceTo(p) < 0.01);
  final first = edgeAt(from), last = edgeAt(to);
  if (first < 0 || last < 0) return null;
  final result = <WallSegment>[];
  var current = from;
  for (var step = 0; step <= edges.length; step++) {
    final index = (first + step) % edges.length;
    final edge = edges[index];
    final toAhead = (to.x - current.x) * (edge.end.x - edge.start.x) +
            (to.y - current.y) * (edge.end.y - edge.start.y) >=
        -1e-8;
    if (index == last && (step > 0 || toAhead)) {
      if (current.distanceTo(to) > 0.01) {
        result.add(edge.copyWith(start: current, end: to));
      }
      return result;
    }
    if (current.distanceTo(edge.end) > 0.01) {
      result.add(edge.copyWith(start: current));
    }
    current = edge.end;
  }
  return null;
}
