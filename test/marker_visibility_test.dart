import 'dart:ui' as ui;
import 'package:bugman_graphs/editor/label_presentation.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/widgets/graph_annotations_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  test('zoomed-out visible marker label remains selectable', () {
    const marker = GraphAnnotation(
        kind: GraphAnnotationKind.marker,
        point: GraphPoint(x: 0, y: 0),
        label: 'Long detailed location',
        markerType: GraphMarkerType.hvacUnit);
    const labels = LabelPresentation(zoom: .03, bounded: true);
    // Near the lower edge of the12px label beneath an18px symbol.
    expect(
        GraphAnnotationsPainter.containsPoint(
            marker, const Offset(40 / .03, 21 / .03), labels),
        true);
  });
  for (final type in [
    GraphMarkerType.stepsFront,
    GraphMarkerType.steps,
    GraphMarkerType.hvacUnit,
    GraphMarkerType.gasLine,
    GraphMarkerType.waterLine
  ]) {
    for (final zoom in [.03, .13, 1.0, 3.0]) {
      test('$type symbol remains visible at screen zoom $zoom', () async {
        final marker = GraphAnnotation(
            kind: GraphAnnotationKind.marker,
            point: const GraphPoint(x: 0, y: 0),
            label: '',
            markerType: type);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.translate(50, 50);
        canvas.scale(zoom);
        GraphAnnotationsPainter(
                labels: LabelPresentation(zoom: zoom, bounded: true),
                annotations: [marker],
                selectedAnnotationIndex: null,
                inspectionsVisible: true,
                treatmentVisible: true,
                structureVisible: true,
                photosVisible: true)
            .paint(canvas, const Size(100, 100));
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 100);
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final xs = <int>[], ys = <int>[];
        for (var y = 0; y < 100; y++) {
          for (var x = 0; x < 100; x++) {
            if (bytes.getUint8((y * 100 + x) * 4 + 3) > 100) {
              xs.add(x);
              ys.add(y);
            }
          }
        }
        expect(xs, isNotEmpty);
        xs.sort();
        ys.sort();
        expect(xs.last - xs.first + 1, greaterThanOrEqualTo(12));
        expect(ys.last - ys.first + 1, greaterThanOrEqualTo(1));
        expect(marker.size, 1);
        expect(marker.point.x, 0);
        image.dispose();
        picture.dispose();
      });
    }
  }
}
