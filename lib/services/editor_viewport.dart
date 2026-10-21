import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Screen magnification only; never changes saved coordinates or calibration.
abstract final class EditorViewport {
  static const minScale = 0.01;
  static const maxScale = 32.0;
  static const percentages = <double>[
    1,
    5,
    10,
    25,
    50,
    75,
    100,
    200,
    400,
    800,
    1600,
    3200
  ];
  static String label(Matrix4 matrix) {
    final percent = matrix.getMaxScaleOnAxis() * 100;
    return '${percent < 10 ? percent.toStringAsFixed(1) : percent.round()}%';
  }

  static Matrix4 zoomAt(Matrix4 current, Offset anchor, double scale) {
    final nextScale = scale.clamp(minScale, maxScale);
    final scene = MatrixUtils.transformPoint(Matrix4.inverted(current), anchor);
    return Matrix4.identity()
      ..setEntry(0, 0, nextScale)
      ..setEntry(1, 1, nextScale)
      ..setEntry(2, 2, nextScale)
      ..setEntry(0, 3, anchor.dx - scene.dx * nextScale)
      ..setEntry(1, 3, anchor.dy - scene.dy * nextScale);
  }

  static Matrix4 fit(Rect bounds, Rect viewport, {double padding = 32}) {
    final available = viewport.deflate(padding);
    final scale = math
        .min(available.width / math.max(bounds.width, 1),
            available.height / math.max(bounds.height, 1))
        .clamp(minScale, maxScale);
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, viewport.center.dx - bounds.center.dx * scale)
      ..setEntry(1, 3, viewport.center.dy - bounds.center.dy * scale);
  }
}
