import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:printing/printing.dart';

/// PNG is rendered from the completed PDF, including every appendix page.
/// Multiple pages form one vertical strip, with a 24px neutral page gutter.
abstract final class GraphPdfRaster {
  static Future<Uint8List> png(Uint8List pdf, {double dpi = 144}) async {
    final images = <ui.Image>[];
    try {
      await for (final page in Printing.raster(pdf, dpi: dpi)) {
        images.add(await page.toImage());
      }
      if (images.isEmpty) throw StateError('PDF has no renderable pages');
      final width = images.map((i) => i.width).reduce((a, b) => a > b ? a : b);
      final height = images.fold<int>(0, (sum, i) => sum + i.height) +
          (images.length - 1) * 24;
      if (width > 16384 || height > 32768 || width * height > 64000000) {
        throw StateError(
            'PNG page strip exceeds the safe image size; export PDF');
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFFE8E8E8), ui.BlendMode.src);
      var y = 0.0;
      for (final image in images) {
        canvas.drawImage(
            image, ui.Offset((width - image.width) / 2, y), ui.Paint());
        y += image.height + 24;
      }
      final picture = recorder.endRecording();
      final composed = await picture.toImage(width, height);
      picture.dispose();
      try {
        return (await composed.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
      } finally {
        composed.dispose();
      }
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }
}
