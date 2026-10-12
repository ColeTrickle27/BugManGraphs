import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/obj/object_stream.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/services/graph_pdf_diagram.dart';
import 'package:bugman_graphs/services/graph_pdf_export.dart';
import 'package:bugman_graphs/widgets/graph_shapes_painter.dart';
import 'graph_pdf_print_layout_test.dart' show printFixture;

Future<GraphPdfDiagram> plan(GraphDocument doc) async => GraphPdfDiagram(
    doc,
    732,
    440,
    PdfTtfFont(PdfDocument(),
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf')));
String paintCommands(GraphPdfDiagram plan) {
  final page =
      PdfPage(PdfDocument(), pageFormat: PdfPageFormat.letter.landscape);
  final paint = ((plan.widget() as pw.SizedBox).child as pw.Stack)
      .children
      .first as pw.CustomPaint;
  paint.painter!(page.getGraphics(), PdfPoint(plan.width, plan.height));
  return latin1.decode((page.contents.first as PdfObjectStream).buf.output());
}

Future<void> sample(GraphDocument doc, String name) async {
  final out = Platform.environment['GRAPH_PDF_QA_OUT'];
  if (out == null) return;
  final bytes = await GraphPdfExport.build(
      graphPng: Uint8List(0),
      title: doc.customer.name,
      sourceDocument: doc,
      brandingLogo:
          (await rootBundle.load('assets/branding/holloman_exterminators.png'))
              .buffer
              .asUint8List());
  await File('$out/$name.pdf').writeAsBytes(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('non-main-only exports retain slab, garage and property acreage totals',
      () async {
    for (final preset in [
      GraphDrawingPreset.slab,
      GraphDrawingPreset.garage,
      GraphDrawingPreset.propertyLine
    ]) {
      final doc = printFixture('small');
      doc.replaceShapes([
        doc.shapes.first
            .copyWith(name: 'Synthetic ${preset.name}', preset: preset)
      ]);
      final before = doc.toJson();
      final totals = GraphPdfExport.summariesForDocument(doc);
      expect(totals, hasLength(1));
      expect(totals.single.isMainStructure, isFalse);
      final segments = doc.wallSegments.toList();
      if (preset == GraphDrawingPreset.propertyLine) {
        expect(totals.single.measurements,
            shapeMeasurementSummary(doc.shapes.single, segments).split(' • '));
      } else {
        expect(totals.single.measurements,
            shapeExportMeasurements(doc.shapes.single, segments));
      }
      await sample(doc, 'non-main-${preset.name}');
      expect(doc.toJson(), before);
    }
  });
  test('main foundation and explicit open shape labels remain present',
      () async {
    final doc = printFixture('small');
    doc.replaceShapes([
      doc.shapes.first
          .copyWith(extraProperties: {'foundationType': 'crawlspace'})
    ]);
    expect((await plan(doc)).labels.any((l) => l.text.contains('Crawlspace')),
        isTrue);
    await sample(doc, 'foundation');
    doc.replaceShapes([
      doc.shapes.first.copyWith(
          closed: false,
          text: 'Accessible open fence boundary',
          preset: GraphDrawingPreset.fenceLine,
          clearFillColor: true)
    ]);
    final labels =
        (await plan(doc)).labels.map((l) => l.text.replaceAll('\n', ' '));
    expect(labels, contains('Accessible open fence boundary'));
    await sample(doc, 'open-labeled');
  });
  test('saved marker rotation is applied clockwise without moving its anchor',
      () async {
    final doc = printFixture('small');
    doc.replaceAnnotations(
        [doc.annotations.first.copyWith(rotationDegrees: 90)]);
    final p = await plan(doc);
    final stack = (p.widget() as pw.SizedBox).child as pw.Stack;
    final icon = stack.children.whereType<pw.Positioned>().first;
    final rotation = icon.child as pw.Transform;
    expect(rotation.transform.entry(0, 0), closeTo(0, 1e-9));
    expect(rotation.transform.entry(1, 0), closeTo(-1, 1e-9));
    expect(icon.left,
        closeTo(p.project(doc.annotations.single.point.offset).dx - 6, 1e-9));
    await sample(doc, 'rotated-marker');
  });
  test('unfilled patterns and edited shape borders reach PDF painting',
      () async {
    final doc = printFixture('small');
    doc.replaceAnnotations([]);
    doc.replaceShapes([
      doc.shapes.first.copyWith(
          clearFillColor: true,
          pattern: GraphShapePattern.grid,
          borderColor: const Color(0xffff0000),
          borderWidth: 9)
    ]);
    final before = doc.toJson();
    final p = await plan(doc);
    final commands = paintCommands(p);
    expect(commands, contains('1 0 0 RG'));
    expect(commands, matches(RegExp(r'\bW\s+n\b')));
    final widths = RegExp(r'([\d.]+) w')
        .allMatches(commands)
        .map((m) => double.parse(m[1]!));
    expect(widths.any((w) => (w - 9 * p.scale).abs() < 0.01), isTrue);
    await sample(doc, 'unfilled-pattern-custom-border');
    expect(doc.toJson(), before);
  });
  test('curved arrowhead follows the final quadratic tangent', () async {
    final doc = printFixture('small');
    doc.replaceShapes([]);
    doc.replaceAnnotations([]);
    const segment = WallSegment(
        start: GraphPoint(x: 0, y: 0),
        controlPoint: GraphPoint(x: 100, y: -150),
        end: GraphPoint(x: 200, y: 0),
        hasArrow: true);
    doc.replaceWallSegments([segment]);
    final p = await plan(doc);
    final commands = paintCommands(p);
    final tip = p.project(segment.end.offset);
    final direction = (segment.end.offset - segment.controlPoint!.offset);
    final unit = direction / direction.distance;
    final center = tip - unit * (18 * p.scale * math.cos(math.pi / 6));
    final triangles = RegExp(
            r'([\d.\-]+) ([\d.\-]+) m\s+([\d.\-]+) ([\d.\-]+) l\s+([\d.\-]+) ([\d.\-]+) l\s+h')
        .allMatches(commands);
    final arrow = triangles.firstWhere((m) =>
        (double.parse(m[1]!) - tip.dx).abs() < 0.01 &&
        (double.parse(m[2]!) - (p.height - tip.dy)).abs() < 0.01);
    final base = Offset((double.parse(arrow[3]!) + double.parse(arrow[5]!)) / 2,
        p.height - (double.parse(arrow[4]!) + double.parse(arrow[6]!)) / 2);
    expect((base - center).distance, lessThan(0.02));
    await sample(doc, 'curved-arrow');
  });
}
