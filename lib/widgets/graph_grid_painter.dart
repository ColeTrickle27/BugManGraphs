import 'package:flutter/material.dart';

class GraphGridPainter extends CustomPainter {
  const GraphGridPainter({
    this.visible = true,
    this.sceneBounds,
  });

  final bool visible;
  final Rect? sceneBounds;

  @override
  void paint(Canvas canvas, Size size) {
    const smallGrid = 24.0;
    const majorGrid = smallGrid * 4;

    final backgroundPaint = Paint()..color = Colors.white;
    final smallGridPaint = Paint()
      ..color = const Color(0xFFE8E5DD)
      ..strokeWidth = 1;
    final majorGridPaint = Paint()
      ..color = const Color(0xFFD1CCBF)
      ..strokeWidth = 1.4;

    final bounds = sceneBounds ?? Offset.zero & size;
    canvas.drawRect(bounds, backgroundPaint);

    if (!visible) {
      return;
    }

    for (double x = (bounds.left / smallGrid).floor() * smallGrid;
        x <= bounds.right;
        x += smallGrid) {
      final paint = x % majorGrid == 0 ? majorGridPaint : smallGridPaint;
      canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), paint);
    }

    for (double y = (bounds.top / smallGrid).floor() * smallGrid;
        y <= bounds.bottom;
        y += smallGrid) {
      final paint = y % majorGrid == 0 ? majorGridPaint : smallGridPaint;
      canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GraphGridPainter oldDelegate) {
    return oldDelegate.visible != visible ||
        oldDelegate.sceneBounds != sceneBounds;
  }
}
