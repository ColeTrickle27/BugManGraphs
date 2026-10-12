import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/freehand_stroke.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/services/graph_pdf_diagram.dart';
import 'package:bugman_graphs/services/graph_pdf_export.dart';
import 'package:bugman_graphs/services/graph_export_legend.dart';
import 'support/crowded_canvas_fixture.dart';

GraphDocument printFixture(String kind) {
  final doc = crowdedCanvasFixture();
  doc.replaceTraces([]);
  doc.replaceFreehandStrokes([]);
  final scale = kind == 'large' ? 20.0 : 1.0;
  final w = kind == 'wide'
      ? 7300.0
      : kind == 'tall'
          ? 120.0
          : 240.0;
  final h = kind == 'tall'
      ? 7300.0
      : kind == 'wide'
          ? 120.0
          : 180.0;
  final points = [
    GraphPoint(x: 100 * scale, y: 100 * scale),
    GraphPoint(x: (100 + w) * scale, y: 100 * scale),
    GraphPoint(x: (100 + w) * scale, y: (100 + h) * scale),
    GraphPoint(x: 100 * scale, y: (100 + h) * scale)
  ];
  final main = doc.shapes.first
      .copyWith(name: 'Main Structure', segmentIndexes: [0, 1, 2, 3]);
  if (kind != 'dense') {
    doc.replaceWallSegments([
      for (var i = 0; i < 4; i++)
        WallSegment(start: points[i], end: points[(i + 1) % 4])
    ]);
    doc.replaceShapes([main]);
    doc.replaceAnnotations([
      GraphAnnotation(
          id: 'print-mud',
          kind: GraphAnnotationKind.marker,
          point: GraphPoint(x: 180 * scale, y: 180 * scale),
          label: 'Mud tube',
          markerType: GraphMarkerType.mudTube),
      GraphAnnotation(
          id: 'print-entry',
          kind: GraphAnnotationKind.marker,
          point: GraphPoint(x: 280 * scale, y: 180 * scale),
          label: 'Entry point',
          markerType: GraphMarkerType.entryPoint),
      GraphAnnotation(
          id: 'print-note',
          kind: GraphAnnotationKind.text,
          point: GraphPoint(x: 20 * scale, y: 420 * scale),
          label: kind == 'boundary'
              ? 'Long boundary callout: inspect the adjoining foundation and preserve the complete wording.'
              : 'Treatment needed',
          extraProperties: {
            'calloutTipX': 240.0 * scale,
            'calloutTipY': 240.0 * scale
          }),
    ]);
  } else {
    doc.replaceTraces(crowdedCanvasFixture().traces);
    doc.replaceShapes([
      doc.shapes.first,
      doc.shapes.last.copyWith(preset: GraphDrawingPreset.treatmentArea)
    ]);
    doc.replaceAnnotations([
      for (var i = 0; i < 10; i++)
        GraphAnnotation(
            id: 'dense-note-$i',
            kind: GraphAnnotationKind.text,
            point:
                GraphPoint(x: 400.0 + (i % 5) * 390, y: 500.0 + (i ~/ 5) * 700),
            label: 'Inspection note ${i + 1}'),
      const GraphAnnotation(
          id: 'dense-pin',
          kind: GraphAnnotationKind.marker,
          point: GraphPoint(x: 1800, y: 900),
          label: 'Mud tubes',
          markerType: GraphMarkerType.mudTube),
      const GraphAnnotation(
          id: 'dense-callout',
          kind: GraphAnnotationKind.text,
          point: GraphPoint(x: 450, y: 1950),
          label: 'Treatment needed at the accessible foundation edge',
          extraProperties: {'calloutTipX': 600.0, 'calloutTipY': 1700.0}),
    ]);
  }
  if (kind == 'multiple') {
    final old = doc.wallSegments.toList();
    doc.replaceWallSegments([
      ...old,
      for (final s in old)
        s.copyWith(
            start:
                GraphPoint.fromOffset(s.start.offset + const Offset(600, 200)),
            end: GraphPoint.fromOffset(s.end.offset + const Offset(600, 200)))
    ]);
    doc.replaceShapes([
      main.copyWith(name: 'Main Structure 1'),
      main.copyWith(name: 'Main Structure 2', segmentIndexes: [4, 5, 6, 7])
    ]);
  }
  if (kind == 'styled') {
    doc.replaceWallSegments([
      for (var i = 0; i < doc.wallSegments.length; i++)
        doc.wallSegments[i].copyWith(
            pattern: LinePattern.values[(i + 2) % LinePattern.values.length],
            controlPoint: i == 0 ? const GraphPoint(x: 220, y: 20) : null)
    ]);
    doc.replaceShapes([main.copyWith(pattern: GraphShapePattern.crossHatch)]);
    doc.replaceFreehandStrokes([
      const FreehandStroke(
          points: [GraphPoint(x: 80, y: 300), GraphPoint(x: 160, y: 320)],
          opacity: 0.4)
    ]);
  }
  doc.updateCustomer(GraphCustomerInfo(
      name: kind == 'missing'
          ? ''
          : kind == 'boundary'
              ? 'A long synthetic customer identification line used to verify readable complete header information'
              : 'Synthetic customer - $kind',
      serviceAddress: kind == 'missing'
          ? ''
          : kind == 'boundary'
              ? 'Synthetic training property, building A, accessible inspection areas and an intentionally long address description for layout verification; no real property address.'
              : 'Synthetic site - no real address',
      pestPacBillToNumber: kind == 'missing' ? '' : 'TEST-BILL',
      pestPacLocationNumber: kind == 'missing' ? '' : 'TEST-LOC',
      serviceType: 'Inspection',
      createdBy: 'Synthetic tester'));
  return doc;
}

Uint8List photo(int w, int h, int n) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(230, 235, 239));
  img.fillRect(image,
      x1: w ~/ 8,
      y1: h ~/ 8,
      x2: w * 7 ~/ 8,
      y2: h * 7 ~/ 8,
      color: img.ColorRgb8(40 + n * 20, 100, 140));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in [
    'small',
    'large',
    'wide',
    'tall',
    'dense',
    'multiple',
    'boundary',
    'missing',
    'styled'
  ]) {
    test(
        'print layout $kind preserves source, all labels and readable typography',
        () async {
      final doc = printFixture(kind);
      final before = doc.toJson();
      final fontBytes =
          await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final metrics = PdfTtfFont(PdfDocument(), fontBytes);
      final plan = GraphPdfDiagram(
          doc, kind == 'tall' ? 540 : 732, kind == 'tall' ? 620 : 440, metrics);
      for (var i = 0; i < plan.labels.length; i++) {
        final a = plan.labels[i];
        expect(a.fontSize, greaterThanOrEqualTo(8));
        expect(a.rect.left, greaterThanOrEqualTo(0));
        expect(a.rect.top, greaterThanOrEqualTo(0));
        expect(a.rect.right, lessThanOrEqualTo(plan.width));
        expect(a.rect.bottom, lessThanOrEqualTo(plan.height));
        for (final b in plan.labels.skip(i + 1)) {
          expect(a.rect.overlaps(b.rect), isFalse,
              reason: '${a.text} overlaps ${b.text}');
        }
      }
      final blank =
          Uint8List.fromList(img.encodePng(img.Image(width: 1, height: 1)));
      final logo =
          (await rootBundle.load('assets/branding/holloman_exterminators.png'))
              .buffer
              .asUint8List();
      final bytes = await GraphPdfExport.build(
          graphPng: blank,
          title: doc.customer.displayName,
          sourceDocument: doc,
          brandingLogo: logo,
          legend: buildGraphLegend(doc.annotations, shapes: doc.shapes));
      expect(bytes.take(4), [37, 80, 68, 70]);
      expect(doc.toJson(), before);
      final out = Platform.environment['GRAPH_PDF_QA_OUT'];
      if (out != null) {
        await Directory(out).create(recursive: true);
        await File('$out/$kind.pdf').writeAsBytes(bytes);
      }
    });
  }
  for (final count in [0, 1, 3]) {
    test('photo appendix $count preserves aspect ratios, captions and order',
        () async {
      final doc = printFixture('small'), before = doc.toJson();
      final photos = [
        for (var i = 0; i < count; i++)
          GraphPdfPhoto(
              referenceLabel: '${i + 1}A',
              filename: 'synthetic-photo-${i + 1}.jpg',
              caption:
                  'Existing synthetic observation ${i + 1}; no invented customer description.',
              bytes: photo(i == 0 ? 500 : 900, i == 0 ? 900 : 500, i))
      ];
      final bytes = await GraphPdfExport.build(
          graphPng:
              Uint8List.fromList(img.encodePng(img.Image(width: 1, height: 1))),
          title: doc.customer.displayName,
          sourceDocument: doc,
          brandingLogo: (await rootBundle
                  .load('assets/branding/holloman_exterminators.png'))
              .buffer
              .asUint8List(),
          photos: photos);
      expect(doc.toJson(), before);
      final out = Platform.environment['GRAPH_PDF_QA_OUT'];
      if (out != null) await File('$out/photos-$count.pdf').writeAsBytes(bytes);
    });
  }
}
