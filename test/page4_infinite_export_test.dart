import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:bugman_graphs/services/graph_image_export.dart';
import 'package:bugman_graphs/services/graph_pat_catalog.dart';
import 'package:bugman_graphs/services/graph_pdf_export.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/widgets/scene_viewport_painter.dart';
import 'package:bugman_graphs/services/structure_join.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/wall_segment.dart';

void main() {
  test(
      'mid-edge joins use the shortest copied boundary without modifying the structure',
      () {
    const points = [
      GraphPoint(x: 0, y: 0),
      GraphPoint(x: 100, y: 0),
      GraphPoint(x: 100, y: 100),
      GraphPoint(x: 0, y: 100)
    ];
    final ring = [
      for (var i = 0; i < 4; i++)
        WallSegment(start: points[i], end: points[(i + 1) % 4])
    ];
    final result = structureBoundaryBetween(
        ring, const GraphPoint(x: 75, y: 0), const GraphPoint(x: 25, y: 0))!;
    expect(result, hasLength(1));
    expect(result.single.lengthPixels, 50);
    expect(ring.first.start, points.first);
    expect(ring.first.end, points[1]);
    expect(
        projectOntoStraightEdge(const GraphPoint(x: 60, y: -10), ring.first)
            .offset,
        const Offset(60, 0));
  });
  for (final entry in const {
    GraphShapePattern.blockwork: Offset(450, 450),
    GraphShapePattern.brick: Offset(225, 150),
    GraphShapePattern.checkerplate: Offset(1, 1)
  }.entries) {
    test('validated PAT translation repeat ${entry.key.name}', () {
      final pattern = graphPatPatterns[entry.key]!;
      final bounds =
          Rect.fromLTWH(0, 0, entry.value.dx * 2, entry.value.dy * 2);
      for (final shift in [
        Offset(entry.value.dx, 0),
        Offset(0, entry.value.dy)
      ]) {
        final source = pattern.strokes(bounds);
        final translated = pattern.strokes(bounds.shift(shift).inflate(0.001));
        for (final stroke
            in source.where((s) => (s.end - s.start).distance > 0.001)) {
          final point = (stroke.start + stroke.end) / 2 + shift;
          expect(translated.any((s) {
            final d = s.end - s.start;
            final n = d.distanceSquared;
            if (n == 0) return false;
            final t =
                ((point - s.start).dx * d.dx + (point - s.start).dy * d.dy) / n;
            return t >= -1e-7 &&
                t <= 1.0000001 &&
                (s.start + d * t - point).distance < 1e-6;
          }), isTrue, reason: '${entry.key} shift $shift point $point');
        }
      }
    });
  }
  testWidgets(
      'infinite viewport and export render negative coordinates independently of zoom',
      (tester) async {
    final key = GlobalKey();
    final controller = TransformationController()
      ..value = Matrix4.identity()
      ..value.translateByDouble(220, 40, 0, 1);
    void scene(Canvas c, Size s) => c.drawRect(
        const Rect.fromLTWH(-200, 0, 100, 100),
        Paint()..color = const Color(0xFFFF0000));
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
            key: key,
            child: SizedBox(
                width: 400,
                height: 240,
                child: CustomPaint(
                    painter: SceneViewportPainter(
                        controller: controller,
                        paintScene: scene,
                        gridVisible: false))))));
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final png = await GraphImageExport.capturePng(
          boundary, const Rect.fromLTWH(-210, -10, 120, 120),
          paintScene: scene);
      final decoded = img.decodePng(png)!;
      expect(decoded.width, 120);
      expect(decoded.height, 120);
      expect(decoded.getPixel(60, 60).r, 255);
      expect(decoded.getPixel(60, 60).g, 0);
      final dir = Directory('artifacts/page4')..createSync(recursive: true);
      File('${dir.path}/negative-world-export.png').writeAsBytesSync(png);
      File('${dir.path}/negative-world-export.pdf').writeAsBytesSync(
          await GraphPdfExport.build(
              graphPng: png, title: 'Synthetic unbounded coordinate export'));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
          const Rect.fromLTWH(0, 0, 720, 240), Paint()..color = Colors.white);
      var x = 0.0;
      for (final pattern in graphPatPatterns.entries) {
        pattern.value.paint(
            canvas,
            Path()..addRect(Rect.fromLTWH(x, 0, 240, 240)),
            Paint()
              ..color = Colors.black
              ..strokeWidth = 1 / graphPatUnitScale[pattern.key]!,
            unitsPerPatternUnit: graphPatUnitScale[pattern.key]!);
        x += 240;
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(720, 240);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/native-pat-fills.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
    controller.dispose();
  });
}
