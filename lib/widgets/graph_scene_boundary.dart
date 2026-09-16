import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Extends the painted world while keeping stored points and view transforms
/// in their original coordinate system, including negative coordinates.
class GraphSceneBoundary extends RepaintBoundary {
  const GraphSceneBoundary(
      {super.key, required this.sceneBounds, required super.child});

  final Rect sceneBounds;

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      GraphSceneRenderBoundary(sceneBounds);

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderRepaintBoundary renderObject) {
    (renderObject as GraphSceneRenderBoundary).sceneBounds = sceneBounds;
  }
}

class GraphSceneRenderBoundary extends RenderRepaintBoundary {
  GraphSceneRenderBoundary(this._sceneBounds);
  Rect _sceneBounds;

  set sceneBounds(Rect value) {
    if (value == _sceneBounds) return;
    _sceneBounds = value;
    markNeedsPaint();
  }

  @override
  Rect get paintBounds => _sceneBounds;

  Future<ui.Image> captureBounds(Rect bounds, {required double pixelRatio}) =>
      (layer! as OffsetLayer).toImage(bounds, pixelRatio: pixelRatio);
}
