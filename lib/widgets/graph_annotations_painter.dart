import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/graph_annotation.dart';
import '../models/graph_marker_catalog.dart';
import 'graph_marker_visual.dart';

class GraphAnnotationsPainter extends CustomPainter {
  const GraphAnnotationsPainter({
    this.sceneBounds,
    required this.annotations,
    required this.selectedAnnotationIndex,
    this.hoveredAnnotationIndex,
    required this.inspectionsVisible,
    required this.treatmentVisible,
    required this.structureVisible,
    required this.photosVisible,
  });

  final List<GraphAnnotation> annotations;
  final Rect? sceneBounds;
  final int? selectedAnnotationIndex;
  final int? hoveredAnnotationIndex;
  final bool inspectionsVisible;
  final bool treatmentVisible;
  final bool structureVisible;
  final bool photosVisible;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < annotations.length; i += 1) {
      final annotation = annotations[i];
      if (!_isVisible(annotation)) {
        continue;
      }

      final calloutTip = _calloutTip(annotation);
      if (calloutTip != null) {
        _drawTreatmentCallout(canvas, annotation, calloutTip, size);
      } else {
        switch (annotation.kind) {
          case GraphAnnotationKind.marker:
            _drawMarker(canvas, annotation, size);
            break;
          case GraphAnnotationKind.photo:
            _drawPhotoPin(canvas, annotation);
            break;
          case GraphAnnotationKind.text:
            _drawTextLabel(canvas, annotation);
            break;
        }
      }

      if (i == selectedAnnotationIndex) {
        _drawSelectionBox(canvas, annotation);
      } else if (i == hoveredAnnotationIndex) {
        canvas.drawCircle(
          annotation.point.offset,
          25 * annotation.size,
          Paint()
            ..color = const Color(0xFF2F80ED).withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }
  }

  bool _isVisible(GraphAnnotation annotation) {
    return switch (annotation.kind) {
      GraphAnnotationKind.marker
          when utilityMarkerTypes.contains(annotation.markerType) =>
        structureVisible,
      GraphAnnotationKind.marker
          when isTreatmentMarker(annotation.markerType) =>
        treatmentVisible,
      GraphAnnotationKind.marker ||
      GraphAnnotationKind.text =>
        inspectionsVisible,
      GraphAnnotationKind.photo => photosVisible,
    };
  }

  void _drawSelectionBox(Canvas canvas, GraphAnnotation annotation) {
    final center = annotation.point.offset;
    final rect = Rect.fromCenter(center: center, width: 84, height: 66);
    final selectedPaint = Paint()
      ..color = const Color(0xFF2F80ED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(rect, selectedPaint);

    for (final handleCenter in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final handle = Rect.fromCenter(
        center: handleCenter,
        width: 10,
        height: 10,
      );
      canvas.drawRect(handle, Paint()..color = Colors.white);
      canvas.drawRect(handle, selectedPaint);
    }
  }

  void _drawMarker(Canvas canvas, GraphAnnotation annotation, Size canvasSize) {
    final center = annotation.point.offset;
    final color = annotation.color ?? annotation.markerType.defaultColor;
    final iconSize = 34 * annotation.size;
    final icon = iconForGraphMarker(annotation.markerType);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(annotation.rotationDegrees * 3.1415926535 / 180);
    canvas.drawCircle(
      const Offset(1.5, 2),
      iconSize * 0.34,
      Paint()..color = const Color.fromRGBO(0, 0, 0, 0.16),
    );
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          inherit: false,
          color: color,
          fontSize: iconSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(-iconPainter.width / 2, -iconPainter.height / 2),
    );

    canvas.restore();
    // Marker labels always scale from the same `annotation.size` value used
    // for the icon, so icon size, font size, and icon-to-label spacing stay
    // proportional to one another instead of drifting independently.
    final labelFontSize = (_markerLabelBaseFontSize * annotation.size)
        .clamp(_markerLabelMinFontSize, _markerLabelMaxFontSize)
        .toDouble();
    final labelGap = (_markerLabelBaseGap * annotation.size)
        .clamp(_markerLabelMinGap, _markerLabelMaxGap)
        .toDouble();
    final iconBottom = center.dy + (iconPainter.height / 2);
    _drawSmallLabel(
      canvas,
      center,
      annotation.label,
      topCenter: Offset(center.dx, iconBottom + labelGap),
      leadingIcon: noticeIconForGraphAnnotation(annotation),
      leadingIconColor: color,
      textColor: Colors.black,
      fontWeight: FontWeight.w800,
      fontSize: labelFontSize,
      backgroundColor: Colors.transparent,
      borderColor: Colors.transparent,
      horizontalPadding: _markerLabelHorizontalPadding,
      verticalPadding: _markerLabelVerticalPadding,
    );
  }

  // Marker label scale constants. All derived from `annotation.size`, the
  // same value that drives icon size, so the two never scale independently.
  static const double _markerLabelBaseFontSize = 12;
  static const double _markerLabelMinFontSize = 9;
  static const double _markerLabelMaxFontSize = 22;
  static const double _markerLabelBaseGap = 2.5;
  static const double _markerLabelMinGap = 2;
  static const double _markerLabelMaxGap = 6;
  static const double _markerLabelHorizontalPadding = 2;
  static const double _markerLabelVerticalPadding = 1;

  Offset? _calloutTip(GraphAnnotation annotation) {
    final x = annotation.extraProperties['calloutTipX'];
    final y = annotation.extraProperties['calloutTipY'];
    if (x is! num || y is! num) return null;
    return Offset(x.toDouble(), y.toDouble());
  }

  void _drawTreatmentCallout(
    Canvas canvas,
    GraphAnnotation annotation,
    Offset tip,
    Size canvasSize,
  ) {
    final requestedCenter = annotation.point.offset;
    final textPainter = TextPainter(
      text: TextSpan(
        text: annotation.label,
        style: TextStyle(
          color: annotation.textColor,
          fontSize: annotation.fontSize,
          fontWeight: annotation.bold ? FontWeight.w800 : FontWeight.w600,
          fontStyle: annotation.italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 210);
    final width = math.max(128.0, textPainter.width + 30);
    final height = math.max(48.0, textPainter.height + 22);
    final center = Offset(
      requestedCenter.dx
          .clamp((sceneBounds?.left ?? 0) + width / 2,
              (sceneBounds?.right ?? canvasSize.width) - width / 2)
          .toDouble(),
      requestedCenter.dy
          .clamp((sceneBounds?.top ?? 0) + height / 2,
              (sceneBounds?.bottom ?? canvasSize.height) - height / 2)
          .toDouble(),
    );
    final rect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );
    final box = RRect.fromRectAndRadius(rect, const Radius.circular(7));
    final nearest = Offset(
      tip.dx.clamp(rect.left, rect.right),
      tip.dy.clamp(rect.top, rect.bottom),
    );
    final linePaint = Paint()
      ..color = annotation.borderColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(tip, nearest, linePaint);
    final direction = (nearest - tip);
    if (direction.distance > 0) {
      final unit = direction / direction.distance;
      final left = Offset(-unit.dy, unit.dx);
      final arrow = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          tip.dx + (unit.dx * 13) + (left.dx * 6),
          tip.dy + (unit.dy * 13) + (left.dy * 6),
        )
        ..lineTo(
          tip.dx + (unit.dx * 13) - (left.dx * 6),
          tip.dy + (unit.dy * 13) - (left.dy * 6),
        )
        ..close();
      canvas.drawPath(arrow, Paint()..color = annotation.borderColor);
    }
    canvas.drawRRect(box, Paint()..color = annotation.backgroundColor);
    canvas.drawRRect(box, linePaint);
    textPainter.paint(
      canvas,
      Offset(
        center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2),
      ),
    );
  }

  void _drawPhotoPin(Canvas canvas, GraphAnnotation annotation) {
    final center = annotation.point.offset;
    final rect = Rect.fromCenter(center: center, width: 54, height: 38);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(7));
    final fillPaint = Paint()..color = const Color(0xFF2C6F9F);
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
      rrect.shift(const Offset(2, 3)),
      Paint()..color = const Color.fromRGBO(0, 0, 0, 0.16),
    );
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);
    canvas.drawCircle(center, 8, Paint()..color = Colors.white);
    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFF2C6F9F));
    if (annotation.attachmentIds.length > 1) {
      final badgeCenter = rect.topRight + const Offset(2, -2);
      canvas.drawCircle(
        badgeCenter,
        11,
        Paint()..color = const Color(0xFFCC2000),
      );
      final badgeText = TextPainter(
        text: TextSpan(
          text: '${annotation.attachmentIds.length}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      badgeText.paint(
        canvas,
        badgeCenter - Offset(badgeText.width / 2, badgeText.height / 2),
      );
    }
    _drawSmallLabel(canvas, center + const Offset(0, 32), annotation.label);
  }

  void _drawTextLabel(Canvas canvas, GraphAnnotation annotation) {
    _drawSmallLabel(
      canvas,
      annotation.point.offset,
      annotation.label,
      textColor: annotation.textColor,
      fontSize: annotation.fontSize,
      fontWeight: annotation.bold ? FontWeight.w800 : FontWeight.w500,
      fontStyle: annotation.italic ? FontStyle.italic : FontStyle.normal,
      backgroundColor: annotation.backgroundColor,
      borderColor: annotation.borderColor,
    );
  }

  /// Draws a compact label with optional leading icon.
  ///
  /// By default the label is centered on [center]. Pass [topCenter] to
  /// instead anchor the label so its top edge sits at that point (used by
  /// marker labels so the gap between the icon and the label stays tight and
  /// scales with the marker rather than being measured from a fixed center
  /// offset).
  void _drawSmallLabel(
    Canvas canvas,
    Offset center,
    String label, {
    Offset? topCenter,
    Color textColor = const Color(0xFF1C2B22),
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w700,
    FontStyle fontStyle = FontStyle.normal,
    Color backgroundColor = Colors.white,
    Color borderColor = const Color(0xFFD1CCBF),
    IconData? leadingIcon,
    Color? leadingIconColor,
    double horizontalPadding = 8,
    double verticalPadding = 4,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 150);
    final iconPainter = leadingIcon == null
        ? null
        : (TextPainter(
            text: TextSpan(
              text: String.fromCharCode(leadingIcon.codePoint),
              style: TextStyle(
                inherit: false,
                color: leadingIconColor ?? textColor,
                fontSize: fontSize + 2,
                fontFamily: leadingIcon.fontFamily,
                package: leadingIcon.fontPackage,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout());
    final iconSpacing = iconPainter == null ? 0.0 : 5.0;
    final contentWidth =
        textPainter.width + (iconPainter?.width ?? 0) + iconSpacing;
    final contentHeight = math.max(
      textPainter.height,
      iconPainter?.height ?? 0,
    );
    final totalHeight = contentHeight + (verticalPadding * 2);
    final labelCenter = topCenter == null
        ? center
        : Offset(topCenter.dx, topCenter.dy + (totalHeight / 2));

    final labelRect = Rect.fromCenter(
      center: labelCenter,
      width: contentWidth + (horizontalPadding * 2),
      height: totalHeight,
    );
    final labelRRect = RRect.fromRectAndRadius(
      labelRect,
      const Radius.circular(5),
    );

    if (backgroundColor.a > 0) {
      canvas.drawRRect(labelRRect, Paint()..color = backgroundColor);
    }
    if (borderColor.a > 0) {
      canvas.drawRRect(
        labelRRect,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final contentLeft = labelCenter.dx - (contentWidth / 2);
    if (iconPainter != null) {
      iconPainter.paint(
        canvas,
        Offset(
          contentLeft,
          labelCenter.dy - (iconPainter.height / 2),
        ),
      );
    }
    textPainter.paint(
      canvas,
      Offset(
        contentLeft + (iconPainter?.width ?? 0) + iconSpacing,
        labelCenter.dy - (textPainter.height / 2),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant GraphAnnotationsPainter oldDelegate) {
    return oldDelegate.sceneBounds != sceneBounds ||
        oldDelegate.annotations != annotations ||
        oldDelegate.selectedAnnotationIndex != selectedAnnotationIndex ||
        oldDelegate.hoveredAnnotationIndex != hoveredAnnotationIndex ||
        oldDelegate.inspectionsVisible != inspectionsVisible ||
        oldDelegate.treatmentVisible != treatmentVisible ||
        oldDelegate.structureVisible != structureVisible ||
        oldDelegate.photosVisible != photosVisible;
  }
}
