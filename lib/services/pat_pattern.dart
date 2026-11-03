import 'dart:math' as math;
import 'dart:ui';

/// AutoCAD PAT definitions are data, never executable PostScript.
class PatPattern {
  const PatPattern(this.name, this.original, this.lines);
  final String name;
  final String original;
  final List<PatLine> lines;

  /// Native line/dot geometry anchored to the drawing origin, shared by
  /// canvas and export. Negative dashes are gaps; zero dashes are points.
  void paint(Canvas canvas, Path clip, Paint paint,
      {double unitsPerPatternUnit = 1}) {
    if (!unitsPerPatternUnit.isFinite || unitsPerPatternUnit <= 0) {
      throw ArgumentError.value(unitsPerPatternUnit);
    }
    final worldBounds = clip.getBounds().intersect(canvas.getLocalClipBounds());
    if (worldBounds.isEmpty) return;
    final bounds = Rect.fromLTRB(
        worldBounds.left / unitsPerPatternUnit,
        worldBounds.top / unitsPerPatternUnit,
        worldBounds.right / unitsPerPatternUnit,
        worldBounds.bottom / unitsPerPatternUnit);
    canvas.save();
    canvas.clipPath(clip);
    canvas.scale(unitsPerPatternUnit);
    for (final stroke in strokes(bounds)) {
      if (stroke.start == stroke.end) {
        canvas.drawCircle(
            stroke.start, paint.strokeWidth / 2, Paint()..color = paint.color);
      } else {
        canvas.drawLine(stroke.start, stroke.end, paint);
      }
    }
    canvas.restore();
  }

  List<PatStroke> strokes(Rect bounds, {int budget = 100000}) {
    final result = <PatStroke>[];
    void add(Offset start, Offset end) {
      if (result.length >= budget) {
        throw StateError('PAT geometry exceeds rendering budget');
      }
      result.add(PatStroke(start, end));
    }

    for (final line in lines) {
      final d = line.direction;
      final n = Offset(-d.dy, d.dx);
      double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
      final corners = [
        bounds.topLeft,
        bounds.topRight,
        bounds.bottomLeft,
        bounds.bottomRight
      ];
      final rows = corners
          .map((p) => dot(p - line.origin, n) / line.offset.dy)
          .toList()
        ..sort();
      if (rows.last.ceil() - rows.first.floor() > budget) {
        throw StateError('PAT row budget exceeded');
      }
      for (var row = rows.first.floor(); row <= rows.last.ceil(); row++) {
        final origin = line.originFor(row);
        final range = corners.map((p) => dot(p - origin, d)).toList()..sort();
        if (line.dashes.isEmpty) {
          add(origin + d * range.first, origin + d * range.last);
          continue;
        }
        final period = line.dashes.fold<double>(0, (sum, v) => sum + v.abs());
        if (period <= 0) {
          throw const FormatException('PAT dash period must be positive');
        }
        if ((range.last - range.first) / period > budget) {
          throw StateError('PAT dash budget exceeded');
        }
        for (var cycle = (range.first / period).floor();
            cycle <= (range.last / period).ceil();
            cycle++) {
          var t = cycle * period;
          for (final dash in line.dashes) {
            if (dash >= 0 && t + dash >= range.first && t <= range.last) {
              add(origin + d * math.max(t, range.first),
                  origin + d * math.min(t + dash, range.last));
            }
            t += dash.abs();
          }
        }
      }
    }
    return result;
  }

  factory PatPattern.parse(String source) {
    String? name;
    final lines = <PatLine>[];
    for (final raw in source.split('\n')) {
      final line = raw.split(';').first.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('*')) {
        if (name != null) throw const FormatException('One pattern per file');
        name = line.substring(1).split(',').first.trim();
        continue;
      }
      final values =
          line.split(',').map((v) => double.parse(v.trim())).toList();
      if (values.length < 5 || values.any((v) => !v.isFinite)) {
        throw const FormatException('Invalid PAT line');
      }
      if (values[4] == 0) throw const FormatException('Zero line spacing');
      lines.add(PatLine(values[0], Offset(values[1], values[2]),
          Offset(values[3], values[4]), values.skip(5).toList()));
    }
    if (name == null || name.isEmpty || lines.isEmpty) {
      throw const FormatException('Missing PAT definition');
    }
    return PatPattern(name, source, List.unmodifiable(lines));
  }
}

class PatStroke {
  const PatStroke(this.start, this.end);
  final Offset start;
  final Offset end;
}

class PatLine {
  const PatLine(this.angle, this.origin, this.offset, this.dashes);
  final double angle;
  final Offset origin;

  /// PAT offsets use the rotated line coordinate system.
  final Offset offset;
  final List<double> dashes;
  Offset get direction =>
      Offset(math.cos(angle * math.pi / 180), math.sin(angle * math.pi / 180));
  Offset get worldOffset => Offset(
      direction.dx * offset.dx - direction.dy * offset.dy,
      direction.dy * offset.dx + direction.dx * offset.dy);
  Offset originFor(int row) => origin + worldOffset * row.toDouble();
}
