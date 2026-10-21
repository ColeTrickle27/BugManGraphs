import 'dart:typed_data';
import 'package:printing/src/interface.dart';
import 'package:printing/src/method_channel.dart';
import 'package:printing/printing.dart';

/// Platform-channel substitute for upload workflow tests only.
/// Real PDF raster parity is exercised in the local browser review harness.
void Function() installTestRasterizer() {
  final original = PrintingPlatform.instance;
  PrintingPlatform.instance = _RasterPlatform();
  return () => PrintingPlatform.instance = original;
}

class _RasterPlatform extends MethodChannelPrinting {
  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) async* {
    if (String.fromCharCodes(document.take(4)) != '%PDF') {
      throw StateError('Expected the composed PDF');
    }
    yield PdfRaster(2, 2, Uint8List.fromList(List.filled(16, 255)));
  }
}
