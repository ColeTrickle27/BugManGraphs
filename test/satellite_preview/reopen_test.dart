import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/satellite_preview.dart';

void main() {
  testWidgets('returned sample graph is reachable from the preview home',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SatellitePreviewHome()));
    await tester.pumpAndSettle();
    expect(find.text('Save Trace'), findsOneWidget);
    await tester.tap(find.text('Save Trace'));
    await tester.pumpAndSettle();
    // Leave the real canvas without changing the sample geometry.
    final navigator = Navigator.of(tester.element(find.byType(Scaffold).last));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('View saved preview graph'), findsOneWidget);
    await tester.tap(find.text('View saved preview graph'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Net yard: 1.82 ac'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
