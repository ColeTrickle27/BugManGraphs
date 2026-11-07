import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/export_bounds_calculator.dart';
import 'package:bugman_graphs/widgets/canvas_toolbar.dart';
import 'package:bugman_graphs/widgets/graph_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(350, 300), const Size(414, 300)]) {
    testWidgets(
        'narrow landscape toolbars remain separate without overflow $size',
        (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      addTearDown(t.view.reset);
      final doc = GraphDocument.forJob(Job(
          customerName: 'Synthetic narrow layout',
          serviceAddress: '',
          pestPacLocationNumber: '990903',
          pestPacBillToNumber: '990901',
          serviceType: 'General Use',
          createdBy: '',
          createdDate: DateTime(2026)));
      await t.pumpWidget(MaterialApp(home: GraphCanvasScreen(document: doc)));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Show main toolbar'));
      await t.pumpAndSettle();
      expect(
          t
              .getRect(find.byType(CanvasToolbar))
              .overlaps(t.getRect(find.byType(CanvasQuickToolbar))),
          isFalse);
      expect(t.takeException(), isNull);
    });
  }
  for (final size in [
    const Size(1440, 1100),
    const Size(390, 844),
    const Size(844, 390)
  ]) {
    testWidgets(
        'existing geometry fits initially; tools and resize retain state at $size',
        (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      addTearDown(t.view.reset);
      final doc = GraphDocument.forJob(Job(
          customerName: 'Synthetic copy',
          serviceAddress: '',
          pestPacLocationNumber: '990903',
          pestPacBillToNumber: '990901',
          serviceType: 'General Use',
          createdBy: '',
          createdDate: DateTime(2026)))
        ..replaceWallSegments(const [
          WallSegment(
              start: GraphPoint(x: 20, y: 20), end: GraphPoint(x: 260, y: 212))
        ])
        ..markClean();
      final before = doc.toJson();
      await t.pumpWidget(MaterialApp(
          home: GraphCanvasScreen(document: doc, fitToContentOnOpen: true)));
      await t.pumpAndSettle();
      final viewerFinder = find.byType(InteractiveViewer);
      final viewer = t.widget<InteractiveViewer>(viewerFinder);
      final viewport = Offset.zero & t.getSize(viewerFinder);
      final painted = MatrixUtils.transformRect(
          viewer.transformationController!.value,
          ExportBoundsCalculator.forDocument(doc, padding: 0));
      expect(viewport.contains(painted.topLeft), true);
      expect(viewport.contains(painted.bottomRight), true);
      if (size.shortestSide < 600) {
        expect(find.byTooltip('Show main toolbar'), findsOneWidget);
        await t.tap(find.byTooltip('Show main toolbar'));
        await t.pumpAndSettle();
      }
      for (final label in [
        'Annotate',
        'Sketch Structure',
        'Inspection Findings',
        'Treatment Details'
      ]) {
        final text = t.renderObject<RenderParagraph>(find.text(label));
        expect(text.didExceedMaxLines, isFalse, reason: label);
      }
      if (size.width > size.height) {
        expect(
            t
                .getRect(find.byType(CanvasToolbar))
                .overlaps(t.getRect(find.byType(CanvasQuickToolbar))),
            isFalse);
      }
      if (find.byTooltip('Fit drawing').evaluate().isEmpty) {
        await t.tap(find.byTooltip('Canvas options'));
        await t.pumpAndSettle();
        await t.tap(find.text('Fit drawing'));
      } else {
        await t.tap(find.byTooltip('Fit drawing'));
      }
      await t.pumpAndSettle();
      final expandedBounds = MatrixUtils.transformRect(
          viewer.transformationController!.value,
          ExportBoundsCalculator.forDocument(doc, padding: 0));
      expect(expandedBounds.left, greaterThanOrEqualTo(208));
      await t.tap(find.byTooltip('Pan (H)'));
      await t.pumpAndSettle();
      if (find.byTooltip('Show main toolbar').evaluate().isNotEmpty) {
        await t.tap(find.byTooltip('Show main toolbar'));
        await t.pumpAndSettle();
      }
      await t.tapAt(t.getTopRight(viewerFinder) + const Offset(-24, 60));
      await t.pump();
      expect(find.byType(MaterialBanner), findsOneWidget);
      final noticeRect = t.getRect(find.byType(MaterialBanner));
      expect(
          noticeRect.overlaps(t.getRect(find.byType(CanvasToolbar))), isFalse);
      expect(noticeRect.overlaps(t.getRect(find.byType(CanvasQuickToolbar))),
          isFalse);
      await t.tap(find.text('Dismiss'));
      await t.pumpAndSettle();
      await t.tap(find.text('Annotate'));
      await t.pumpAndSettle();
      final toolbarState = t.state(find.byType(CanvasToolbar));
      final manual = Matrix4.identity()
        ..scaleByDouble(.75, .75, .75, 1)
        ..setEntry(0, 3, 45)
        ..setEntry(1, 3, 75);
      viewer.transformationController!.value = manual;
      await t.pump();
      await t.tap(find.byTooltip('Hide main toolbar'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Show main toolbar'));
      await t.pumpAndSettle();
      expect(t.state(find.byType(CanvasToolbar)), same(toolbarState));
      final sections = t.widgetList<Semantics>(find.descendant(
          of: find.byType(CanvasToolbar), matching: find.byType(Semantics)));
      expect(
          sections.any((s) =>
              s.properties.label == 'Annotate tools' &&
              s.properties.expanded == true),
          true);
      expect(viewer.transformationController!.value, manual);
      final oldCenter =
          viewer.transformationController!.toScene(viewport.center);
      t.view.physicalSize = Size(size.height, size.width);
      await t.pumpAndSettle();
      final resized = t.getSize(viewerFinder);
      final newCenter =
          viewer.transformationController!.toScene(resized.center(Offset.zero));
      expect((newCenter - oldCenter).distance, lessThan(.001));
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), .75);
      expect(doc.toJson(), before);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('full graph title can be opened and closed on a narrow screen',
      (t) async {
    const title = 'Synthetic customer with a long service location title';
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            appBar: AppBar(
                title: const SizedBox(width: 100, child: GraphTitle(title))),
            body: const SizedBox())));
    final semantics = t.ensureSemantics();
    expect(
        t
            .getSemantics(find.byType(GraphTitle))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, title), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    await t.tap(find.byType(GraphTitle));
    await t.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, title), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(t.takeException(), isNull);
    semantics.dispose();
  });
}
