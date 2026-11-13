import '../models/trace_geometry.dart';
import 'measurement_service.dart';

/// Exclusions must be simple, disjoint polygons fully inside a simple boundary.
/// Rejecting invalid geometry prevents double deductions and outside acreage.
class TraceAreaService {
  static double excludedSquareMeters(TraceGeometry trace) =>
      trace.exclusions.fold(
          0,
          (sum, e) =>
              sum + MeasurementService.geodesicAreaSquareMeters(e.geoPoints));
  static double netSquareMeters(TraceGeometry trace) =>
      (MeasurementService.geodesicAreaSquareMeters(trace.geoPoints) -
              excludedSquareMeters(trace))
          .clamp(0, double.infinity);

  static String? validate(TraceGeometry trace) {
    if (!_simple(trace.geoPoints)) {
      return 'Trace a boundary with at least three distinct corners and no crossing edges.';
    }
    for (var i = 0; i < trace.exclusions.length; i++) {
      final e = trace.exclusions[i];
      if (!_simple(e.geoPoints)) {
        return '${e.label}: use at least three distinct corners with no crossing edges.';
      }
      if (e.geoPoints.any((p) => !_inside(p, trace.geoPoints)) ||
          _crosses(e.geoPoints, trace.geoPoints)) {
        return '${e.label}: keep the entire excluded area inside the boundary.';
      }
      for (final other in trace.exclusions.take(i)) {
        if (_crosses(e.geoPoints, other.geoPoints) ||
            _inside(e.geoPoints.first, other.geoPoints) ||
            _inside(other.geoPoints.first, e.geoPoints)) {
          return '${e.label} overlaps ${other.label}. Excluded areas must not overlap or touch.';
        }
      }
    }
    return null;
  }

  static bool _simple(List<GeoPoint> p) {
    if (p.length < 3 || MeasurementService.geodesicAreaSquareMeters(p) < 0.01) {
      return false;
    }
    for (var i = 0; i < p.length; i++) {
      final b = (i + 1) % p.length;
      if (MeasurementService.geodesicDistanceMeters(p[i], p[b]) < 0.01) {
        return false;
      }
      for (var j = i + 1; j < p.length; j++) {
        final d = (j + 1) % p.length;
        if (j == b || d == i) continue;
        if (_intersects(p[i], p[b], p[j], p[d])) return false;
      }
    }
    return true;
  }

  static bool _crosses(List<GeoPoint> a, List<GeoPoint> b) {
    for (var i = 0; i < a.length; i++) {
      for (var j = 0; j < b.length; j++) {
        if (_intersects(
            a[i], a[(i + 1) % a.length], b[j], b[(j + 1) % b.length])) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _intersects(GeoPoint a, GeoPoint b, GeoPoint c, GeoPoint d) {
    double cross(GeoPoint p, GeoPoint q, GeoPoint r) =>
        (q.longitude - p.longitude) * (r.latitude - p.latitude) -
        (q.latitude - p.latitude) * (r.longitude - p.longitude);
    bool on(GeoPoint p, GeoPoint q, GeoPoint r) =>
        r.longitude >=
            (p.longitude < q.longitude ? p.longitude : q.longitude) &&
        r.longitude <=
            (p.longitude > q.longitude ? p.longitude : q.longitude) &&
        r.latitude >= (p.latitude < q.latitude ? p.latitude : q.latitude) &&
        r.latitude <= (p.latitude > q.latitude ? p.latitude : q.latitude);
    final abC = cross(a, b, c),
        abD = cross(a, b, d),
        cdA = cross(c, d, a),
        cdB = cross(c, d, b);
    return (abC * abD < 0 && cdA * cdB < 0) ||
        (abC.abs() < 1e-16 && on(a, b, c)) ||
        (abD.abs() < 1e-16 && on(a, b, d)) ||
        (cdA.abs() < 1e-16 && on(c, d, a)) ||
        (cdB.abs() < 1e-16 && on(c, d, b));
  }

  static bool _inside(GeoPoint p, List<GeoPoint> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude <
              (b.longitude - a.longitude) *
                      (p.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }
}
