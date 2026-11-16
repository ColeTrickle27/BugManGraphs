import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Future<Uint8List> encodeTraceImage(ui.Image image) async {
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) {
    throw const FormatException('Could not read satellite image');
  }
  return compute(
      _jpeg, png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
}

Uint8List _jpeg(Uint8List png) {
  final image = img.decodePng(png);
  if (image == null) {
    throw const FormatException('Could not decode satellite image');
  }
  return img.encodeJpg(image, quality: 85);
}
