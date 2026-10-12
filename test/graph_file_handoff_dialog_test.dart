import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/services/graph_file_handoff.dart';
import 'package:bugman_graphs/widgets/graph_file_handoff_dialog.dart';
import 'support/crowded_canvas_fixture.dart';

class FakeFile implements PreparedGraphFile {
  FakeFile({this.supported = true, this.result = FileHandoffResult.handedOff});
  final bool supported;
  final FileHandoffResult result;
  int shares = 0, downloads = 0;
  @override
  String get name => 'synthetic.pdf';
  @override
  bool get canShare => supported;
  @override
  Future<FileHandoffResult> share() {
    shares++;
    return Future.value(result);
  }

  @override
  void download() {
    downloads++;
  }
}

void main() {
  for (final action in [GraphFileAction.savePng, GraphFileAction.savePdf]) {
    testWidgets(
        'desktop $action offers download even when native sharing exists',
        (tester) async {
      final file = FakeFile(), document = crowdedCanvasFixture();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: GraphFileHandoffDialog(
                  action: action,
                  document: document,
                  revision: () => 0,
                  prepare: () async => PreparedGraphExport(file, 0)))));
      await tester.pumpAndSettle();
      expect(find.text('Open share sheet'), findsNothing);
      await tester.tap(find.text(
          action == GraphFileAction.savePng ? 'Download PNG' : 'Download PDF'));
      await tester.pumpAndSettle();
      expect(file.downloads, 1);
      expect(file.shares, 0);
      expect(find.textContaining('Download requested'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
  testWidgets(
      'preparation failures show the reason and provide no incomplete file',
      (tester) async {
    final doc = crowdedCanvasFixture();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GraphFileHandoffDialog(
                action: GraphFileAction.emailPdf,
                document: doc,
                revision: () => 0,
                prepare: () => Future.error(StateError(
                    'PDF not exported: photo synthetic.jpg is unavailable'))))));
    await tester.pumpAndSettle();
    expect(find.textContaining('photo synthetic.jpg is unavailable'),
        findsOneWidget);
    expect(find.text('Download PDF'), findsNothing);
    expect(find.text('Open share sheet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final result in FileHandoffResult.values) {
    testWidgets(
        'email PDF handoff $result never silently downloads or claims sent',
        (tester) async {
      final document = crowdedCanvasFixture();
      final file = FakeFile(result: result);
      final before = document.toJson();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: GraphFileHandoffDialog(
                  action: GraphFileAction.emailPdf,
                  document: document,
                  prepare: () async => PreparedGraphExport(file, 0),
                  revision: () => 0))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open share sheet'));
      await tester.pumpAndSettle();
      expect(file.shares, 1);
      expect(file.downloads, 0);
      expect(document.toJson(), before);
      expect(find.textContaining('Email sent'), findsNothing);
      if (result == FileHandoffResult.cancelled) {
        expect(find.textContaining('Share cancelled'), findsOneWidget);
      }
      if (result == FileHandoffResult.handedOff) {
        expect(find.textContaining('Finish saving or sending'), findsOneWidget);
      }
    });
  }
  testWidgets('unsupported file sharing retains explicit download only',
      (tester) async {
    final document = crowdedCanvasFixture();
    final file = FakeFile(supported: false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GraphFileHandoffDialog(
                action: GraphFileAction.emailPdf,
                document: document,
                prepare: () async => PreparedGraphExport(file, 0),
                revision: () => 0))));
    await tester.pumpAndSettle();
    expect(find.text('Open share sheet'), findsNothing);
    expect(file.downloads, 0);
    await tester.tap(find.text('Download PDF'));
    await tester.pumpAndSettle();
    expect(file.downloads, 1);
    expect(file.shares, 0);
  });
  testWidgets(
      'document change invalidates prepared file before final share tap',
      (tester) async {
    final document = crowdedCanvasFixture();
    var revision = 0;
    document.addListener(() => revision++);
    final old = FakeFile();
    final fresh = FakeFile();
    final pending = Completer<PreparedGraphExport?>();
    var prepares = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GraphFileHandoffDialog(
                action: GraphFileAction.savePdf,
                document: document,
                prepare: () {
                  prepares++;
                  return prepares == 1
                      ? Future.value(PreparedGraphExport(old, revision))
                      : pending.future;
                },
                revision: () => revision))));
    await tester.pumpAndSettle();
    document.replaceWallSegments([
      const WallSegment(
          start: GraphPoint(x: 1, y: 2), end: GraphPoint(x: 3, y: 4))
    ]);
    await tester.pump();
    expect(find.text('Open share sheet'), findsNothing);
    expect(find.text('Preparing file…'), findsOneWidget);
    expect(old.shares, 0);
    pending.complete(PreparedGraphExport(fresh, revision));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open share sheet'));
    await tester.pumpAndSettle();
    expect(fresh.shares, 1);
    expect(old.shares, 0);
  });
}
