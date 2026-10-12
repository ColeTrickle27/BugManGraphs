import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/graph_file_handoff.dart';
import 'support/crowded_canvas_fixture.dart';

class RecordingHandoff implements GraphFileHandoff {
  bool failNext = false;
  final files = <Uint8List>[];
  @override
  PreparedGraphFile prepare(Uint8List bytes, String name, String contentType) {
    files.add(Uint8List.fromList(bytes));
    if (failNext) {
      failNext = false;
      throw StateError('Synthetic preparation failure');
    }
    return TestFile(name);
  }
}

class TestFile implements PreparedGraphFile {
  TestFile(this.name);
  @override
  final String name;
  @override
  bool get canShare => false;
  @override
  void download() {}
  @override
  Future<FileHandoffResult> share() async => FileHandoffResult.unavailable;
}

Future<void> openExport(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byTooltip('Save and share'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save PNG…'));
    await tester.tap(find.text('Save PNG…'));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      if (find.text('Preparing file…').evaluate().isEmpty) break;
    }
  });
  await tester.pumpAndSettle();
}

Future<void> closeExport(WidgetTester tester) async {
  await tester.tap(find.text('Close'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'failed preparation can close and retry without document mutation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final document = crowdedCanvasFixture(), before = document.toJson();
    final handoff = RecordingHandoff()..failNext = true;
    await tester.pumpWidget(MaterialApp(
        home: GraphCanvasScreen(document: document, fileHandoff: handoff)));
    await tester.pumpAndSettle();
    await openExport(tester);
    expect(find.textContaining('could not be prepared'), findsOneWidget);
    await closeExport(tester);
    await openExport(tester);
    expect(handoff.files, hasLength(2));
    expect(find.text('Download PNG'), findsOneWidget);
    expect(document.toJson(), before);
    expect(tester.takeException(), isNull);
  });
  for (final setting in ['zoom', 'labels', 'grid', 'ratio']) {
    testWidgets(
        'PNG reflects $setting changes on reopen without editing geometry',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.reset);
      final document = crowdedCanvasFixture(), before = document.toJson();
      final handoff = RecordingHandoff();
      await tester.pumpWidget(MaterialApp(
          home: GraphCanvasScreen(document: document, fileHandoff: handoff)));
      await tester.pumpAndSettle();
      await openExport(tester);
      expect(handoff.files, hasLength(1));
      await closeExport(tester);
      if (setting == 'zoom') {
        await tester.tap(find.byTooltip('Zoom in'));
      } else {
        await tester.tap(find.byTooltip('Canvas options'));
        await tester.pumpAndSettle();
        final label = switch (setting) {
          'labels' => 'Larger labels',
          'grid' => 'Grid',
          _ => '2:1'
        };
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find
            .ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate((w) => w is PopupMenuEntry))
            .first);
      }
      await tester.pumpAndSettle();
      await openExport(tester);
      expect(handoff.files, hasLength(2));
      expect(handoff.files.last, isNot(orderedEquals(handoff.files.first)));
      expect(document.toJson(), before);
      expect(tester.takeException(), isNull);
    });
  }
}
