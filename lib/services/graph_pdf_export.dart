import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'graph_export_legend.dart';

class GraphPdfPhoto {
  const GraphPdfPhoto({
    required this.referenceLabel,
    required this.filename,
    required this.bytes,
  });

  final String referenceLabel;
  final String filename;
  final Uint8List bytes;
}

class GraphMeasurementSummary {
  const GraphMeasurementSummary({
    required this.label,
    required this.measurements,
  });

  final String label;
  final List<String> measurements;
}

class GraphPdfExport {
  const GraphPdfExport._();

  static Future<Uint8List> build({
    required Uint8List graphPng,
    required String title,
    List<GraphLegendSection> legend = const [],
    List<GraphMeasurementSummary> measurementSummary = const [],
    List<GraphPdfPhoto> photos = const [],
    Uint8List? brandingLogo,
    Uint8List? markerIconFontBytes,
    ByteData? documentFont,
    ByteData? documentBoldFont,
  }) async {
    final document = pw.Document(
      title: title,
      creator: 'BugMan Graphs',
      theme: documentFont == null
          ? null
          : pw.ThemeData.withFont(
              base: pw.Font.ttf(documentFont),
              bold: pw.Font.ttf(documentBoldFont ?? documentFont)),
    );
    final image = pw.MemoryImage(graphPng);
    final logo = brandingLogo == null ? null : pw.MemoryImage(brandingLogo);
    final markerIconFont = markerIconFontBytes == null
        ? null
        : pw.Font.ttf(markerIconFontBytes.buffer.asByteData());
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 12),
                    child: pw.Image(logo, height: 30, fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Holloman Exterminators',
                        style: const pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.red800,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        title,
                        style: const pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  'Inspection Graph',
                  style:
                      const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(height: 1, color: PdfColors.red800),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            ),
            if (legend.isNotEmpty || measurementSummary.isNotEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (measurementSummary.isNotEmpty)
                      pw.Expanded(
                        child: _section(
                          'Measurement Summary',
                          measurementSummary
                              .map((item) => pw.Padding(
                                    padding:
                                        const pw.EdgeInsets.only(bottom: 2),
                                    child: pw.RichText(
                                      text: pw.TextSpan(
                                        text: '${item.label}: ',
                                        style: const pw.TextStyle(
                                            fontSize: 8,
                                            fontWeight: pw.FontWeight.bold),
                                        children: [
                                          pw.TextSpan(
                                              text:
                                                  item.measurements.join('  '),
                                              style: const pw.TextStyle(
                                                  fontWeight:
                                                      pw.FontWeight.normal))
                                        ],
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    if (measurementSummary.isNotEmpty && legend.isNotEmpty)
                      pw.SizedBox(width: 14),
                    if (legend.isNotEmpty)
                      pw.Expanded(
                        child: _section(
                          'Legend',
                          [
                            for (final section in legend)
                              pw.Wrap(
                                spacing: 8,
                                runSpacing: 3,
                                children: [
                                  for (final entry in section.entries)
                                    pw.Row(
                                      mainAxisSize: pw.MainAxisSize.min,
                                      children: [
                                        if (markerIconFont != null)
                                          pw.Text(
                                            String.fromCharCode(
                                                entry.icon.codePoint),
                                            style: pw.TextStyle(
                                              font: markerIconFont,
                                              fontSize: 10,
                                              color: PdfColor.fromInt(
                                                entry.color.toARGB32(),
                                              ),
                                            ),
                                          )
                                        else
                                          pw.Container(
                                            width: 7,
                                            height: 7,
                                            color: PdfColor.fromInt(
                                              entry.color.toARGB32(),
                                            ),
                                          ),
                                        pw.SizedBox(width: 3),
                                        pw.Text(
                                            '${entry.markerType.shortLabel} ${entry.markerType.label}',
                                            style: const pw.TextStyle(
                                                fontSize: 7)),
                                      ],
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    for (var start = 0; start < photos.length; start += 2) {
      final pagePhotos = photos.skip(start).take(2).toList(growable: false);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '$title - Photo Appendix',
                style: const pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 16),
              for (final photo in pagePhotos)
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 14),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${photo.referenceLabel}  ${photo.filename}',
                          style: const pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Expanded(
                          child: pw.Center(
                            child: pw.Image(
                              pw.MemoryImage(photo.bytes),
                              fit: pw.BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return document.save();
  }

  static pw.Widget _section(String title, List<pw.Widget> children) =>
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style: const pw.TextStyle(
                    fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            ...children,
          ],
        ),
      );
}
