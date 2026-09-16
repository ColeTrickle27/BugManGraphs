import 'package:flutter_test/flutter_test.dart';

import 'package:bugman_graphs/main.dart';
import 'package:bugman_graphs/editor/editor_interaction_controller.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/screens/home_screen.dart';
import 'package:bugman_graphs/screens/new_job_screen.dart';
import 'package:bugman_graphs/services/graph_photo_service.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:bugman_graphs/services/graph_repository_stub.dart';
import 'package:bugman_graphs/theme/app_theme.dart';
import 'package:bugman_graphs/widgets/canvas_toolbar.dart';
import 'package:bugman_graphs/widgets/graph_shapes_painter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  testWidgets('BugManGraphs starts on the job list', (tester) async {
    await tester.pumpWidget(const BugManGraphsApp());

    expect(find.text('BugManGraphs'), findsOneWidget);
    expect(find.text('No jobs yet'), findsOneWidget);
    expect(find.text('New Job'), findsOneWidget);
    expect(find.byKey(const ValueKey('holloman-logo')), findsOneWidget);

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final theme = materialApp.theme!;
    expect(theme.colorScheme.primary, AppColors.red);
    expect(theme.colorScheme.secondary, AppColors.black);
    expect(theme.colorScheme.outline, AppColors.wolfGrey);
    expect(theme.colorScheme.surface, AppColors.white);
    expect(theme.colorScheme.onPrimary, AppColors.white);
  });

  testWidgets(
      'presentation mode is read-only and only paints approved finding markers',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final job = Job(
      customerName: 'Customer Presentation',
      serviceAddress: '1 Structure Way',
      pestPacLocationNumber: 'LOC-1',
      pestPacBillToNumber: 'BILL-1',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 8, 19),
    );
    final document = GraphDocument(
      id: job.id,
      customer: GraphCustomerInfo.fromJob(job),
      traces: const [TraceGeometry(id: 'property-trace', label: 'Property', geoPoints: [], canvasPoints: [GraphPoint(x: 100, y: 100), GraphPoint(x: 200, y: 100), GraphPoint(x: 200, y: 200)])],
      annotations: const [
        GraphAnnotation(
            id: 'approved',
            kind: GraphAnnotationKind.marker,
            point: GraphPoint(x: 120, y: 140),
            label: 'AT',
            markerType: GraphMarkerType.activeTermites),
        GraphAnnotation(
            id: 'internal',
            kind: GraphAnnotationKind.marker,
            point: GraphPoint(x: 220, y: 240),
            label: 'TT',
            markerType: GraphMarkerType.trenchAndTreat),
        GraphAnnotation(
            id: 'note',
            kind: GraphAnnotationKind.text,
            point: GraphPoint(x: 320, y: 340),
            label: 'Staff note'),
      ],
    )..markClean();

    await tester.pumpWidget(MaterialApp(
        home: GraphCanvasScreen(
            document: document,
            presentationMode: true,
            presentationMarkerIds: const {'approved'})));
    await tester.pumpAndSettle();

    expect(find.byType(CanvasToolbar), findsNothing);
    expect(find.byTooltip('File actions'), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final annotations =
        _graphOverlayPainter(tester).annotations as List<dynamic>;
    expect(annotations.map((item) => item.id), ['approved']);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.child, isA<RepaintBoundary>());
    final dynamic surface = (viewer.child as RepaintBoundary).child;
    expect(surface.traces.map((dynamic trace) => trace.id), ['property-trace']);
    expect(surface.traceLayerVisible, isTrue);
    final exportBoundary = find.byWidget(viewer.child!);
    expect(find.descendant(of: exportBoundary, matching: find.byType(AppBar)),
        findsNothing);
    expect(document.isDirty, isFalse);
  });

  testWidgets('New Job shows optional metadata fields and approved services',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const BugManGraphsApp());

    await tester.tap(find.text('New Job'));
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.decoration?.labelText)
        .toList();
    expect(fields, [
      'Company',
      'First Name',
      'Last Name',
      'Street Address',
      'City',
      'State',
      'Zip',
      'Phone',
      'Email',
      'Name',
      'Phone Number',
      'Location Name',
      'Date',
      'Created By',
    ]);

    final today = DateTime.now();
    final expectedDate = '${today.month.toString().padLeft(2, '0')}/'
        '${today.day.toString().padLeft(2, '0')}/'
        '${today.year.toString().padLeft(4, '0')}';
    final dateField = tester.widget<TextField>(
      find.byKey(const ValueKey('job-date-field')),
    );
    expect(dateField.controller?.text, expectedDate);
    expect(dateField.readOnly, isTrue);

    final serviceType = tester.widget<DropdownButtonFormField<String>>(
      find.widgetWithText(DropdownButtonFormField<String>, 'Service Type'),
    );
    expect(NewJobScreen.serviceTypes,
        ['Inspection', 'WDIR', 'ATBS Installation', 'General Use']);
    expect(serviceType.initialValue, 'Inspection');
    expect(find.text('Termite Inspection'), findsNothing);
    expect(find.text('Termite Treatment'), findsNothing);
    expect(find.text('Rodent Inspection'), findsNothing);
    expect(find.text('General Pest'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('job-date-field')));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Create Graph'), findsOneWidget);
  });

  testWidgets('blank New Job submission opens an Untitled Job graph',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const BugManGraphsApp());

    await tester.tap(find.text('New Job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Graph'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNothing);
    expect(find.text('Untitled Job'), findsOneWidget);
    expect(find.byType(GraphCanvasScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Untitled Job'), findsOneWidget);
    expect(find.textContaining('Location #'), findsNothing);
    expect(find.textContaining('Bill-To #'), findsNothing);
  });

  testWidgets('job card labels both populated PestPac identifiers',
      (tester) async {
    final repository = MemoryGraphRepository();
    await repository.saveGraph(GraphDocument.forJob(Job(
        customerName: 'Linked customer',
        serviceAddress: '1 Test Way',
        pestPacLocationNumber: 'LOC-42',
        pestPacBillToNumber: 'BILL-84',
        serviceType: 'Inspection',
        createdBy: 'Tester',
        createdDate: DateTime(2026, 9, 9))));
    await tester
        .pumpWidget(MaterialApp(home: HomeScreen(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Location # LOC-42'), findsOneWidget);
    expect(find.text('Bill-To # BILL-84'), findsOneWidget);
  });

  testWidgets('saved graph cards reopen their stored document', (tester) async {
    final repository = MemoryGraphRepository();
    final job = Job(
      customerName: 'Stored Graph',
      serviceAddress: '10 Archive Lane',
      pestPacLocationNumber: '100',
      pestPacBillToNumber: '200',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 7, 20),
    );
    await repository.saveGraph(GraphDocument.forJob(job));
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stored Graph'));
    await tester.pumpAndSettle();

    expect(find.byType(GraphCanvasScreen), findsOneWidget);
    expect(find.text('Stored Graph'), findsOneWidget);
  });

  testWidgets('saved and unsaved jobs with matching metadata keep separate IDs',
      (tester) async {
    final repository = MemoryGraphRepository();
    final createdDate = DateTime(2026, 7, 20);
    final savedJob = Job(
      id: 'saved-job',
      customerName: '',
      serviceAddress: '',
      pestPacLocationNumber: '',
      pestPacBillToNumber: '',
      serviceType: 'Inspection',
      createdBy: '',
      createdDate: createdDate,
    );
    final unsavedJob = Job(
      id: 'unsaved-job',
      customerName: '',
      serviceAddress: '',
      pestPacLocationNumber: '',
      pestPacBillToNumber: '',
      serviceType: 'Inspection',
      createdBy: '',
      createdDate: createdDate,
    );
    await repository.saveGraph(GraphDocument.forJob(savedJob));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          jobs: [savedJob, unsavedJob],
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Untitled Job'), findsNWidgets(2));
  });

  testWidgets('saved job information can be edited and deleted',
      (tester) async {
    final repository = MemoryGraphRepository();
    final job = Job(
      id: 'editable-job',
      customerName: 'Original Location',
      serviceAddress: '10 Old Road',
      pestPacLocationNumber: '100',
      pestPacBillToNumber: '200',
      serviceType: 'Inspection',
      createdBy: 'Original User',
      createdDate: DateTime(2026, 7, 20),
    );
    await repository.saveGraph(GraphDocument.forJob(job));
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Job actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit job information'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Company'),
      'Updated Location',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Street Address'),
      '20 New Road',
    );
    await tester.scrollUntilVisible(find.text('Save Changes'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Updated Location'), findsOneWidget);
    expect(
      (await repository.loadGraph(job.id))?.customer.serviceAddress,
      '20 New Road',
    );

    await tester.tap(find.byTooltip('Job actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete saved job'));
    await tester.pumpAndSettle();
    expect(find.text('Delete saved job?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await repository.listGraphs(), isEmpty);
    expect(find.text('No jobs yet'), findsOneWidget);
  });

  testWidgets('structure plotting requires points and Enter completes it',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectStructure(tester, 'Detached Structure');

    await tester.tapAt(const Offset(280, 240));
    await tester.pump();
    expect(_shapeCount(tester), 0);

    await tester.tapAt(const Offset(500, 240));
    await tester.tapAt(const Offset(460, 430));
    await tester.pump();
    expect(_shapeCount(tester), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_shapeCount(tester), 1);
    expect(find.text('Shape Properties'), findsNothing);
  });

  testWidgets('Escape cancels an unfinished structure', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectStructure(tester, 'Garage/Carport');

    await tester.tapAt(const Offset(280, 240));
    await tester.tapAt(const Offset(500, 240));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(_shapeCount(tester), 0);
  });

  testWidgets('Undo removes only the latest unfinished structure point',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectStructure(tester, 'Detached Structure');

    await tester.tapAt(const Offset(280, 240));
    await tester.tapAt(const Offset(520, 240));
    await tester.tapAt(const Offset(520, 440));
    await tester.pump();
    expect(_wallCount(tester), 2);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(_wallCount(tester), 1);
    expect(_shapeCount(tester), 0);
  });

  testWidgets('dragging a completed structure vertex moves adjacent corners',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectStructure(tester, 'Detached Structure');

    await tester.tapAt(const Offset(280, 240));
    await tester.tapAt(const Offset(520, 240));
    await tester.tapAt(const Offset(520, 440));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.tap(find.byTooltip('Select (V)'));
    await tester.pump();

    final before = List.of(_graphOverlayPainter(tester).wallSegments as List);
    final gesture = await tester.startGesture(const Offset(280, 240));
    await gesture.moveTo(const Offset(320, 280));
    await gesture.up();
    await tester.pump();
    final after = List.of(_graphOverlayPainter(tester).wallSegments as List);

    expect(after.first.start, isNot(before.first.start));
    expect(after.last.end.x, after.first.start.x);
    expect(after.last.end.y, after.first.start.y);
    expect(after.first.end.x, before.first.end.x);
    expect(after.first.end.y, before.first.end.y);
  });

  testWidgets('dragging a rectangle vertex moves only its connected corners',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectBasicShape(tester, 'Rectangle');
    await tester.dragFrom(const Offset(300, 250), const Offset(220, 170));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();

    final before = List.of(_graphOverlayPainter(tester).wallSegments as List);
    final gesture = await tester.startGesture(const Offset(300, 250));
    await gesture.moveTo(const Offset(336, 286));
    await gesture.up();
    await tester.pump();
    final after = List.of(_graphOverlayPainter(tester).wallSegments as List);

    expect(after.first.start, isNot(before.first.start));
    expect(after.last.end.x, after.first.start.x);
    expect(after.last.end.y, after.first.start.y);
    expect(after.first.end.x, before.first.end.x);
    expect(after.first.end.y, before.first.end.y);
  });

  testWidgets('double-click completes an in-progress structure',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectStructure(tester, 'Concrete Slab');

    await tester.tapAt(const Offset(280, 240));
    await tester.tapAt(const Offset(500, 240));
    await tester.tapAt(const Offset(460, 430));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(460, 430));
    await tester.pump();

    expect(_shapeCount(tester), 1);
  });

  for (final pointCount in [2, 3]) {
    testWidgets(
        'Quick Measure accepts $pointCount points as an open distance measurement',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.reset);
      await _pumpEditor(tester);

      await _selectQuickMeasure(tester);
      final toolbar = tester.widget<CanvasToolbar>(find.byType(CanvasToolbar));
      expect(toolbar.selectedTool, CanvasTool.structure);
      expect(toolbar.selectedDrawingPreset, GraphDrawingPreset.measurementLine);
      await tester.tapAt(const Offset(300, 250));
      await tester.tapAt(const Offset(500, 250));
      if (pointCount == 3) {
        await tester.tapAt(const Offset(500, 450));
      }
      await tester.tap(find.text('Finish Measure'));
      await tester.pump();

      expect(_shapeCount(tester), 1);
      final painter = _graphOverlayPainter(tester);
      final shapes = (painter.shapes as List).cast<GraphShape>();
      final wallSegments = (painter.wallSegments as List).cast<WallSegment>();
      expect(shapes.single.preset, GraphDrawingPreset.measurementLine);
      expect(shapes.single.closed, isFalse);
      expect(shapes.single.fillColor, isNull);
      expect(shapes.single.fillOpacity, 0);
      expect(wallSegments, hasLength(pointCount - 1));
      expect(usesStyledSegmentRendering(shapes.single), isTrue);
      final shapeSegments = shapes.single.segmentIndexes
          .map((index) => wallSegments[index])
          .toList();
      expect(shapeMeasurementSummary(shapes.single, shapeSegments),
          isNot(contains(' sf')));
      expect(
          shapeExportMeasurements(shapes.single, shapeSegments), hasLength(1));
      expect(shapeMeasurementSummary(shapes.single, shapeSegments),
          contains(' lf'));
    });
  }

  testWidgets('generic shapes require drag and double-click opens properties',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    await _selectBasicShape(tester, 'Rectangle');
    await tester.pump();
    await tester.tapAt(const Offset(300, 250));
    await tester.pump();
    expect(_shapeCount(tester), 0);

    await tester.dragFrom(const Offset(300, 250), const Offset(220, 170));
    await tester.pump();
    expect(_shapeCount(tester), 1);
    expect(find.text('Shape Properties'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.tapAt(const Offset(410, 335));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(410, 335));
    await tester.pumpAndSettle();
    expect(find.text('Shape Properties'), findsOneWidget);
  });

  testWidgets('deleting a finished shape removes its backing lines',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    await _selectBasicShape(tester, 'Rectangle');
    await tester.dragFrom(const Offset(300, 250), const Offset(220, 170));
    await tester.pump();
    expect(_shapeCount(tester), 1);
    expect(_wallCount(tester), 4);

    await tester.tap(find.byTooltip('Delete selection'));
    await tester.pump();

    expect(_shapeCount(tester), 0);
    expect(_wallCount(tester), 0);
  });

  testWidgets('main and quick toolbars collapse independently', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    expect(find.text('Select V'), findsNothing);
    expect(find.text('Pan H'), findsNothing);
    expect(find.byType(CanvasQuickToolbar), findsOneWidget);

    await tester.tap(find.byTooltip('Hide main toolbar'));
    await tester.pump();
    expect(find.byType(CanvasToolbar), findsNothing);
    expect(find.byTooltip('Show main toolbar'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide quick toolbar'));
    await tester.pump();
    expect(find.byType(CanvasQuickToolbar), findsNothing);
    expect(find.byTooltip('Show quick toolbar'), findsOneWidget);
  });

  testWidgets('properties and layers start collapsed in bottom toolbar',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(910, 794);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    expect(find.text('Properties'), findsNothing);
    expect(find.text('Layers'), findsNothing);
    expect(find.byTooltip('Properties panel'), findsOneWidget);
    expect(find.byTooltip('Layers panel'), findsOneWidget);
    expect(find.byTooltip('Delete selection'), findsOneWidget);

    final viewerWidth = tester.getSize(find.byType(InteractiveViewer)).width;
    await tester.tap(find.byTooltip('Layers panel'));
    await tester.pump();
    expect(find.text('Layers'), findsWidgets);
    expect(find.text('Building Structure'), findsOneWidget);
    expect(find.text('Inspections'), findsOneWidget);
    expect(find.text('Treatment'), findsOneWidget);
    expect(find.text('Findings'), findsNothing);
    expect(find.text('Shapes'), findsNothing);
    expect(tester.getSize(find.byType(InteractiveViewer)).width, viewerWidth);

    await tester.tap(find.byTooltip('Properties panel'));
    await tester.pump();
    expect(find.text('Properties'), findsWidgets);
    expect(tester.getSize(find.byType(InteractiveViewer)).width, viewerWidth);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.text('Properties'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.text('Properties'), findsWidgets);
  });

  testWidgets('top toolbar keeps file and canvas options collapsed',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(910, 794);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);
    expect(find.text('Graph File'), findsNothing);
    expect(find.text('Export PDF'), findsNothing);
    expect(find.text('20:1'), findsNothing);

    await tester.tap(find.byTooltip('File actions'));
    await tester.pumpAndSettle();
    expect(find.text('SAVE TO OPS BRAIN'), findsOneWidget);
    expect(find.text('Graph File'), findsOneWidget);
    expect(find.text('PDF File'), findsNothing);
    expect(find.text('PNG File'), findsNothing);
    expect(find.text('Save & Open Inspection Workflow'), findsOneWidget);
    expect(find.text('EXPORT FILE'), findsOneWidget);
    expect(find.text('Export PDF'), findsOneWidget);
    expect(find.text('Export PNG'), findsOneWidget);
    expect(find.text('Copy Structure to New Graph'), findsOneWidget);

    // No BugMan Graphs portal is wired up for a bare _pumpEditor() session,
    // so a "Save to Ops Brain" action warns instead of silently no-op-ing.
    await tester.tap(find.text('Graph File'));
    await tester.pump();
    expect(find.text('No changes to save'), findsOneWidget);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('File actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export PDF'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Exporting PDF/PNG files to Holloman Ops Brain is available when '
        'BugManGraphs is opened through Holloman Ops Brain',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.text(
        'Exporting PDF/PNG files to Holloman Ops Brain is available when '
        'BugManGraphs is opened through Holloman Ops Brain',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Canvas options'));
    await tester.pumpAndSettle();
    expect(find.text('Snap to grid'), findsOneWidget);
    expect(find.text('Snap to objects'), findsNothing);
    expect(find.text('10:1'), findsOneWidget);
    expect(find.text('20:1'), findsNothing);
  });

  Future<void> chooseFileAction(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('File actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Graph File save is a no-op when clean, and reuses the same Ops '
      'Brain key on repeat saves (item 10)', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(910, 794);
    addTearDown(tester.view.reset);
    final portal = _FakeBugManPortalService();
    final job = Job(
      customerName: 'Save Test',
      serviceAddress: '',
      pestPacLocationNumber: '',
      pestPacBillToNumber: '',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 8, 6),
    );
    final document = GraphDocument.forJob(job);
    await tester.pumpWidget(
      MaterialApp(
        home: GraphCanvasScreen(document: document, portalService: portal),
      ),
    );
    await tester.pumpAndSettle();

    // A brand new, untouched graph has nothing to save yet.
    await chooseFileAction(tester, 'Graph File');
    expect(find.text('No changes to save'), findsOneWidget);
    expect(portal.saveCallCount, 0);

    // Dirty the document, then Save creates the first Ops Brain file.
    document.setLayer('trace', const GraphLayerState(visible: true));
    await chooseFileAction(tester, 'Graph File');
    expect(portal.saveExistingKeys, [null]);

    // Dirty it again and Save again -- same key gets overwritten (no
    // conflict dialog appears the very first time a document that was
    // just created this save round is re-saved with the same key... but
    // once _portalKey is already set, a second dirty save must prompt).
    document.setLayer('trace', const GraphLayerState(visible: false));
    await tester.tap(find.byTooltip('File actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Graph File'));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsOneWidget);
    await tester.tap(find.text('Overwrite Existing'));
    await tester.pumpAndSettle();
    expect(portal.saveExistingKeys, [null, portal.savedKey]);
  });

  testWidgets(
      'Save As New gives the graph a fresh identity and Ops Brain key '
      '(item 10/11)', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(910, 794);
    addTearDown(tester.view.reset);
    final portal = _FakeBugManPortalService();
    final job = Job(
      customerName: 'Existing Graph Test',
      serviceAddress: '',
      pestPacLocationNumber: '',
      pestPacBillToNumber: '',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 8, 6),
    );
    const originalKey =
        'company/BugMan Graphs Uploads/original-existing-graph.bgraph';
    final document = GraphDocument.forJob(job);
    await tester.pumpWidget(MaterialApp(
      home: GraphCanvasScreen(
        document: document,
        portalService: portal,
        portalKey: originalKey,
      ),
    ));
    await tester.pumpAndSettle();

    document.setLayer('trace', const GraphLayerState(visible: true));
    await chooseFileAction(tester, 'Graph File');
    expect(find.text('Save changes'), findsOneWidget);
    await tester.tap(find.text('Save As New'));
    await tester.pumpAndSettle();

    // Saved as a new file -- the existing key was never touched.
    expect(portal.saveExistingKeys, [null]);
    expect(portal.saveExistingKeys.contains(originalKey), isFalse);
  });

  testWidgets(
      'a missing Ops Brain graph recovers by saving as a new file '
      '(item 11 renamed-key recovery)', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(910, 794);
    addTearDown(tester.view.reset);
    final portal = _FakeBugManPortalService();
    const staleKey = 'company/BugMan Graphs Uploads/renamed-away.bgraph';
    portal.notFoundExistingKeys.add(staleKey);
    final job = Job(
      customerName: 'Renamed Key Test',
      serviceAddress: '',
      pestPacLocationNumber: '',
      pestPacBillToNumber: '',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 8, 6),
    );
    final document = GraphDocument.forJob(job);
    await tester.pumpWidget(MaterialApp(
      home: GraphCanvasScreen(
        document: document,
        portalService: portal,
        portalKey: staleKey,
      ),
    ));
    await tester.pumpAndSettle();

    document.setLayer('trace', const GraphLayerState(visible: true));
    await chooseFileAction(tester, 'Graph File');
    expect(find.text('Save changes'), findsOneWidget);
    await tester.tap(find.text('Overwrite Existing'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('could not be found in Holloman Ops Brain'),
      findsOneWidget,
    );
    expect(portal.saveExistingKeys, [staleKey, null]);
  });

  Future<void> chooseFileActionAndAwaitAsyncWork(
    WidgetTester tester,
    String label,
  ) async {
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('File actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pump();
      // The PDF/PNG render pipeline (image capture + PDF assembly) does
      // real async work that only progresses under runAsync's real
      // event loop, not the fake-async test clock, so poll with real
      // delays instead of pumpAndSettle here.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
  }

  testWidgets('Export PDF/PNG save the graph and rendered exports to Ops Brain',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final portal = _FakeBugManPortalService();
    final job = Job(
      customerName: 'Export Upload Test',
      serviceAddress: '',
      pestPacLocationNumber: 'LOC-9',
      pestPacBillToNumber: 'BILL-9',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 8, 6),
    );
    final document = GraphDocument.forJob(job);
    await tester.pumpWidget(
      MaterialApp(
        home: GraphCanvasScreen(document: document, portalService: portal),
      ),
    );
    await tester.pumpAndSettle();

    await chooseFileActionAndAwaitAsyncWork(tester, 'Export PDF');
    expect(portal.saveExistingKeys, [null]);
    expect(portal.uploadExportCalls, hasLength(1));
    expect(portal.uploadExportCalls.single['contentType'], 'application/pdf');
    expect(
      portal.uploadExportCalls.single['fileName'],
      buildGraphFileName(
        document.customer,
        document.createdAt,
        GraphFileKind.pdfExport,
      ),
    );

    await chooseFileActionAndAwaitAsyncWork(tester, 'Export PNG');
    expect(portal.saveExistingKeys, [null, portal.savedKey]);
    expect(portal.uploadExportCalls, hasLength(2));
    expect(portal.uploadExportCalls.last['contentType'], 'image/png');
    expect(
      portal.uploadExportCalls.last['fileName'],
      buildGraphFileName(
        document.customer,
        document.createdAt,
        GraphFileKind.pngExport,
      ),
    );
  });

  testWidgets('Expired sign-in keeps the active graph and retries unchanged',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final portal = _FakeBugManPortalService()
      ..saveError =
          const PortalAuthenticationException('https://ops.holloman-ext.com/');
    final repository = MemoryGraphRepository();
    final document = GraphDocument.forJob(Job(
      customerName: 'Auth Recovery Test',
      serviceAddress: '1 Test Way',
      pestPacLocationNumber: 'TEST-LOC',
      pestPacBillToNumber: 'TEST-BILL',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 9, 9),
    ));
    document.replaceAnnotations(const [
      GraphAnnotation(
        id: 'photo-pin',
        kind: GraphAnnotationKind.photo,
        point: GraphPoint(x: 800, y: 600),
        label: 'Photo 1',
        attachmentIds: ['photo-1'],
      ),
    ]);
    document.replaceAttachments(const [
      GraphAttachment(
        id: 'photo-1',
        name: 'test.png',
        annotationId: 'photo-pin',
        blobKey: 'photo-1',
        thumbnailKey: 'photo-1-thumb',
      ),
    ]);
    final photo = image_lib.encodePng(image_lib.Image(width: 2, height: 2));
    await repository
        .saveGraph(document, blobs: {'photo-1': photo, 'photo-1-thumb': photo});
    final openedUrls = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: GraphCanvasScreen(
        document: document,
        repository: repository,
        portalService: portal,
        onPortalSignIn: openedUrls.add,
      ),
    ));
    await tester.pumpAndSettle();
    await _selectQuickMeasure(tester);
    await tester.tapAt(const Offset(300, 250));
    await tester.tapAt(const Offset(500, 250));
    final beforeSave = document.toJson();

    await chooseFileAction(tester, 'Graph File');
    expect(find.text('Sign in to save online'), findsOneWidget);
    expect(find.textContaining('saved on this device'), findsOneWidget);
    expect((await repository.loadGraph(document.id))!.toJson(), beforeSave);
    expect(document.isDirty, isTrue);
    await tester.tap(find.text('Sign in in new tab'));
    await tester.pumpAndSettle();
    expect(openedUrls, ['https://ops.holloman-ext.com/']);
    expect(find.byType(GraphCanvasScreen), findsOneWidget);
    expect(document.toJson(), beforeSave);
    expect(_wallCount(tester), 1);

    portal.saveError = null;
    await chooseFileAction(tester, 'Graph File');
    expect(portal.saveCallCount, 2);
    expect(portal.savedDocuments, [beforeSave, beforeSave]);
    expect(portal.savedBlobKeys, [
      {'photo-1', 'photo-1-thumb'},
      {'photo-1', 'photo-1-thumb'},
    ]);
    expect(await repository.loadBlob('photo-1'), photo);
    expect(document.isDirty, isFalse);
    // The unclosed drawing session remains usable after the sign-in dialog.
    await tester.tapAt(const Offset(500, 450));
    await tester.tap(find.text('Finish Measure'));
    await tester.pumpAndSettle();
    expect(_wallCount(tester), 2);
    expect(_shapeCount(tester), 1);
  });

  testWidgets('Export stops before upload when its automatic graph save fails',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final portal = _FakeBugManPortalService()
      ..saveError = Exception('Ops Brain graph save failed.');
    final job = Job(
      customerName: 'Export Save Failure Test',
      serviceAddress: '',
      pestPacLocationNumber: 'LOC-10',
      pestPacBillToNumber: 'BILL-10',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 8, 6),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GraphCanvasScreen(
          document: GraphDocument.forJob(job),
          portalService: portal,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await chooseFileAction(tester, 'Export PNG');

    expect(portal.saveCallCount, 1);
    expect(portal.uploadExportCalls, isEmpty);
    expect(find.textContaining('Graph could not be saved'), findsOneWidget);
  });

  testWidgets(
      'Exporting PDF/PNG to Ops Brain is unavailable outside Holloman Ops '
      'Brain, and never calls uploadGraphExport (item 8)', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final portal = _FakeBugManPortalService()..available = false;
    final job = Job(
      customerName: 'Unavailable Portal Test',
      serviceAddress: '',
      pestPacLocationNumber: '',
      pestPacBillToNumber: '',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 8, 6),
    );
    final document = GraphDocument.forJob(job);
    await tester.pumpWidget(
      MaterialApp(
        home: GraphCanvasScreen(document: document, portalService: portal),
      ),
    );
    await tester.pumpAndSettle();

    await chooseFileAction(tester, 'Export PNG');
    expect(
      find.text(
        'Exporting PDF/PNG files to Holloman Ops Brain is available when '
        'BugManGraphs is opened through Holloman Ops Brain',
      ),
      findsOneWidget,
    );
    expect(portal.uploadExportCalls, isEmpty);
  });

  testWidgets(
      'Save & Open Inspection Workflow saves the graph then opens the '
      'resolved inspection workflow (item 14)', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final portal = _FakeBugManPortalService();
    final job = Job(
      customerName: 'Sales Brain Handoff Test',
      serviceAddress: '1 Handoff Way',
      pestPacLocationNumber: 'LOC-42',
      pestPacBillToNumber: 'BILL-77',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 8, 6),
    );
    final document = GraphDocument.forJob(job);
    await tester.pumpWidget(
      MaterialApp(
        home: GraphCanvasScreen(document: document, portalService: portal),
      ),
    );
    await tester.pumpAndSettle();

    // A never-yet-saved graph still gets its first Ops Brain save before
    // navigating, even though isDirty may be false for a freshly created
    // document -- "no Ops Brain key yet" is not the same thing as
    // "nothing to save".
    await tester.runAsync(() async {
      await chooseFileAction(tester, 'Save & Open Inspection Workflow');
    });

    expect(portal.saveCallCount, 1);
    expect(portal.saveExistingKeys, [null]);
  });

  testWidgets(
      'Save & Open Inspection Workflow warns instead of navigating when '
      'PestPac identifiers are missing (item 14)', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final portal = _FakeBugManPortalService();
    final job = Job(
      customerName: 'No PestPac IDs Test',
      serviceAddress: '',
      pestPacLocationNumber: '',
      pestPacBillToNumber: '',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 8, 6),
    );
    final document = GraphDocument.forJob(job);
    await tester.pumpWidget(
      MaterialApp(
        home: GraphCanvasScreen(document: document, portalService: portal),
      ),
    );
    await tester.pumpAndSettle();

    await chooseFileAction(tester, 'Save & Open Inspection Workflow');

    expect(portal.saveCallCount, 0);
    expect(
      find.textContaining(
        'needs a customer with a Bill-To and Location before opening the '
        'inspection workflow',
      ),
      findsOneWidget,
    );
  });

  testWidgets('scale options update the canvas transformation', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final controller = viewer.transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));

    await tester.tap(find.byTooltip('Canvas options'));
    await tester.pumpAndSettle();
    final scaleItem = find.ancestor(
      of: find.text('3:1'),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    );
    await tester.tap(scaleItem);
    await tester.pumpAndSettle();

    expect(controller.value.getMaxScaleOnAxis(), closeTo(3, 0.001));
  });

  testWidgets('completed Trace vertices can be moved and trace can be deleted',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final job = Job(
      customerName: 'Trace Test',
      serviceAddress: '1 Trace Way',
      pestPacLocationNumber: '',
      pestPacBillToNumber: '',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 7, 23),
    );
    final document = GraphDocument(
      id: job.id,
      customer: GraphCustomerInfo.fromJob(job),
      layers: const {'trace': GraphLayerState(visible: true)},
      traces: const [
        TraceGeometry(
          id: 'trace-1',
          label: 'Property Trace 1',
          geoPoints: [
            GeoPoint(latitude: 35.0, longitude: -78.0),
            GeoPoint(latitude: 35.0, longitude: -77.999),
            GeoPoint(latitude: 34.999, longitude: -77.999),
          ],
          canvasPoints: [
            GraphPoint(x: 1700, y: 1800),
            GraphPoint(x: 1900, y: 1800),
            GraphPoint(x: 1900, y: 2000),
          ],
          metersPerCanvasUnit: 0.5,
        ),
      ],
    )..markClean();
    await tester.pumpWidget(
      MaterialApp(home: GraphCanvasScreen(document: document)),
    );
    await tester.pumpAndSettle();

    final viewerFinder = find.byType(InteractiveViewer);
    final controller = tester
        .widget<InteractiveViewer>(viewerFinder)
        .transformationController!;
    controller.value = Matrix4.identity()
      ..translateByDouble(-1400, -1400, 0, 1);
    await tester.pump();
    const scenePoint = Offset(1700, 1800);
    final localPoint = MatrixUtils.transformPoint(
      controller.value,
      scenePoint,
    );
    final globalPoint = tester.getTopLeft(viewerFinder) + localPoint;
    await tester.dragFrom(globalPoint, const Offset(48, 24));
    await tester.pump();

    expect(document.traces.single.canvasPoints.first.x, greaterThan(1700));
    expect(document.traces.single.canvasPoints.first.y, greaterThan(1800));
    expect(document.traces.single.geoPoints.first.longitude, isNot(-78.0));

    final beforeTraceMove = document.traces.single;
    const traceInterior = Offset(1850, 1900);
    final traceInteriorLocal = MatrixUtils.transformPoint(
      controller.value,
      traceInterior,
    );
    await tester.dragFrom(
      tester.getTopLeft(viewerFinder) + traceInteriorLocal,
      const Offset(36, 24),
    );
    await tester.pump();

    final movedTrace = document.traces.single;
    expect(
      movedTrace.canvasPoints[1].x,
      greaterThan(beforeTraceMove.canvasPoints[1].x),
    );
    expect(
      movedTrace.geoPoints[1].longitude,
      greaterThan(beforeTraceMove.geoPoints[1].longitude),
    );

    var left = movedTrace.canvasPoints.first.x;
    var right = left;
    var top = movedTrace.canvasPoints.first.y;
    for (final point in movedTrace.canvasPoints.skip(1)) {
      left = point.x < left ? point.x : left;
      right = point.x > right ? point.x : right;
      top = point.y < top ? point.y : top;
    }
    final selectionLocal = MatrixUtils.transformPoint(
      controller.value,
      movedTrace.canvasPoints[1].offset,
    );
    await tester.tapAt(tester.getTopLeft(viewerFinder) + selectionLocal);
    await tester.pump();
    final rotationHandleScene = Offset((left + right) / 2, top - 42);
    final rotationHandleLocal = MatrixUtils.transformPoint(
      controller.value,
      rotationHandleScene,
    );
    await tester.dragFrom(
      tester.getTopLeft(viewerFinder) + rotationHandleLocal,
      const Offset(72, 36),
    );
    await tester.pump();

    final rotatedTrace = document.traces.single;
    expect(
      rotatedTrace.canvasPoints.asMap().entries.any(
            (entry) =>
                entry.value.x != movedTrace.canvasPoints[entry.key].x ||
                entry.value.y != movedTrace.canvasPoints[entry.key].y,
          ),
      isTrue,
    );
    expect(
      rotatedTrace.geoPoints.first.latitude,
      movedTrace.geoPoints.first.latitude,
    );
    expect(
      rotatedTrace.geoPoints.first.longitude,
      movedTrace.geoPoints.first.longitude,
    );

    await tester.tap(find.byTooltip('Delete selection'));
    await tester.pump();
    expect(document.traces, isEmpty);
  });

  testWidgets('main toolbar tools can be dragged into quick tools',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    final calloutBox = find.byTooltip(
      'Callouts & Sketch: Callout Box',
    );
    final quickToolbar = find.byKey(const ValueKey('canvas-quick-toolbar'));
    expect(calloutBox, findsOneWidget);
    expect(quickToolbar, findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(calloutBox),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveTo(tester.getCenter(quickToolbar));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final toolbar = tester.widget<CanvasQuickToolbar>(
      find.byType(CanvasQuickToolbar),
    );
    expect(
      toolbar.actions,
      contains(
        const CanvasToolbarAction.tool(CanvasTool.callout),
      ),
    );
  });

  testWidgets('drawing tools can overlap shapes and place markers inside them',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    await _selectBasicShape(tester, 'Rectangle');
    await tester.dragFrom(const Offset(300, 250), const Offset(220, 170));
    await tester.pump();
    expect(_shapeCount(tester), 1);

    await _selectBasicShape(tester, 'Rectangle');
    await tester.dragFrom(const Offset(350, 290), const Offset(110, 90));
    await tester.pump();
    expect(_shapeCount(tester), 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.tapAt(const Offset(410, 335));
    await tester.pump();
    expect(_annotationCount(tester), 1);
    expect(find.text('Item Properties'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.tapAt(const Offset(410, 335));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Item Properties'), findsNothing);
    await tester.tapAt(const Offset(410, 335));
    await tester.pump();
    expect(find.text('Item Properties'), findsOneWidget);
  });

  testWidgets('moisture marker saves a reading without a framework assertion',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    final moistureTool = find.byTooltip(
      'Moisture\nHold and drag to customize quick tools',
    );
    await _expandToolbarSection(
      tester,
      'Inspection Findings',
      moistureTool,
    );
    await tester.ensureVisible(moistureTool);
    await tester.pumpAndSettle();
    await tester.tap(moistureTool.hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    final toolbar = tester.widget<CanvasToolbar>(find.byType(CanvasToolbar));
    expect(toolbar.selectedTool, CanvasTool.marker);
    expect(toolbar.selectedMarkerType, GraphMarkerType.moisture);
    await tester.tapAt(const Offset(500, 350));
    await tester.pumpAndSettle();

    expect(find.text('Moisture percentage'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '18%');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_annotationCount(tester), 1);
    final annotations =
        _graphOverlayPainter(tester).annotations as List<dynamic>;
    expect(annotations.single.label, '18% — High Moisture');
  });

  testWidgets('photo tool adds multiple selected images to one pin',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final job = Job(
      customerName: 'Photo Test',
      serviceAddress: '',
      pestPacLocationNumber: '',
      pestPacBillToNumber: '',
      serviceType: 'Inspection',
      createdBy: 'Widget Test',
      createdDate: DateTime(2026, 7, 20),
    );
    final png = Uint8List.fromList(
      image_lib.encodePng(image_lib.Image(width: 8, height: 8)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GraphCanvasScreen(
          job: job,
          photoPicker: _FakePhotoPicker([
            PickedGraphPhoto(name: 'one.png', bytes: png),
            PickedGraphPhoto(name: 'two.png', bytes: png),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final photoTool = find.byTooltip(
      'Photo\nHold and drag to customize quick tools',
    );
    await _expandToolbarSection(
      tester,
      'Inspection Findings',
      photoTool,
    );
    await tester.ensureVisible(photoTool);
    // The toolbar is independently scrollable; settle after bringing the
    // photo action into its viewport before tapping it.
    await tester.pumpAndSettle();
    expect(photoTool.hitTestable(), findsOneWidget);
    await tester.tap(photoTool.hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<CanvasToolbar>(find.byType(CanvasToolbar)).selectedTool,
      CanvasTool.photo,
    );
    await tester.tapAt(const Offset(500, 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose Photos or Files'));
    await tester.pumpAndSettle();
    expect(find.text('Add 2 photos?'), findsOneWidget);
    await tester.tap(find.text('Add to Graph'));
    await tester.pumpAndSettle();

    final annotations =
        _graphOverlayPainter(tester).annotations as List<dynamic>;
    expect(annotations, hasLength(1));
    expect(annotations.single.attachmentIds, hasLength(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();
    await tester.tapAt(const Offset(500, 350));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(500, 350));
    await tester.pumpAndSettle();
    expect(find.text('2 photo attachments'), findsOneWidget);
    expect(find.text('one.png'), findsOneWidget);
    expect(find.text('two.png'), findsOneWidget);
  });

  testWidgets('selected shape rotation handle rotates the finished shape',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    await _selectBasicShape(tester, 'Rectangle');
    await tester.dragFrom(const Offset(300, 250), const Offset(220, 170));
    await tester.pump();
    expect(_shapeCount(tester), 1);
    expect(_firstShapeRotation(tester), 0);

    await tester.dragFrom(const Offset(410, 222), const Offset(70, 55));
    await tester.pump();

    expect(_firstShapeRotation(tester), isNot(closeTo(0, 0.1)));
  });

  testWidgets(
      'iPad-sized touch drag moves an object without drawing a structure',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    await _selectBasicShape(tester, 'Rectangle');
    await tester.dragFrom(const Offset(250, 220), const Offset(180, 140));
    await tester.pump();
    expect(_shapeCount(tester), 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    final touch = await tester.startGesture(
      const Offset(340, 290),
      kind: PointerDeviceKind.touch,
    );
    await touch.moveBy(const Offset(80, 60));
    await touch.up();
    await tester.pump();

    expect(_shapeCount(tester), 1);
    expect(find.text('Shape Properties'), findsNothing);
  });

  for (final size in const [Size(1440, 900), Size(1024, 768)]) {
    testWidgets('initial canvas is centered in the usable viewport at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await _pumpEditor(tester);

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final viewport = tester.getSize(find.byType(InteractiveViewer));
      final matrix = viewer.transformationController!.value;

      expect(matrix.entry(0, 3), closeTo((viewport.width - 3600) / 2, 0.1));
      expect(matrix.entry(1, 3), closeTo((viewport.height - 2600) / 2, 0.1));
      expect(find.text('Annotate'), findsOneWidget);
      expect(find.text('Sketch Structure'), findsOneWidget);
      expect(find.text('Inspection Findings'), findsOneWidget);
      expect(find.text('Treatment Details'), findsOneWidget);
      expect(find.byType(CanvasQuickToolbar), findsOneWidget);
      expect(find.byTooltip('Select (V)'), findsOneWidget);
      expect(find.byTooltip('Pan (H)'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CanvasToolbar),
          matching: find.text('Shapes'),
        ),
        findsNothing,
      );
    });
  }

  for (final presentationMode in [false, true]) {
    testWidgets(
        'an oversized property trace stays fitted through pinch and pan (presentation: $presentationMode)',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.reset);
      final job = Job(
        customerName: 'Large Property',
        serviceAddress: '10 Carlie Cs Drive',
        pestPacLocationNumber: '',
        pestPacBillToNumber: '',
        serviceType: 'Inspection',
        createdBy: 'Widget Test',
        createdDate: DateTime(2026, 9, 16),
      );
      final document = GraphDocument(
        id: job.id,
        customer: GraphCustomerInfo.fromJob(job),
        layers: const {'trace': GraphLayerState(visible: true)},
        traces: const [
          TraceGeometry(
            id: 'large-property-trace',
            label: 'Large property',
            geoPoints: [],
            canvasPoints: [
              GraphPoint(x: -2400, y: -3600),
              GraphPoint(x: 7200, y: -3600),
              GraphPoint(x: 7200, y: 7600),
              GraphPoint(x: -2400, y: 7600),
            ],
          ),
        ],
      )..markClean();

      await tester.pumpWidget(
        MaterialApp(
            home: GraphCanvasScreen(
                document: document, presentationMode: presentationMode)),
      );
      await tester.pumpAndSettle();

      final viewerFinder = find.byType(InteractiveViewer);
      final viewer = tester.widget<InteractiveViewer>(viewerFinder);
      final matrix = viewer.transformationController!.value;
      final viewport = tester.getSize(viewerFinder);
      final traceBounds =
          const Rect.fromLTRB(-2400, -3600, 7200, 7600).inflate(64);
      final fittedBounds = MatrixUtils.transformRect(matrix, traceBounds);

      expect(matrix.getMaxScaleOnAxis(), lessThan(0.25));
      expect(fittedBounds.left, greaterThanOrEqualTo(0));
      expect(fittedBounds.top, greaterThanOrEqualTo(0));
      expect(fittedBounds.right, lessThanOrEqualTo(viewport.width));
      expect(fittedBounds.bottom, lessThanOrEqualTo(viewport.height));

      final initialScale = matrix.getMaxScaleOnAxis();
      final center = tester.getCenter(viewerFinder);
      final first =
          await tester.startGesture(center - const Offset(100, 0), pointer: 1);
      final second =
          await tester.startGesture(center + const Offset(100, 0), pointer: 2);
      await first.moveTo(center - const Offset(80, 0));
      await second.moveTo(center + const Offset(80, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final pinched = viewer.transformationController!.value.clone();
      expect(pinched.getMaxScaleOnAxis(), lessThan(initialScale));
      final pinchedBounds = MatrixUtils.transformRect(pinched, traceBounds);
      expect(pinchedBounds.left, greaterThanOrEqualTo(0));
      expect(pinchedBounds.top, greaterThanOrEqualTo(0));
      expect(pinchedBounds.right, lessThanOrEqualTo(viewport.width));
      expect(pinchedBounds.bottom, lessThanOrEqualTo(viewport.height));

      if (!presentationMode) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.pump();
      }
      await tester.dragFrom(center, const Offset(30, 20));
      await tester.pumpAndSettle();
      if (!presentationMode) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      }
      final panned = viewer.transformationController!.value;
      expect(panned.entry(0, 3), greaterThan(pinched.entry(0, 3)));
      expect(panned.getMaxScaleOnAxis(),
          closeTo(pinched.getMaxScaleOnAxis(), 0.0001));
    });
  }

  testWidgets('Spacebar drag pans without drawing and restores the line tool',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectLineTool(tester, 'Line');
    await tester.pump();

    final viewerBefore = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final before = viewerBefore.transformationController!.value.clone();
    final center = tester.getCenter(find.byType(InteractiveViewer));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(90, 55));
    await gesture.up();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();

    final after = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value;
    expect(after.entry(0, 3), isNot(closeTo(before.entry(0, 3), 0.1)));
    expect(_shapeCount(tester), 0);
    expect(_annotationCount(tester), 0);

    await tester.tapAt(center - const Offset(80, 0));
    await tester.tapAt(center + const Offset(80, 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Line Properties'), findsNothing);
    await tester.tapAt(center);
    await tester.pump();
    expect(find.text('Line Properties'), findsOneWidget);
  });

  testWidgets('modifier wheel controls zoom and both scroll axes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    Matrix4 matrix() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value
        .clone();

    final initial = matrix();
    await tester.sendEventToBinding(PointerScrollEvent(
      position: center,
      scrollDelta: const Offset(0, -120),
      kind: PointerDeviceKind.mouse,
    ));
    await tester.pump();
    expect(
        matrix().getMaxScaleOnAxis(), greaterThan(initial.getMaxScaleOnAxis()));

    final beforeControl = matrix();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(PointerScrollEvent(
      position: center,
      scrollDelta: const Offset(0, 80),
      kind: PointerDeviceKind.mouse,
    ));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
        matrix().entry(0, 3), isNot(closeTo(beforeControl.entry(0, 3), 0.1)));

    final beforeShift = matrix();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(PointerScrollEvent(
      position: center,
      scrollDelta: const Offset(0, 80),
      kind: PointerDeviceKind.mouse,
    ));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(matrix().entry(1, 3), isNot(closeTo(beforeShift.entry(1, 3), 0.1)));
  });

  testWidgets('line double-click closes and finishes the plotted path',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectLineTool(tester, 'Line');
    await tester.tapAt(const Offset(320, 260));
    await tester.tapAt(const Offset(500, 260));
    await tester.tapAt(const Offset(500, 420));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(500, 420));
    await tester.pumpAndSettle();

    expect(_shapeCount(tester), 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Close Shape closes and saves a multi-point line',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectLineTool(tester, 'Line');
    await tester.tapAt(const Offset(320, 260));
    await tester.tapAt(const Offset(500, 260));
    await tester.tapAt(const Offset(500, 420));
    await tester.tap(find.text('Close Shape').first);
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Close Shape')),
    );
    await tester.pumpAndSettle();

    expect(_shapeCount(tester), 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Treatment Area plots points and double-click closes the area',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    final picker = find.byTooltip('Treatment Marker: Treatment Area');
    await _expandToolbarSection(tester, 'Treatment Details', picker);
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Treatment Area').last);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(300, 240));
    await tester.tapAt(const Offset(520, 240));
    await tester.tapAt(const Offset(480, 430));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(480, 430));
    await tester.pumpAndSettle();

    expect(_shapeCount(tester), 1);
    expect(find.text('Line Properties'), findsNothing);
  });

  testWidgets('Treatment Note callout completes when its drag is released',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    final treatmentNote = find.byTooltip('Treatment Note');
    await _expandToolbarSection(tester, 'Treatment Details', treatmentNote);
    await tester.tap(treatmentNote);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(320, 260));
    await gesture.moveTo(const Offset(470, 340));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inline-canvas-text-editor')),
        findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('inline-canvas-text-editor')),
      'Treat foundation wall',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(_annotationCount(tester), 1);
    expect(
      (_graphOverlayPainter(tester).annotations as List).single.label,
      'Treat foundation wall',
    );
  });

  testWidgets('Callout Box places an editable inspection note on the graph',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);

    final picker = find.byTooltip('Callouts & Sketch: Callout Box');
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Callout Box').last);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(320, 260));
    await gesture.moveTo(const Offset(470, 340));
    await gesture.up();
    await tester.pumpAndSettle();

    final editor = find.byKey(const ValueKey('inline-canvas-text-editor'));
    expect(editor, findsOneWidget);
    await tester.enterText(editor, 'Inspect rim joist');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final annotations = (_graphOverlayPainter(tester).annotations as List)
        .cast<GraphAnnotation>();
    expect(annotations, hasLength(1));
    expect(annotations.single.kind, GraphAnnotationKind.text);
    expect(annotations.single.label, 'Inspect rim joist');
    expect(annotations.single.extraProperties, contains('calloutTipX'));
  });

  testWidgets('right-click removes only the latest unfinished line point',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectLineTool(tester, 'Line');
    await tester.tapAt(const Offset(320, 260));
    await tester.tapAt(const Offset(500, 260));
    await _secondaryClick(tester, const Offset(500, 260));
    await tester.pump();

    expect(
      find.byWidgetPredicate((widget) =>
          widget is Tooltip &&
          widget.message == 'Latest plotted point removed'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(500, 300));
    await tester.tapAt(const Offset(500, 430));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(500, 430));
    await tester.pumpAndSettle();
    expect(_shapeCount(tester), 1);
  });

  testWidgets('Undo lifts the latest unfinished line point like right-click',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectLineTool(tester, 'Line');
    await tester.tapAt(const Offset(320, 260));
    await tester.tapAt(const Offset(500, 260));
    await tester.pump();
    expect(_wallCount(tester), 1);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();

    expect(_wallCount(tester), 0);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is Tooltip &&
          widget.message == 'Latest plotted point removed'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(500, 300));
    await tester.pump();
    expect(_wallCount(tester), 1);
  });

  testWidgets('thin line selection uses reduced but practical tolerance',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await _pumpEditor(tester);
    await _selectLineTool(tester, 'Line');
    await tester.dragFrom(const Offset(320, 300), const Offset(260, 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();

    await tester.tapAt(const Offset(450, 326));
    await tester.pump();
    expect(find.text('Line Properties'), findsNothing);

    await tester.tapAt(const Offset(450, 306));
    await tester.pump();
    expect(find.text('Shape Properties'), findsNothing);

    await tester.tapAt(const Offset(450, 306));
    await tester.pump();
    expect(find.text('Line Properties'), findsOneWidget);
  });
}

Future<void> _pumpEditor(WidgetTester tester) async {
  final job = Job(
    customerName: 'Interaction Test',
    serviceAddress: '1 Canvas Way',
    pestPacLocationNumber: 'TEST-1',
    pestPacBillToNumber: 'BILL-1',
    serviceType: 'Inspection',
    createdBy: 'Widget Test',
    createdDate: DateTime(2026, 7, 18),
  );
  await tester.pumpWidget(MaterialApp(home: GraphCanvasScreen(job: job)));
  await tester.pumpAndSettle();
}

dynamic _graphOverlayPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byKey(const ValueKey('graph-canvas-paint')))
    .foregroundPainter as dynamic;

int _shapeCount(WidgetTester tester) =>
    (_graphOverlayPainter(tester).shapes as List).length;

int _wallCount(WidgetTester tester) =>
    (_graphOverlayPainter(tester).wallSegments as List).length;

int _annotationCount(WidgetTester tester) =>
    (_graphOverlayPainter(tester).annotations as List).length;

double _firstShapeRotation(WidgetTester tester) =>
    (_graphOverlayPainter(tester).shapes as List).first.rotationDegrees
        as double;

Future<void> _secondaryClick(WidgetTester tester, Offset position) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.down(position);
  await gesture.up();
}

Future<void> _selectStructure(WidgetTester tester, String label) async {
  await _expandToolbarSection(tester, 'Sketch Structure', find.text('MAIN'));
  if (label == 'Main Structure') {
    await tester.ensureVisible(find.text('MAIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MAIN'));
    await tester.pumpAndSettle();
    return;
  }

  await tester.ensureVisible(find.text('Building Features'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Building Features'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _selectBasicShape(WidgetTester tester, String label) async {
  await _expandToolbarSection(tester, 'Annotate', find.text('Basic Shapes'));
  await tester.ensureVisible(find.text('Basic Shapes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Basic Shapes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _selectLineTool(WidgetTester tester, String label) async {
  expect(label, 'Line');
  await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
  await tester.pumpAndSettle();
}

Future<void> _selectQuickMeasure(WidgetTester tester) async {
  final quickMeasure = find.byKey(const ValueKey('quick-measure-tool'));
  await tester.ensureVisible(quickMeasure);
  final action = tester.widget<InkWell>(find.descendant(
    of: quickMeasure,
    matching: find.byType(InkWell),
  ));
  action.onTap!();
  await tester.pumpAndSettle();
}

Future<void> _expandToolbarSection(
  WidgetTester tester,
  String label,
  Finder visibleChild,
) async {
  if (visibleChild.evaluate().isNotEmpty) return;
  final sectionLabel = find.descendant(
    of: find.byType(CanvasToolbar),
    matching: find.text(label),
  );
  await tester.ensureVisible(sectionLabel);
  await tester.pumpAndSettle();
  await tester.tap(sectionLabel);
  await tester.pumpAndSettle();
}

class _FakePhotoPicker implements GraphPhotoPicker {
  _FakePhotoPicker(this.photos);

  final List<PickedGraphPhoto> photos;

  @override
  Future<PickedGraphPhoto?> capture() async =>
      photos.isEmpty ? null : photos.first;

  @override
  Future<List<PickedGraphPhoto>> chooseMultiple() async => photos;
}

class _FakeBugManPortalService implements BugManPortalService {
  final savedKey = 'company/BugMan Graphs Uploads/saved.bgraph';
  final saveExistingKeys = <String?>[];
  final savedDocuments = <Map<String, Object?>>[];
  final savedBlobKeys = <Set<String>>[];
  final uploadExportCalls = <Map<String, Object?>>[];
  // Item 11: keys in this set make the next saveGraph() call with that
  // existingKey throw the exact server 404 error text, so tests can
  // exercise the "Saved graph not found" recovery path.
  final notFoundExistingKeys = <String>{};
  Object? saveError;
  bool available = true;
  int saveCallCount = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<PortalGraphPackage> loadGraph(String key) =>
      throw UnimplementedError();

  @override
  Future<PortalUploadResult> saveGraph(
    GraphDocument document,
    Map<String, Uint8List> blobs, {
    String? existingKey,
  }) async {
    saveCallCount += 1;
    savedDocuments.add(document.toJson());
    savedBlobKeys.add(blobs.keys.toSet());
    saveExistingKeys.add(existingKey);
    if (saveError != null) throw saveError!;
    if (existingKey != null && notFoundExistingKeys.contains(existingKey)) {
      throw Exception('Saved graph not found.');
    }
    return PortalUploadResult(
      key: existingKey ?? savedKey,
      message: 'Graph saved to Ops Brain.',
    );
  }

  @override
  Future<PortalUploadResult> uploadGraphExport({
    required GraphCustomerInfo customer,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    required DateTime graphCreatedAt,
  }) async {
    uploadExportCalls.add({
      'customer': customer,
      'fileName': fileName,
      'bytes': bytes,
      'contentType': contentType,
      'graphCreatedAt': graphCreatedAt,
    });
    return PortalUploadResult(
      key: 'company/BugMan Graphs Uploads/$fileName',
      message: '$fileName saved to Ops Brain.',
    );
  }

  @override
  String? buildSalesBrainReportUrl({
    required String billToNumber,
    required String locationNumber,
    required String graphKey,
  }) {
    if (!available) return null;
    final encodedKey = Uri.encodeQueryComponent(graphKey);
    return 'https://ops.holloman-ext.com/sales-brain/'
        '?billTo=$billToNumber&location=$locationNumber&graphKey=$encodedKey';
  }
}
