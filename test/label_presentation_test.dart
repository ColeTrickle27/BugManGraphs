import 'package:bugman_graphs/editor/label_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screen labels stay bounded across zoom and text-size settings', () {
    for (final zoom in [0.03, 0.1, 0.5, 1.0, 3.0, 10.0]) {
      for (final textScale in [0.7, 1.0, 1.6]) {
        final labels = LabelPresentation(zoom: zoom, textScale: textScale, bounded: true);
        for (final font in [12.0, 15.0, 17.0, 24.0]) {
          expect(labels.fontSize(font) * zoom, inInclusiveRange(12.0 - 0.001, 26.0 + 0.001));
        }
      }
    }
    expect(const LabelPresentation().fontSize(17), 17);
  });
}
