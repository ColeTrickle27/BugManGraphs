import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/graph_annotation.dart';

abstract final class CalloutGeometry {
  static Offset? tip(GraphAnnotation a) {
    final x = a.extraProperties['calloutTipX'];
    final y = a.extraProperties['calloutTipY'];
    return x is num && y is num && x.isFinite && y.isFinite
        ? Offset(x.toDouble(), y.toDouble())
        : null;
  }

  static double width(GraphAnnotation a) {
    final value = a.extraProperties['calloutWidth'];
    return value is num && value.isFinite
        ? value.toDouble().clamp(128, 720)
        : 240;
  }

  static TextPainter text(GraphAnnotation a) => TextPainter(
        text: TextSpan(
            text: a.label,
            style: TextStyle(
                color: a.textColor,
                fontSize: a.fontSize,
                fontWeight: a.bold ? FontWeight.w800 : FontWeight.w600,
                fontStyle: a.italic ? FontStyle.italic : FontStyle.normal)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: width(a) - 30);
  static Rect box(GraphAnnotation a) {
    final painter = text(a);
    final explicit = a.extraProperties['calloutHeight'];
    final minimum = explicit is num && explicit.isFinite
        ? explicit.toDouble().clamp(48, 1200)
        : 48.0;
    return Rect.fromCenter(
        center: a.point.offset,
        width: width(a),
        height: math.max(minimum, painter.height + 22).toDouble());
  }

  static Rect bounds(GraphAnnotation a) {
    final anchor = tip(a);
    final rect = box(a);
    return anchor == null
        ? rect
        : rect.expandToInclude(Rect.fromCircle(center: anchor, radius: 8));
  }
}
