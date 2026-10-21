import 'dart:math' as math;
import 'dart:ui';
import '../models/wall_segment.dart';

/// Derived geometry only: never changes saved vertices or calibration.
abstract final class CurveMeasurements {
  /// Adaptive flattening bounds hit-test error to a quarter canvas unit.
  static double distanceTo(WallSegment s, Offset point) {
    double line(Offset a, Offset b, Offset p) {
      final delta = b - a;
      if (delta.distanceSquared == 0) return (p - a).distance;
      final relative = p - a;
      final t = ((relative.dx * delta.dx + relative.dy * delta.dy) /
              delta.distanceSquared)
          .clamp(0.0, 1.0);
      return (p - (a + delta * t)).distance;
    }

    double curve(Offset a, Offset c, Offset b, int depth) {
      if (depth == 0 || line(a, b, c) <= .25) return line(a, b, point);
      final ac = (a + c) / 2, cb = (c + b) / 2;
      final midpoint = (ac + cb) / 2;
      return math.min(
          curve(a, ac, midpoint, depth - 1), curve(midpoint, cb, b, depth - 1));
    }

    return s.controlPoint == null
        ? line(s.start.offset, s.end.offset, point)
        : curve(s.start.offset, s.controlPoint!.offset, s.end.offset, 16);
  }

  static double length(WallSegment s) {
    final c = s.controlPoint;
    if (c == null) return s.start.distanceTo(s.end);
    double speed(double t) =>
        2 *
        math.sqrt(
            math.pow((1 - t) * (c.x - s.start.x) + t * (s.end.x - c.x), 2) +
                math.pow((1 - t) * (c.y - s.start.y) + t * (s.end.y - c.y), 2));
    double integrate(double a, double b, double fa, double fm, double fb,
        double whole, double tolerance, int depth) {
      final mid = (a + b) / 2;
      final fl = speed((a + mid) / 2), fr = speed((mid + b) / 2);
      final left = (mid - a) * (fa + 4 * fl + fm) / 6;
      final right = (b - mid) * (fm + 4 * fr + fb) / 6;
      final delta = left + right - whole;
      if (depth == 0 || delta.abs() <= 15 * tolerance) {
        return left + right + delta / 15;
      }
      return integrate(a, mid, fa, fl, fm, left, tolerance / 2, depth - 1) +
          integrate(mid, b, fm, fr, fb, right, tolerance / 2, depth - 1);
    }

    final fa = speed(0), fm = speed(.5), fb = speed(1);
    return integrate(0, 1, fa, fm, fb, (fa + 4 * fm + fb) / 6, 1e-8, 20);
  }

  /// Exact Green integral for ordered straight/quadratic closed boundaries.
  static double areaPixels(Iterable<WallSegment> segments) {
    var integral = 0.0;
    for (final s in segments) {
      final c = s.controlPoint;
      if (c == null) {
        integral += s.start.x * s.end.y - s.end.x * s.start.y;
      } else {
        final ax = s.start.x - 2 * c.x + s.end.x;
        final ay = s.start.y - 2 * c.y + s.end.y;
        final bx = 2 * (c.x - s.start.x), by = 2 * (c.y - s.start.y);
        integral += (bx * ay - ax * by) / 3 +
            s.start.x * ay -
            ax * s.start.y +
            s.start.x * by -
            bx * s.start.y;
      }
    }
    return integral.abs() / 2;
  }
}
