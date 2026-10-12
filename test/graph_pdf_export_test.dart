import 'dart:convert';

import 'package:bugman_graphs/services/graph_pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('builds a PDF graph with labeled photo appendix pages', () async {
    final onePixelPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    final graphOnly = await GraphPdfExport.build(
      graphPng: onePixelPng,
      title: 'PDF Test',
    );
    final bytes = await GraphPdfExport.build(
      graphPng: onePixelPng,
      title: 'PDF Test',
      photos: [
        GraphPdfPhoto(
          referenceLabel: '1a',
          filename: 'crawlspace.jpg',
          bytes: onePixelPng,
        ),
      ],
    );

    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(500));
    expect(bytes.length, greaterThan(graphOnly.length));
  });
}
