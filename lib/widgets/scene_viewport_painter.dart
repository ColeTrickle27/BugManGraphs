import 'package:flutter/material.dart';

/// Paint only the visible viewport while retaining unbounded world coordinates.
/// The viewport matrix never changes stored geometry or physical calibration.
class SceneViewportPainter extends CustomPainter {
  SceneViewportPainter(
      {required this.controller,
      required this.paintScene,
      required this.gridVisible})
      : super(repaint: controller);
  final TransformationController controller;
  final void Function(Canvas, Size) paintScene;
  final bool gridVisible;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.transform(controller.value.storage);
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height)
    ].map(controller.toScene).toList();
    final bounds = corners.fold<Rect>(
        Rect.fromPoints(corners.first, corners.first),
        (r, p) => r.expandToInclude(Rect.fromPoints(p, p)));
    if (gridVisible) {
      final scale = controller.value.getMaxScaleOnAxis();
      final minor = Paint()
        ..color = const Color(0xFFE8E5DD)
        ..strokeWidth = 1 / scale;
      final major = Paint()
        ..color = const Color(0xFFD1CCBF)
        ..strokeWidth = 1.4 / scale;
      for (var x = (bounds.left / 24).floor() * 24.0;
          x <= bounds.right;
          x += 24) {
        canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom),
            x % 96 == 0 ? major : minor);
      }
      for (var y = (bounds.top / 24).floor() * 24.0;
          y <= bounds.bottom;
          y += 24) {
        canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y),
            y % 96 == 0 ? major : minor);
      }
    }
    paintScene(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SceneViewportPainter oldDelegate) => true;
}
