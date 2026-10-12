import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;
import 'dart:ui' as ui;
import 'package:flutter/material.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection, Icons;
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/graph_document.dart';
import '../models/graph_annotation.dart';
import '../models/graph_shape.dart';
import '../widgets/graph_marker_visual.dart';
import '../widgets/graph_shapes_painter.dart'
    show shapeExportMeasurements, shapeMeasurementSummary;
import 'graph_export_legend.dart';
import 'graph_pdf_diagram.dart';
import 'measurement_service.dart';
import 'measurement_format.dart';
import '../models/trace_geometry.dart';

class GraphPdfPhoto {
  const GraphPdfPhoto(
      {required this.referenceLabel,
      required this.filename,
      required this.bytes,
      this.caption = ''});
  final String referenceLabel, filename, caption;
  final Uint8List bytes;
}

class GraphMeasurementSummary {
  const GraphMeasurementSummary(
      {required this.label,
      required this.measurements,
      this.isMainStructure = false});
  final bool isMainStructure;
  final String label;
  final List<String> measurements;
}

class GraphPdfExport {
  const GraphPdfExport._();
  static bool isReadablePhoto(Uint8List bytes) {
    try {
      return bytes.isNotEmpty && img.decodeImage(bytes) != null;
    } catch (_) {
      return false;
    }
  }

  static List<GraphMeasurementSummary> summariesForDocument(
      GraphDocument source) {
    final result = <GraphMeasurementSummary>[];
    for (final shape in source.shapes) {
      if (!source.layer('structure').visible ||
          !source.layer('shapes').visible ||
          (shape.preset == GraphDrawingPreset.treatmentArea &&
              !source.layer('treatment').visible)) {
        continue;
      }
      final segments = [
        for (final i in shape.segmentIndexes)
          if (i >= 0 && i < source.wallSegments.length) source.wallSegments[i]
      ];
      final measurements =
          shape.preset == GraphDrawingPreset.propertyLine && shape.closed
              ? shapeMeasurementSummary(shape, segments)
                  .split(' • ')
                  .where((s) => s.isNotEmpty)
                  .toList()
              : shapeExportMeasurements(shape, segments);
      if (measurements.isEmpty) continue;
      result.add(GraphMeasurementSummary(
          isMainStructure: shape.preset == GraphDrawingPreset.mainStructure,
          label: shape.text.trim().isEmpty ? shape.name : shape.text,
          measurements: measurements));
    }
    if (source.layer('trace').visible) {
      for (final trace in source.traces) {
        if (trace.geoPoints.length < 2) continue;
        final m = MeasurementService.measureTrace(trace,
            status: MeasurementAccuracyStatus.estimated);
        result.add(GraphMeasurementSummary(label: trace.label, measurements: [
          MeasurementFormat.linearFeet(m.linearFeet),
          if (trace.closed) ...[
            MeasurementFormat.squareFeet(m.squareFeet),
            MeasurementFormat.acres(m.acres)
          ]
        ]));
      }
    }
    return result;
  }

  static Future<void>? _materialFont;
  static Future<Map<String, Uint8List>> _icons(GraphDocument source) async {
    final markers = source.annotations.where((a) =>
        (a.kind == GraphAnnotationKind.marker ||
            a.kind == GraphAnnotationKind.photo) &&
        a.extraProperties['calloutTipX'] is! num &&
        (a.kind != GraphAnnotationKind.photo ||
            source.layer('photos').visible));
    if (markers.isEmpty) return {};
    try {
      await (_materialFont ??= (() async {
        final loader = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await loader.load();
      })());
    } catch (_) {
      return {};
    }
    final result = <String, Uint8List>{};
    for (final marker in markers) {
      final key = GraphPdfDiagram.iconKey(marker);
      if (result.containsKey(key)) continue;
      final icon = marker.kind == GraphAnnotationKind.photo
              ? Icons.photo_camera
              : iconForGraphMarker(marker.markerType),
          recorder = ui.PictureRecorder(),
          canvas = ui.Canvas(recorder);
      final text = TextPainter(
          text: TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(
                  inherit: false,
                  fontSize: 48,
                  color: marker.kind == GraphAnnotationKind.photo
                      ? const ui.Color(0xFF2C6F9F)
                      : marker.color ?? marker.markerType.defaultColor,
                  fontFamily: icon.fontFamily,
                  package: icon.fontPackage)),
          textDirection: TextDirection.ltr)
        ..layout();
      text.paint(
          canvas, ui.Offset((64 - text.width) / 2, (64 - text.height) / 2));
      final picture = recorder.endRecording(),
          image = await picture.toImage(64, 64);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) result[key] = data.buffer.asUint8List();
      image.dispose();
      picture.dispose();
    }
    return result;
  }

  static Future<Uint8List> build(
      {required Uint8List graphPng,
      required String title,
      GraphDocument? sourceDocument,
      List<GraphLegendSection> legend = const [],
      List<GraphMeasurementSummary> measurementSummary = const [],
      List<GraphPdfPhoto> photos = const [],
      Uint8List? brandingLogo,
      Uint8List? markerIconFontBytes}) async {
    final graph = sourceDocument == null
        ? null
        : GraphDocument.fromJson(sourceDocument.toJson());
    final regular = (await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold = (await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    final baseFont = pw.Font.ttf(regular), boldFont = pw.Font.ttf(bold);
    final document = pw.Document(
        title: title,
        creator: 'BugMan Graphs',
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont));
    final metrics = PdfTtfFont(document.document, regular);
    final logo = brandingLogo == null ? null : pw.MemoryImage(brandingLogo);
    final symbols = graph == null ? <String, Uint8List>{} : await _icons(graph);
    for (final photo in photos) {
      if (img.decodeImage(photo.bytes) == null) {
        throw StateError(
            'PDF not exported: photo "${photo.filename}" could not be read.');
      }
    }
    final groups = <List<GraphPdfPhoto>>[];
    for (var i = 0; i < photos.length;) {
      final photo = img.decodeImage(photos[i].bytes);
      final count = photo != null && photo.height > photo.width * 1.1
          ? 1
          : math.min(2, photos.length - i);
      groups.add(photos.sublist(i, i + count));
      i += count;
    }
    final totalPages = 1 + groups.length;
    final customer = graph?.customer;
    final name = customer?.name.trim() ?? title.trim();
    final address = customer?.serviceAddress.trim() ?? '';
    final ids = [
      if ((customer?.pestPacBillToNumber.trim() ?? '').isNotEmpty)
        'Bill-To ${customer!.pestPacBillToNumber}',
      if ((customer?.pestPacLocationNumber.trim() ?? '').isNotEmpty)
        'Location ${customer!.pestPacLocationNumber}'
    ].join('  |  ');
    pw.Widget header(String kind) =>
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            if (logo != null)
              pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 12),
                  child: pw.Image(logo,
                      width: 112, height: 29, fit: pw.BoxFit.contain)),
            pw.Expanded(
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                  pw.Text('Holloman Exterminators',
                      style: const pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey900)),
                  if (name.isNotEmpty)
                    pw.Text(name,
                        style: const pw.TextStyle(
                            fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  if (address.isNotEmpty)
                    pw.Text(address,
                        style: const pw.TextStyle(
                            fontSize: 8.5, color: PdfColors.grey700)),
                  if (ids.isNotEmpty)
                    pw.Text(ids,
                        style: const pw.TextStyle(
                            fontSize: 7.5, color: PdfColors.grey700)),
                ])),
            pw.SizedBox(width: 12),
            pw.Text(kind,
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ]),
          pw.SizedBox(height: 8),
          pw.Container(height: 1, color: PdfColors.red800),
          pw.SizedBox(height: 9),
        ]);
    pw.Widget footer(int page) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('BugMan Graphs',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey600)),
              pw.Text('Page $page of $totalPages',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey600)),
            ]));
    final effectiveLegend = graph == null
        ? legend
        : buildGraphLegend(
            graph.annotations.where((a) =>
                a.extraProperties['calloutTipX'] is! num &&
                (a.kind != GraphAnnotationKind.photo ||
                    graph.layer('photos').visible)),
            shapes: graph.shapes,
            inspectionsVisible: graph.layer('inspections').visible,
            treatmentVisible: graph.layer('treatment').visible);
    final entries = effectiveLegend.expand((s) => s.entries).toList();
    final allTotals =
        graph == null ? measurementSummary : summariesForDocument(graph);
    final totals = graph == null
        ? allTotals
        : allTotals.where((s) => s.isMainStructure).toList();
    final detailTotals = graph == null
        ? <GraphMeasurementSummary>[]
        : allTotals.where((s) => !s.isMainStructure).toList();
    final format = graph != null && _tall(graph)
        ? PdfPageFormat.letter
        : PdfPageFormat.letter.landscape;
    document.addPage(pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  header('PROPERTY DIAGRAM'),
                  pw.Expanded(
                      child: pw.LayoutBuilder(builder: (context, constraints) {
                    final width = constraints!.maxWidth;
                    final summaryHeight = totals.isEmpty
                        ? 0.0
                        : math.max(24.0, totals.length * 12.0 + 8);
                    final graphHeight = constraints.maxHeight - summaryHeight;
                    final diagram = graph == null
                        ? pw.Center(
                            child: pw.Image(pw.MemoryImage(graphPng),
                                fit: pw.BoxFit.contain))
                        : GraphPdfDiagram(
                                graph, width - 12, graphHeight - 12, metrics,
                                icons: symbols)
                            .widget();
                    return pw.Container(
                        decoration: pw.BoxDecoration(
                            border: pw.Border.all(
                                color: PdfColors.grey300, width: 0.6)),
                        child: pw.Column(children: [
                          pw.Expanded(
                              child: pw.Padding(
                                  padding: const pw.EdgeInsets.all(6),
                                  child: diagram)),
                          if (totals.isNotEmpty)
                            pw.Container(
                                height: summaryHeight,
                                width: width,
                                color: PdfColors.grey100,
                                padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      for (final item in totals)
                                        pw.Text(
                                            '${item.label}: ${item.measurements.join('  |  ')}',
                                            style: const pw.TextStyle(
                                                fontSize: 8,
                                                color: PdfColors.grey700)),
                                    ])),
                        ]));
                  })),
                  if (detailTotals.isNotEmpty)
                    pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 6),
                        child: pw.Wrap(spacing: 12, runSpacing: 3, children: [
                          for (final item in detailTotals)
                            pw.SizedBox(
                                width: (format.width - 60) / 2,
                                child: pw.Text(
                                    '${item.label}: ${item.measurements.join('  |  ')}',
                                    style: const pw.TextStyle(
                                        fontSize: 8, color: PdfColors.grey700)))
                        ])),
                  if (entries.isNotEmpty ||
                      graph?.annotations.any((a) =>
                              a.kind == GraphAnnotationKind.photo &&
                              graph.layer('photos').visible) ==
                          true)
                    pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 8),
                        child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('LEGEND',
                                  style: const pw.TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.grey600)),
                              pw.SizedBox(height: 4),
                              pw.Wrap(spacing: 14, runSpacing: 4, children: [
                                for (final entry in entries)
                                  pw.Row(
                                      mainAxisSize: pw.MainAxisSize.min,
                                      children: [
                                        if (symbols.containsKey(
                                            '${entry.markerType.name}:${entry.color.toARGB32()}'))
                                          pw.Image(
                                              pw.MemoryImage(symbols[
                                                  '${entry.markerType.name}:${entry.color.toARGB32()}']!),
                                              width: 12,
                                              height: 12)
                                        else
                                          pw.Container(
                                              width: 12,
                                              height: 12,
                                              color: PdfColor.fromInt(
                                                  entry.color.toARGB32()),
                                              alignment: pw.Alignment.center,
                                              child: pw.Text(
                                                  entry.markerType.shortLabel,
                                                  style: const pw.TextStyle(
                                                      fontSize: 5,
                                                      color: PdfColors.white))),
                                        pw.SizedBox(width: 4),
                                        pw.Text(entry.markerType.label,
                                            style: const pw.TextStyle(
                                                fontSize: 8)),
                                      ])
                              ]),
                            ])),
                  footer(1),
                ])));
    for (var page = 0; page < groups.length; page++) {
      final group = groups[page];
      document.addPage(pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    header('PHOTO REFERENCES'),
                    for (var index = 0; index < group.length; index++)
                      pw.Expanded(
                          child: pw.Padding(
                              padding: pw.EdgeInsets.only(
                                  bottom: index + 1 < group.length ? 14 : 0),
                              child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                        '${group[index].referenceLabel}  ${group[index].filename}',
                                        style: const pw.TextStyle(
                                            fontSize: 10,
                                            fontWeight: pw.FontWeight.bold)),
                                    if (group[index].caption.trim().isNotEmpty)
                                      pw.Padding(
                                          padding: const pw.EdgeInsets.only(
                                              top: 3, bottom: 4),
                                          child: pw.Text(group[index].caption,
                                              style: const pw.TextStyle(
                                                  fontSize: 9,
                                                  color: PdfColors.grey700))),
                                    pw.SizedBox(height: 6),
                                    pw.Expanded(
                                        child: pw.Center(
                                            child: pw.Image(
                                                pw.MemoryImage(
                                                    group[index].bytes),
                                                fit: pw.BoxFit.contain))),
                                  ]))),
                    footer(page + 2),
                  ])));
    }
    return document.save();
  }

  static bool _tall(GraphDocument source) {
    final points = [
      for (final s in source.wallSegments) ...[s.start.offset, s.end.offset],
      for (final t in source.traces) ...t.canvasPoints.map((p) => p.offset),
      for (final a in source.annotations) a.point.offset,
      for (final a in source.annotations)
        if (a.extraProperties['calloutTipX'] is num &&
            a.extraProperties['calloutTipY'] is num)
          Offset((a.extraProperties['calloutTipX'] as num).toDouble(),
              (a.extraProperties['calloutTipY'] as num).toDouble()),
      for (final stroke in source.freehandStrokes)
        ...stroke.points.map((p) => p.offset)
    ];
    if (points.isEmpty) return false;
    final w = points.map((p) => p.dx).reduce(math.max) -
        points.map((p) => p.dx).reduce(math.min);
    final h = points.map((p) => p.dy).reduce(math.max) -
        points.map((p) => p.dy).reduce(math.min);
    return h > math.max(w, 1) * 1.15;
  }
}
