import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/graph_annotation.dart';
import '../models/graph_document.dart';
import '../models/graph_marker_catalog.dart';
import '../models/graph_shape.dart';
import '../models/wall_segment.dart';
import 'measurement_format.dart';
import 'measurement_service.dart';

class PdfDiagramLabel {
  const PdfDiagramLabel(this.text, this.rect, this.anchor,
      {this.fontSize = 8.5,
      this.color = PdfColors.grey900,
      this.callout = false});
  final String text;
  final Rect rect;
  final Offset anchor;
  final double fontSize;
  final PdfColor color;
  final bool callout;
}

/// Print coordinates and typography are independent of viewport zoom. Stored
/// geometry and the existing measurement calculations remain the source of truth.
class GraphPdfDiagram {
  GraphPdfDiagram(this.document, this.width, this.height, this.font,
      {this.icons = const {}}) {
    final points = <Offset>[
      for (final s in visibleSegments) ...[
        s.start.offset,
        s.end.offset,
        if (s.controlPoint != null) s.controlPoint!.offset
      ],
      for (final a in visibleAnnotations) ...[
        a.point.offset,
        if (_tip(a) != null) _tip(a)!
      ],
      if (document.layer('structure').visible)
        for (final stroke in document.freehandStrokes)
          ...stroke.points.map((p) => p.offset),
      if (document.layer('trace').visible)
        for (final trace in document.traces)
          ...trace.canvasPoints.map((p) => p.offset),
    ];
    bounds = points.isEmpty
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : Rect.fromLTRB(
            points.map((p) => p.dx).reduce(math.min),
            points.map((p) => p.dy).reduce(math.min),
            points.map((p) => p.dx).reduce(math.max),
            points.map((p) => p.dy).reduce(math.max));
    const inset = 42.0;
    scale = math.min(math.max(1, width - 2 * inset) / math.max(1, bounds.width),
        math.max(1, height - 2 * inset) / math.max(1, bounds.height));
    offset = Offset((width - bounds.width * scale) / 2 - bounds.left * scale,
        (height - bounds.height * scale) / 2 - bounds.top * scale);
    _prepareLabels();
  }
  final GraphDocument document;
  final double width, height;
  final PdfFont font;
  final Map<String, Uint8List> icons;
  late final Rect bounds;
  late final double scale;
  late final Offset offset;
  final labels = <PdfDiagramLabel>[];
  final _icons = <Rect>[];
  final _lines = <(Offset, Offset)>[];
  final _treatmentAreas = <Rect>[];
  Rect get area => Rect.fromLTWH(6, 6, width - 12, height - 12);
  Offset project(Offset p) => p * scale + offset;
  bool _shapeVisible(GraphShape s) =>
      document.layer('structure').visible &&
      document.layer('shapes').visible &&
      (s.preset != GraphDrawingPreset.treatmentArea ||
          document.layer('treatment').visible);
  Iterable<GraphShape> get visibleShapes =>
      document.shapes.where(_shapeVisible);
  Iterable<WallSegment> get visibleSegments {
    final owned = document.shapes.expand((s) => s.segmentIndexes).toSet();
    final visible = visibleShapes.expand((s) => s.segmentIndexes).toSet();
    return [
      for (var i = 0; i < document.wallSegments.length; i++)
        if (visible.contains(i) ||
            (!owned.contains(i) && document.layer('structure').visible))
          document.wallSegments[i]
    ];
  }

  Iterable<GraphAnnotation> get visibleAnnotations =>
      document.annotations.where((a) => switch (a.kind) {
            GraphAnnotationKind.photo => document.layer('photos').visible,
            GraphAnnotationKind.text => document.layer('inspections').visible,
            GraphAnnotationKind.marker when isTreatmentMarker(a.markerType) =>
              document.layer('treatment').visible,
            GraphAnnotationKind.marker
                when utilityMarkerTypes.contains(a.markerType) =>
              document.layer('structure').visible,
            GraphAnnotationKind.marker => document.layer('inspections').visible,
          });
  static Offset? _tip(GraphAnnotation a) {
    final x = a.extraProperties['calloutTipX'],
        y = a.extraProperties['calloutTipY'];
    return x is num && y is num ? Offset(x.toDouble(), y.toDouble()) : null;
  }

  static String iconKey(GraphAnnotation a) => a.kind ==
          GraphAnnotationKind.photo
      ? 'photo'
      : '${a.markerType.name}:${(a.color ?? a.markerType.defaultColor).toARGB32()}';
  double _measure(String text, double size) =>
      font.stringMetrics(text).width * size;
  String _wrap(String text, double limit, double size) {
    final lines = <String>[];
    for (final paragraph in text.split('\n')) {
      var line = '';
      for (var word
          in paragraph.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
        if (_measure(word, size) > limit) {
          if (line.isNotEmpty) {
            lines.add(line);
            line = '';
          }
          var chunk = '';
          for (final rune in word.runes) {
            final char = String.fromCharCode(rune);
            if (_measure(chunk + char, size) > limit && chunk.isNotEmpty) {
              lines.add(chunk);
              chunk = '';
            }
            chunk += char;
          }
          word = chunk;
        }
        if (line.isNotEmpty && _measure('$line $word', size) > limit) {
          lines.add(line);
          line = word;
        } else {
          line = line.isEmpty ? word : '$line $word';
        }
      }
      lines.add(line);
    }
    return lines.join('\n');
  }

  Rect _clamp(Rect r) => r.shift(Offset(
      r.left < area.left
          ? area.left - r.left
          : r.right > area.right
              ? area.right - r.right
              : 0,
      r.top < area.top
          ? area.top - r.top
          : r.bottom > area.bottom
              ? area.bottom - r.bottom
              : 0));
  bool _intersectsLine(Rect r, (Offset, Offset) line) {
    final (a, b) = line;
    if (!r.overlaps(Rect.fromPoints(a, b).inflate(0.1))) return false;
    if (r.contains(a) || r.contains(b)) return true;
    double cross(Offset x, Offset y) => x.dx * y.dy - x.dy * y.dx;
    for (final edge in [
      (r.topLeft, r.topRight),
      (r.topRight, r.bottomRight),
      (r.bottomRight, r.bottomLeft),
      (r.bottomLeft, r.topLeft)
    ]) {
      final v = b - a, w = edge.$2 - edge.$1, d = cross(v, w);
      if (d.abs() < 0.0001) continue;
      final t = cross(edge.$1 - a, w) / d, u = cross(edge.$1 - a, v) / d;
      if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return true;
    }
    return false;
  }

  bool _available(Rect r) =>
      r.left >= area.left &&
      r.top >= area.top &&
      r.right <= area.right &&
      r.bottom <= area.bottom &&
      !labels.any((l) => l.rect.inflate(2).overlaps(r)) &&
      !_icons.any((i) => i.inflate(2).overlaps(r)) &&
      !_lines.any((line) => _intersectsLine(r.inflate(1.5), line));
  Rect _place(Size size, Offset preferred,
      {Offset? normal, Offset? dimensionAnchor}) {
    Rect at(Offset center) => _clamp(Rect.fromCenter(
        center: center, width: size.width, height: size.height));
    bool available(Rect r) =>
        _available(r) &&
        (dimensionAnchor == null ||
            !_treatmentAreas.any((area) =>
                area.overlaps(r) ||
                (!area.inflate(0.5).contains(dimensionAnchor) &&
                    _intersectsLine(area.deflate(0.5), (
                      dimensionAnchor,
                      Offset(dimensionAnchor.dx.clamp(r.left, r.right),
                          dimensionAnchor.dy.clamp(r.top, r.bottom))
                    )))));
    final candidates = <Offset>[preferred];
    if (normal != null) {
      final tangent = Offset(-normal.dy, normal.dx);
      for (var step = 1; step <= 12; step++) {
        for (final side in [0.0, 1.0, -1.0]) {
          candidates.add(
              preferred + normal * (step * 7) + tangent * (side * step * 4));
        }
      }
    } else {
      for (var step = 1; step <= 10; step++) {
        for (final d in [
          const Offset(1, 0),
          const Offset(-1, 0),
          const Offset(0, 1),
          const Offset(0, -1)
        ]) {
          candidates.add(preferred + d * (step * 8));
        }
      }
    }
    for (final center in candidates) {
      final r = at(center);
      if (available(r)) return r;
    }
    final free = <Rect>[];
    for (var y = area.top + size.height / 2;
        y <= area.bottom - size.height / 2;
        y += 8) {
      for (var x = area.left + size.width / 2;
          x <= area.right - size.width / 2;
          x += 8) {
        final r = at(Offset(x, y));
        if (available(r)) free.add(r);
      }
    }
    if (free.isEmpty) {
      throw StateError(
          'This drawing has more labels than fit legibly on one graph page.');
    }
    free.sort((a, b) => (a.center - preferred)
        .distance
        .compareTo((b.center - preferred).distance));
    return free.first;
  }

  void _label(String value, Offset anchor,
      {Offset? normal,
      bool callout = false,
      PdfColor color = PdfColors.grey900,
      double size = 8.5}) {
    final text = _wrap(value,
        callout ? math.min(180, width - 28) : math.min(120, width - 28), size);
    final lines = text.split('\n');
    final box = Size(
        lines.map((s) => _measure(s, size)).fold<double>(0, math.max) + 10,
        lines.length * size * 1.5 + 8);
    final preferred =
        normal == null ? anchor : anchor + normal * (box.height / 2 + 8);
    labels.add(PdfDiagramLabel(
        text,
        _place(box, preferred,
            normal: normal, dimensionAnchor: normal == null ? null : anchor),
        anchor,
        fontSize: size,
        color: color,
        callout: callout));
  }

  void _prepareLabels() {
    for (final shape in visibleShapes
        .where((s) => s.preset == GraphDrawingPreset.treatmentArea)) {
      final points = [
        for (final i in shape.segmentIndexes)
          if (i >= 0 && i < document.wallSegments.length)
            project(document.wallSegments[i].start.offset)
      ];
      if (points.isNotEmpty) {
        _treatmentAreas.add(Rect.fromLTRB(
            points.map((p) => p.dx).reduce(math.min),
            points.map((p) => p.dy).reduce(math.min),
            points.map((p) => p.dx).reduce(math.max),
            points.map((p) => p.dy).reduce(math.max)));
      }
    }
    for (final segment in visibleSegments) {
      if (segment.controlPoint == null) {
        _lines
            .add((project(segment.start.offset), project(segment.end.offset)));
      } else {
        var before = project(segment.start.offset);
        for (var i = 1; i <= 16; i++) {
          final t = i / 16;
          final p = project(segment.start.offset * ((1 - t) * (1 - t)) +
              segment.controlPoint!.offset * (2 * (1 - t) * t) +
              segment.end.offset * (t * t));
          _lines.add((before, p));
          before = p;
        }
      }
    }
    if (document.layer('trace').visible) {
      for (final trace in document.traces) {
        for (var i = 0;
            i <
                (trace.closed
                    ? trace.canvasPoints.length
                    : trace.canvasPoints.length - 1);
            i++) {
          _lines.add((
            project(trace.canvasPoints[i].offset),
            project(
                trace.canvasPoints[(i + 1) % trace.canvasPoints.length].offset)
          ));
        }
      }
    }
    for (final a in visibleAnnotations) {
      if (a.kind != GraphAnnotationKind.text && _tip(a) == null) {
        _icons.add(Rect.fromCenter(
            center: project(a.point.offset), width: 14, height: 14));
      }
    }
    // Notes and marker labels reserve their space before dimensions are placed.
    for (final a in visibleAnnotations) {
      final p = project(a.point.offset);
      if (_tip(a) != null || a.kind == GraphAnnotationKind.text) {
        _label(a.label, p, callout: true, size: 9);
      } else {
        _label(
            a.label.isEmpty
                ? a.kind == GraphAnnotationKind.photo
                    ? 'Photo'
                    : a.markerType.label
                : a.label,
            p + const Offset(0, 17),
            size: 8);
      }
    }
    final indexed = <int>{};
    for (final shape in visibleShapes) {
      final segments = [
        for (final i in shape.segmentIndexes)
          if (i >= 0 && i < document.wallSegments.length)
            document.wallSegments[i]
      ];
      indexed.addAll(shape.segmentIndexes);
      if (segments.isEmpty) continue;
      final points = segments.map((s) => s.start.offset).toList();
      var signed = 0.0;
      for (var i = 0; i < points.length; i++) {
        final a = points[i], b = points[(i + 1) % points.length];
        signed += a.dx * b.dy - b.dx * a.dy;
      }
      for (final segment in segments) {
        final d = segment.end.offset - segment.start.offset;
        if (d.distance < 0.01) continue;
        var n = Offset(-d.dy, d.dx) / d.distance;
        if (shape.closed && signed > 0) n = -n;
        _label(segment.measurementLabel,
            project((segment.start.offset + segment.end.offset) / 2),
            normal: n, color: PdfColors.green900);
      }
      if (shape.closed) {
        final center =
            points.reduce((a, b) => a + b) / points.length.toDouble();
        _label(shape.text.trim().isEmpty ? shape.name : shape.text,
            project(center),
            size: 9);
      }
    }
    for (var i = 0; i < document.wallSegments.length; i++) {
      if (indexed.contains(i)) continue;
      final s = document.wallSegments[i];
      if (!visibleSegments.contains(s)) continue;
      final d = s.end.offset - s.start.offset;
      _label(s.measurementLabel, project((s.start.offset + s.end.offset) / 2),
          normal: d.distance == 0
              ? const Offset(0, -1)
              : Offset(d.dy, -d.dx) / d.distance);
    }
    if (document.layer('trace').visible) {
      for (final trace in document.traces) {
        if (trace.geoPoints.length != trace.canvasPoints.length) continue;
        var signed = 0.0;
        for (var i = 0; i < trace.canvasPoints.length; i++) {
          final a = trace.canvasPoints[i].offset,
              b = trace
                  .canvasPoints[(i + 1) % trace.canvasPoints.length].offset;
          signed += a.dx * b.dy - b.dx * a.dy;
        }
        for (var i = 0;
            i <
                (trace.closed
                    ? trace.canvasPoints.length
                    : trace.canvasPoints.length - 1);
            i++) {
          final next = (i + 1) % trace.canvasPoints.length,
              a = trace.canvasPoints[i].offset,
              b = trace.canvasPoints[next].offset,
              d = b - a;
          if (d.distance < 0.01) continue;
          var n = Offset(-d.dy, d.dx) / d.distance;
          if (trace.closed && signed > 0) n = -n;
          final feet = MeasurementService.geodesicDistanceMeters(
                  trace.geoPoints[i], trace.geoPoints[next]) *
              3.280839895013123;
          _label(MeasurementFormat.linearFeet(feet), project((a + b) / 2),
              normal: n, color: PdfColors.blue900);
        }
      }
    }
  }

  pw.Widget widget() => pw.SizedBox(
      width: width,
      height: height,
      child: pw.Stack(children: [
        pw.CustomPaint(size: PdfPoint(width, height), painter: _paint),
        for (final a in visibleAnnotations)
          if (a.kind != GraphAnnotationKind.text && _tip(a) == null)
            pw.Positioned(
                left: project(a.point.offset).dx - 6,
                top: project(a.point.offset).dy - 6,
                child: a.kind == GraphAnnotationKind.marker &&
                        icons.containsKey(iconKey(a))
                    ? pw.Image(pw.MemoryImage(icons[iconKey(a)]!),
                        width: 12, height: 12)
                    : pw.Container(
                        width: 12,
                        height: 12,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                            color: PdfColors.grey800,
                            borderRadius: pw.BorderRadius.circular(2)),
                        child: pw.Text(
                            a.kind == GraphAnnotationKind.photo
                                ? 'P'
                                : a.markerType.shortLabel,
                            style: const pw.TextStyle(
                                fontSize: 6, color: PdfColors.white)))),
        for (final label in labels)
          pw.Positioned(
              left: label.rect.left,
              top: label.rect.top,
              child: pw.Container(
                  width: label.rect.width,
                  height: label.rect.height,
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(
                          color: label.callout
                              ? PdfColors.grey500
                              : PdfColors.grey300,
                          width: 0.45),
                      borderRadius:
                          pw.BorderRadius.circular(label.callout ? 3 : 5)),
                  child: pw.Text(label.text,
                      softWrap: false,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontSize: label.fontSize,
                          color: label.color,
                          height: 1.25)))),
      ]));
  void _paint(PdfGraphics g, PdfPoint size) {
    void move(Offset p) => g.moveTo(p.dx, height - p.dy);
    void line(Offset p) => g.lineTo(p.dx, height - p.dy);
    if (document.layer('trace').visible) {
      for (final trace in document.traces) {
        if (trace.canvasPoints.isEmpty) continue;
        g.saveContext();
        g.setStrokeColor(PdfColors.blue700);
        g.setFillColor(const PdfColor(0.92, 0.95, 0.99));
        g.setLineWidth(1);
        move(project(trace.canvasPoints.first.offset));
        for (final p in trace.canvasPoints.skip(1)) {
          line(project(p.offset));
        }
        if (trace.closed) g.closePath();
        if (trace.closed) {
          g.fillAndStrokePath();
        } else {
          g.strokePath();
        }
        g.restoreContext();
      }
    }
    for (final shape in visibleShapes) {
      final segments = [
        for (final i in shape.segmentIndexes)
          if (i >= 0 && i < document.wallSegments.length)
            document.wallSegments[i]
      ];
      if (segments.isEmpty) continue;
      if (shape.closed && shape.fillColor != null) {
        g.saveContext();
        g.setGraphicState(PdfGraphicState(opacity: shape.fillOpacity));
        g.setFillColor(PdfColor.fromInt(shape.fillColor!.toARGB32()));
        move(project(segments.first.start.offset));
        for (final s in segments) {
          final a = project(s.start.offset), b = project(s.end.offset);
          if (s.controlPoint == null) {
            line(b);
          } else {
            final c = project(s.controlPoint!.offset),
                c1 = a + (c - a) * (2 / 3),
                c2 = b + (c - b) * (2 / 3);
            g.curveTo(c1.dx, height - c1.dy, c2.dx, height - c2.dy, b.dx,
                height - b.dy);
          }
        }
        g.closePath();
        g.fillPath();
        g.restoreContext();
        if (shape.pattern != GraphShapePattern.none) {
          g.saveContext();
          move(project(segments.first.start.offset));
          for (final s in segments) {
            final a = project(s.start.offset), b = project(s.end.offset);
            if (s.controlPoint == null) {
              line(b);
            } else {
              final c = project(s.controlPoint!.offset),
                  c1 = a + (c - a) * (2 / 3),
                  c2 = b + (c - b) * (2 / 3);
              g.curveTo(c1.dx, height - c1.dy, c2.dx, height - c2.dy, b.dx,
                  height - b.dy);
            }
          }
          g.closePath();
          g.clipPath();
          g.setGraphicState(const PdfGraphicState(opacity: 0.35));
          g.setStrokeColor(PdfColor.fromInt(shape.borderColor.toARGB32()));
          g.setFillColor(PdfColor.fromInt(shape.borderColor.toARGB32()));
          g.setLineWidth(0.4);
          final points = segments
              .expand((s) => [
                    project(s.start.offset),
                    project(s.end.offset),
                    if (s.controlPoint != null) project(s.controlPoint!.offset)
                  ])
              .toList();
          final left = points.map((p) => p.dx).reduce(math.min),
              right = points.map((p) => p.dx).reduce(math.max),
              top = points.map((p) => p.dy).reduce(math.min),
              bottom = points.map((p) => p.dy).reduce(math.max);
          final pattern = shape.pattern;
          for (var y = top; y <= bottom; y += 8) {
            if (pattern == GraphShapePattern.horizontal ||
                pattern == GraphShapePattern.grid) {
              g.drawLine(left, height - y, right, height - y);
              g.strokePath();
            }
            for (var x = left; x <= right; x += 8) {
              if (pattern == GraphShapePattern.dots ||
                  pattern == GraphShapePattern.largeDots) {
                g.drawEllipse(
                    x,
                    height - y,
                    pattern == GraphShapePattern.largeDots ? 1.2 : 0.5,
                    pattern == GraphShapePattern.largeDots ? 1.2 : 0.5);
                g.fillPath();
              }
              if (pattern == GraphShapePattern.checker &&
                  ((x - left) / 8 + (y - top) / 8).round().isEven) {
                g.drawRect(x, height - y - 8, 8, 8);
                g.fillPath();
              }
            }
          }
          if (pattern == GraphShapePattern.vertical ||
              pattern == GraphShapePattern.grid) {
            for (var x = left; x <= right; x += 8) {
              g.drawLine(x, height - top, x, height - bottom);
              g.strokePath();
            }
          }
          if (pattern == GraphShapePattern.diagonal ||
              pattern == GraphShapePattern.reverseDiagonal ||
              pattern == GraphShapePattern.crossHatch) {
            for (var x = left - (bottom - top);
                x <= right + (bottom - top);
                x += 8) {
              if (pattern != GraphShapePattern.reverseDiagonal) {
                g.drawLine(
                    x, height - bottom, x + (bottom - top), height - top);
                g.strokePath();
              }
              if (pattern != GraphShapePattern.diagonal) {
                g.drawLine(
                    x, height - top, x + (bottom - top), height - bottom);
                g.strokePath();
              }
            }
          }
          g.restoreContext();
        }
      }
    }
    for (final s in visibleSegments) {
      g.saveContext();
      g.setStrokeColor(PdfColor.fromInt(s.color.toARGB32()));
      g.setLineWidth((s.strokeWidth * scale).clamp(0.7, 2.0));
      if (s.pattern == LinePattern.dashed) {
        g.setLineDashPattern([5, 3]);
      }
      final a = project(s.start.offset), b = project(s.end.offset);
      if (s.pattern == LinePattern.solid || s.pattern == LinePattern.dashed) {
        move(a);
        if (s.controlPoint == null) {
          line(b);
        } else {
          final c = project(s.controlPoint!.offset),
              c1 = a + (c - a) * (2 / 3),
              c2 = b + (c - b) * (2 / 3);
          g.curveTo(c1.dx, height - c1.dy, c2.dx, height - c2.dy, b.dx,
              height - b.dy);
        }
        g.strokePath();
      } else {
        g.setFillColor(PdfColor.fromInt(s.color.toARGB32()));
        final c =
            s.controlPoint == null ? null : project(s.controlPoint!.offset);
        Offset at(double t) => c == null
            ? a + (b - a) * t
            : a * ((1 - t) * (1 - t)) + c * (2 * (1 - t) * t) + b * (t * t);
        var length = 0.0;
        var previous = a;
        for (var i = 1; i <= 32; i++) {
          final next = at(i / 32);
          length += (next - previous).distance;
          previous = next;
        }
        final count = math.max(1, (length / 7).floor());
        for (var i = 0; i <= count; i++) {
          final p = at(i / count);
          if (s.pattern == LinePattern.dottedSmall ||
              s.pattern == LinePattern.dottedLarge) {
            final r = s.pattern == LinePattern.dottedLarge ? 1.4 : 0.7;
            g.drawEllipse(p.dx, height - p.dy, r, r);
            g.fillPath();
          } else if (s.pattern == LinePattern.xMarks) {
            g.drawLine(
                p.dx - 2, height - p.dy - 2, p.dx + 2, height - p.dy + 2);
            g.drawLine(
                p.dx - 2, height - p.dy + 2, p.dx + 2, height - p.dy - 2);
            g.strokePath();
          } else {
            move(p + const Offset(0, -2));
            line(p + const Offset(2, 0));
            line(p + const Offset(0, 2));
            line(p + const Offset(-2, 0));
            g.closePath();
            g.fillPath();
          }
        }
      }
      if (s.hasArrow) _arrow(g, a, b);
      g.restoreContext();
    }
    if (document.layer('structure').visible) {
      for (final stroke in document.freehandStrokes) {
        if (stroke.points.isEmpty) continue;
        g.saveContext();
        g.setGraphicState(PdfGraphicState(opacity: stroke.opacity.clamp(0, 1)));
        g.setStrokeColor(PdfColor.fromInt(stroke.color.toARGB32()));
        g.setLineWidth((stroke.strokeWidth * scale).clamp(0.7, 2));
        move(project(stroke.points.first.offset));
        for (final p in stroke.points.skip(1)) {
          line(project(p.offset));
        }
        g.strokePath();
        g.restoreContext();
      }
    }
    g.setStrokeColor(PdfColors.grey500);
    g.setLineWidth(0.45);
    for (final label in labels) {
      final border = Offset(
          label.anchor.dx.clamp(label.rect.left, label.rect.right),
          label.anchor.dy.clamp(label.rect.top, label.rect.bottom));
      if ((border - label.anchor).distance > 2) {
        g.drawLine(label.anchor.dx, height - label.anchor.dy, border.dx,
            height - border.dy);
        g.strokePath();
      }
    }
    for (final a in visibleAnnotations) {
      final tip = _tip(a);
      if (tip == null) continue;
      final anchor = project(a.point.offset);
      final label = labels
          .firstWhere((l) => l.callout && (l.anchor - anchor).distance < 0.01);
      final end = Offset(
          project(tip).dx.clamp(label.rect.left, label.rect.right),
          project(tip).dy.clamp(label.rect.top, label.rect.bottom));
      final start = project(tip);
      g.setStrokeColor(PdfColor.fromInt(a.borderColor.toARGB32()));
      g.setLineWidth(0.75);
      g.drawLine(start.dx, height - start.dy, end.dx, height - end.dy);
      g.strokePath();
      _arrow(g, end, start);
    }
  }

  void _arrow(PdfGraphics g, Offset from, Offset to) {
    final d = to - from;
    if (d.distance < 0.01) return;
    final unit = d / d.distance, side = Offset(-unit.dy, unit.dx);
    final a = to - unit * 6 + side * 2.5, b = to - unit * 6 - side * 2.5;
    g.moveTo(to.dx, height - to.dy);
    g.lineTo(a.dx, height - a.dy);
    g.lineTo(b.dx, height - b.dy);
    g.closePath();
    g.setFillColor(PdfColors.grey700);
    g.fillPath();
  }
}
