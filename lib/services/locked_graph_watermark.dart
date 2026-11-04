import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../models/graph_document.dart';
import '../models/graph_shape.dart';

/// A presentation-only layer. The caller supplies server-confirmed lock state;
/// no watermark, lock flag or hit target is inserted into graph geometry.
abstract final class LockedGraphWatermark {
  static const assetPath = 'assets/branding/holloman_exterminators.png';
  static const opacity = 0.14;

  /// The caller owns the image and must dispose it with its editor state.
  static Future<ui.Image> loadLogo({AssetBundle? bundle}) async {
    final bytes = await (bundle ?? rootBundle).load(assetPath);
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// World-coordinate structure bounds, unaffected by zoom, notes, readings,
  /// photos or treatment areas. Empty diagrams rely on their Locked header.
  static ui.Rect? structureBounds(GraphDocument document,
      {bool includeFreehand = true}) {
    final treatmentSegments = <int>{
      for (final shape in document.shapes)
        if (shape.preset == GraphDrawingPreset.treatmentArea)
          ...shape.segmentIndexes,
    };
    final points = <ui.Offset>[
      for (var index = 0; index < document.wallSegments.length; index++)
        if (!treatmentSegments.contains(index))
          for (final segment in [document.wallSegments[index]]) ...[
            segment.start.offset,
            segment.end.offset,
            if (segment.controlPoint != null) segment.controlPoint!.offset,
          ],
      if (includeFreehand)
        for (final stroke in document.freehandStrokes)
          for (final point in stroke.points) point.offset,
    ].where((point) => point.dx.isFinite && point.dy.isFinite).toList();
    if (points.isEmpty) return null;
    var bounds = ui.Rect.fromPoints(points.first, points.first);
    for (final point in points.skip(1)) {
      bounds = bounds.expandToInclude(ui.Rect.fromPoints(point, point));
    }
    return bounds;
  }

  static ui.Rect? destination(ui.Rect? structureBounds, ui.Size logoSize) {
    if (structureBounds == null ||
        structureBounds.isEmpty ||
        !structureBounds.isFinite ||
        logoSize.isEmpty ||
        !logoSize.width.isFinite ||
        !logoSize.height.isFinite) {
      return null;
    }
    final available = ui.Size(
      structureBounds.width * 0.55,
      structureBounds.height * 0.35,
    );
    final ratio = logoSize.width / logoSize.height;
    var width = available.width;
    var height = width / ratio;
    if (height > available.height) {
      height = available.height;
      width = height * ratio;
    }
    return ui.Rect.fromCenter(
      center: structureBounds.center,
      width: width,
      height: height,
    );
  }

  /// Paint immediately before graph geometry in the shared live/export scene.
  /// The dark structure labels and readings then remain fully opaque above it.
  static void paint(
    ui.Canvas canvas, {
    required bool locked,
    required ui.Rect? structureBounds,
    required ui.Image? logo,
  }) {
    if (!locked || logo == null) return;
    final source = ui.Rect.fromLTWH(
      0,
      0,
      logo.width.toDouble(),
      logo.height.toDouble(),
    );
    final target = destination(structureBounds, source.size);
    if (target == null) return;
    canvas.save();
    canvas.clipRect(structureBounds!);
    canvas.drawImageRect(
      logo,
      source,
      target,
      ui.Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..color = const ui.Color(0xFFFFFFFF).withValues(alpha: opacity),
    );
    canvas.restore();
  }
}
