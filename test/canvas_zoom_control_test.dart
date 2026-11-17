import 'package:bugman_graphs/widgets/canvas_zoom_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('track tap zooms to its position in $direction',
        (tester) async {
      var value = 0.5;
      await tester.pumpWidget(MaterialApp(
          home: Directionality(
        textDirection: direction,
        child: Center(
            child: SizedBox(
                width: 220,
                child: StatefulBuilder(
                  builder: (context, update) => CanvasZoomControl(
                      value: value,
                      color: Colors.red,
                      formatValue: (value) => '$value',
                      onChanged: (next) => update(() => value = next)),
                ))),
      )));
      final rect = tester.getRect(find.byType(CanvasZoomControl));
      await tester.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));
      await tester.pump();
      expect(value,
          direction == TextDirection.ltr ? greaterThan(.5) : lessThan(.5));
      await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
      await tester.pump();
      expect(value, direction == TextDirection.ltr ? 0 : 1);
    });
  }
}
