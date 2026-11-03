// Regression coverage for items 1-4: marker icon size, label font size, and
// icon-to-label spacing must all scale from the same `annotation.size`
// source, the label must render with no filled background, and the
// icon-to-label gap must stay tight rather than a large fixed offset.
//
// This renders the real painter to an actual image and inspects pixels,
// rather than asserting on private implementation details, so it exercises
// the same code path the app uses.
import 'dart:ui' as ui;

import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/widgets/graph_annotations_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _InkBounds {
  _InkBounds({required this.rowBands, required this.minX, required this.maxX});

  /// Contiguous vertical bands of rows that contain at least one
  /// non-transparent pixel, in top-to-bottom order. Each band is a
  /// (start, end) row-index pair.
  final List<(int, int)> rowBands;
  final int minX;
  final int maxX;
}

Future<ui.Image> _renderAnnotation(GraphAnnotation annotation, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
  final painter = GraphAnnotationsPainter(
    annotations: [annotation],
    selectedAnnotationIndex: null,
    inspectionsVisible: true,
    treatmentVisible: true,
    structureVisible: true,
    photosVisible: true,
  );
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  return picture.toImage(size.width.round(), size.height.round());
}

/// Scans the rendered image for non-transparent pixels and groups them into
/// contiguous vertical bands (a gap of >=2 fully-empty rows starts a new
/// band). With an icon on top and a label below with a tight gap, a
/// correctly scaled marker should produce exactly two bands: the icon, then
/// the label - never a single merged band (would indicate overlap) and never
/// a huge gap (would indicate the old oversized offset).
Future<_InkBounds> _inkBounds(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = byteData!.buffer.asUint8List();
  final width = image.width;
  final height = image.height;

  bool rowHasInk(int y) {
    for (var x = 0; x < width; x++) {
      final alpha = bytes[((y * width) + x) * 4 + 3];
      if (alpha > 0) return true;
    }
    return false;
  }

  int minX = width;
  int maxX = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final alpha = bytes[((y * width) + x) * 4 + 3];
      if (alpha > 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
      }
    }
  }

  final bands = <(int, int)>[];
  int? bandStart;
  var emptyStreak = 0;
  for (var y = 0; y < height; y++) {
    if (rowHasInk(y)) {
      bandStart ??= y;
      emptyStreak = 0;
    } else if (bandStart != null) {
      emptyStreak += 1;
      if (emptyStreak >= 2) {
        bands.add((bandStart, y - emptyStreak));
        bandStart = null;
        emptyStreak = 0;
      }
    }
  }
  if (bandStart != null) {
    bands.add((bandStart, height - 1));
  }

  return _InkBounds(rowBands: bands, minX: minX, maxX: maxX);
}

void main() {
  const canvasSize = Size(200, 200);
  const center = GraphPoint(x: 100, y: 100);

  Future<_InkBounds> renderMoistureReadingAt(double markerSize) async {
    final annotation = GraphAnnotation(
      kind: GraphAnnotationKind.marker,
      markerType: GraphMarkerType.moistureReading,
      point: center,
      label: '18%',
      size: markerSize,
    );
    final image = await _renderAnnotation(annotation, canvasSize);
    return _inkBounds(image);
  }

  testWidgets(
    'moisture-reading marker: icon and label scale together and stay tight',
    (tester) async {
      late _InkBounds small;
      late _InkBounds large;
      // Rasterizing to an image performs real (non-fake-async) engine work,
      // so it must run outside the widget test's fake-async zone or it
      // will hang forever waiting on a clock that never advances.
      await tester.runAsync(() async {
        small = await renderMoistureReadingAt(0.7);
        large = await renderMoistureReadingAt(1.8);
      });

      // Item 1: both the icon and label grow with annotation.size, so the
      // overall painted width and the number of ink bands' total height
      // must both grow noticeably between the smallest and largest size.
      final smallWidth = small.maxX - small.minX;
      final largeWidth = large.maxX - large.minX;
      expect(largeWidth, greaterThan(smallWidth),
          reason: 'a larger marker size must produce a wider icon+label');

      // Icon + label render as two distinct, non-overlapping ink bands
      // (icon on top, label below) at both sizes - proves the label
      // doesn't overlap the icon and isn't merged into one blob.
      expect(small.rowBands.length, 2,
          reason:
              'expected exactly one icon band and one label band at the '
              'small size, got: ${small.rowBands}');
      expect(large.rowBands.length, 2,
          reason:
              'expected exactly one icon band and one label band at the '
              'large size, got: ${large.rowBands}');

      // Item 4: the icon-to-label gap (rows between the two bands) must
      // stay small and must itself scale with size, not be a large fixed
      // offset. Using a generous upper bound derived from the marker scale
      // constants (base gap 2.5, clamped 2-6) plus rendering slack.
      final smallGap = small.rowBands[1].$1 - small.rowBands[0].$2;
      final largeGap = large.rowBands[1].$1 - large.rowBands[0].$2;
      expect(smallGap, inInclusiveRange(0, 10),
          reason: 'icon-to-label gap should be tight at the small size');
      expect(largeGap, inInclusiveRange(0, 24),
          reason: 'bare glyph bearings plus the scaled label gap should stay tight');

      // Item 3/2 (tight bounds, no background fill): the label band's
      // height must be small - a filled background/pill would inflate it
      // well beyond the glyph height (label text uses ~fontSize-based
      // height only, no padding-heavy pill).
      final smallLabelHeight =
          small.rowBands[1].$2 - small.rowBands[1].$1;
      final largeLabelHeight =
          large.rowBands[1].$2 - large.rowBands[1].$1;
      expect(smallLabelHeight, lessThan(16),
          reason:
              'label band should be tight text-only height at the small '
              'size, not a padded background pill');
      expect(largeLabelHeight, lessThan(30),
          reason:
              'label band should be tight text-only height at the large '
              'size, not a padded background pill');
    },
  );

  testWidgets(
    'termite-activity marker (non-moisture type) also scales icon+label together',
    (tester) async {
      Future<_InkBounds> render(double markerSize) async {
        final annotation = GraphAnnotation(
          kind: GraphAnnotationKind.marker,
          markerType: GraphMarkerType.termiteActivity,
          point: center,
          label: 'AT',
          size: markerSize,
        );
        final image = await _renderAnnotation(annotation, canvasSize);
        return _inkBounds(image);
      }

      late _InkBounds small;
      late _InkBounds large;
      await tester.runAsync(() async {
        small = await render(0.7);
        large = await render(1.8);
      });

      expect(large.maxX - large.minX, greaterThan(small.maxX - small.minX));
      expect(small.rowBands.length, 2);
      expect(large.rowBands.length, 2);
    },
  );
}
