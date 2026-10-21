import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/widgets/canvas_toolbar.dart';
import 'package:bugman_graphs/editor/editor_interaction_controller.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_shape.dart';

const actions = [
  CanvasToolbarAction.tool(CanvasTool.select),
  CanvasToolbarAction.tool(CanvasTool.pan),
  CanvasToolbarAction.tool(CanvasTool.text),
  CanvasToolbarAction.preset(GraphDrawingPreset.mainStructure),
  CanvasToolbarAction.marker(GraphMarkerType.treatmentNote)
];

void main() {
  testWidgets(
      'expandable desktop labels track actions and outside clicks never reset the drawing tool',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    var selected = CanvasTool.select;
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: CanvasQuickToolbar(
                      actions: actions,
                      selectedTool: selected,
                      selectedMarkerType: GraphMarkerType.treatmentNote,
                      selectedDrawingPreset: null,
                      onActionSelected: (action) {
                        calls++;
                        setState(() =>
                            selected = action.tool ?? CanvasTool.structure);
                      },
                      onActionAdded: (_) {},
                      onReset: () {},
                      onCollapse: () {},
                      onToggleProperties: () {},
                      onToggleLayers: () {},
                      onDeleteSelection: () {},
                      onUndo: () {},
                      onRedo: () {},
                      propertiesSelected: false,
                      layersSelected: false,
                    ))))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-active-label-Select')),
        findsOneWidget);
    final pan = find.byTooltip('Pan (H)');
    expect(tester.getSize(pan).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(pan).width, greaterThanOrEqualTo(44));
    await tester.tap(pan);
    await tester.pumpAndSettle();
    expect(selected, CanvasTool.pan);
    expect(calls, 1);
    expect(
        find.byKey(const ValueKey('quick-active-label-Pan')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('quick-active-label-Select')), findsNothing);
    await tester.tapAt(const Offset(300, 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-active-label-Pan')), findsNothing);
    expect(selected, CanvasTool.pan);
    expect(calls, 1);
  });
  testWidgets(
      'mobile keeps all utility actions reachable and the toolbar within the viewport',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                    alignment: Alignment.bottomCenter,
                    child: CanvasQuickToolbar(
                      actions: actions,
                      selectedTool: CanvasTool.select,
                      selectedMarkerType: GraphMarkerType.treatmentNote,
                      selectedDrawingPreset: null,
                      onActionSelected: (_) {
                        calls.add('tool');
                      },
                      onActionAdded: (_) {
                        calls.add('add');
                      },
                      onReset: () {
                        calls.add('reset');
                      },
                      onCollapse: () {
                        calls.add('hide');
                      },
                      onToggleProperties: () {
                        calls.add('properties');
                      },
                      onToggleLayers: () {
                        calls.add('layers');
                      },
                      onDeleteSelection: () {
                        calls.add('delete');
                      },
                      onUndo: () {
                        calls.add('undo');
                      },
                      onRedo: () {
                        calls.add('redo');
                      },
                      propertiesSelected: false,
                      layersSelected: false,
                    ))))));
    await tester.pumpAndSettle();
    final bounds =
        tester.getRect(find.byKey(const ValueKey('canvas-quick-toolbar')));
    expect(bounds.left, greaterThanOrEqualTo(12));
    expect(bounds.right, lessThanOrEqualTo(378));
    for (final entry in const {
      'Undo': 'undo',
      'Redo': 'redo',
      'Properties': 'properties',
      'Layers': 'layers',
      'Delete selection': 'delete',
      'Reset quick toolbar': 'reset',
      'Hide quick toolbar': 'hide'
    }.entries) {
      await tester.tap(find.byTooltip('More quick tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.ancestor(
          of: find.text(entry.key),
          matching: find.byWidgetPredicate(
              (widget) => widget is PopupMenuEntry<String>)));
      await tester.pumpAndSettle();
      expect(calls.last, entry.value);
    }
    expect(tester.takeException(), isNull);
  });
}
