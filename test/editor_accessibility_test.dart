import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/crowded_canvas_fixture.dart';

void main() {
  testWidgets('icon commands have button names before hover', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
          home: GraphCanvasScreen(document: crowdedCanvasFixture())));
      await tester.pumpAndSettle();
      for (final label in [
        'Zoom out',
        'Zoom in',
        'Fit drawing',
        'Reset zoom to 100%',
        'Object properties',
        'Layers panel',
        'Delete selection'
      ]) {
        final button = find.descendant(
            of: find.byTooltip(label), matching: find.byType(IconButton));
        expect(button, findsOneWidget, reason: label);
        expect(tester.getSemantics(button).label, label,
            reason: 'The actionable button must be named without hover.');
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Tab leaves drawing mode without finishing or changing geometry',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final document = crowdedCanvasFixture();
    await tester
        .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    final before = document.toJson();
    final focused = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(same(focused)));
    expect(find.text('Place the first structure point before finishing'),
        findsNothing);
    expect(document.toJson(), before);
  });

  testWidgets('Space activates focused toolbar instead of starting canvas pan',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: GraphCanvasScreen(document: crowdedCanvasFixture())));
    await tester.pumpAndSettle();
    bool toolsFocused() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<FloatingActionButton>()
            ?.key ==
        const ValueKey('canvas-tools-button');
    for (var step = 0; step < 40 && !toolsFocused(); step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(toolsFocused(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Tools'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('zoom accepts keyboard adjustment and preserves graph data',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final document = crowdedCanvasFixture();
    await tester
        .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
    await tester.pumpAndSettle();
    final before = document.toJson();
    for (var step = 0;
        step < 40 &&
            FocusManager.instance.primaryFocus?.debugLabel != 'Canvas zoom';
        step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Canvas zoom');
    final oldZoom = tester
        .widget<Text>(find.byKey(const ValueKey('viewport-zoom-label')))
        .data;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('viewport-zoom-label')))
            .data,
        isNot(oldZoom));
    expect(document.toJson(), before);
    final zoomFocus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNot(same(zoomFocus)));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(zoomFocus));
    expect(document.toJson(), before);
  });
}
