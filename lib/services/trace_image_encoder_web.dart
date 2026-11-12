import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:web/web.dart' as web;

// Use the browser encoder instead of decoding a PNG and encoding JPEG in Dart
// on the phone's UI thread. Keep the existing resolution and JPEG quality.
Future<Uint8List> encodeTraceImage(ui.Image image) async {
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (rgba == null) {
    throw const FormatException('Could not read satellite image');
  }
  final canvas = web.HTMLCanvasElement()
    ..width = image.width
    ..height = image.height;
  try {
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (context == null) throw StateError('Image encoding is unavailable');
    final pixels = Uint8ClampedList.view(
        rgba.buffer, rgba.offsetInBytes, rgba.lengthInBytes);
    context.putImageData(
        web.ImageData(pixels.toJS, image.width, image.height.toJS), 0, 0);
    final encoded = Completer<web.Blob>();
    canvas.toBlob(
        ((web.Blob? blob) {
          if (blob == null || blob.type != 'image/jpeg') {
            encoded
                .completeError(StateError('Could not encode satellite image'));
          } else {
            encoded.complete(blob);
          }
        }).toJS,
        'image/jpeg',
        .85.toJS);
    final blob = await encoded.future.timeout(const Duration(seconds: 8));
    return (await blob.arrayBuffer().toDart).toDart.asUint8List();
  } finally {
    canvas.width = 0;
    canvas.height = 0;
  }
}
