import 'package:bugman_graphs/editor/editor_interaction_controller.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/graph_marker_catalog.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/widgets/wall_segments_painter.dart';
import 'package:bugman_graphs/widgets/canvas_toolbar.dart';
import 'package:bugman_graphs/widgets/graph_marker_visual.dart';
import 'package:bugman_graphs/widgets/graph_shapes_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interaction controller keeps tool, structure, and marker intent', () {
    final controller = EditorInteractionController();
    addTearDown(controller.dispose);

    controller.selectStructure(GraphDrawingPreset.detachedStructure);
    expect(controller.primaryTool, CanvasTool.structure);
    expect(controller.structureType, GraphDrawingPreset.detachedStructure);

    controller.selectTool(CanvasTool.rectangle);
    expect(controller.primaryTool, CanvasTool.rectangle);
    expect(controller.structureType, GraphDrawingPreset.detachedStructure);

    controller.selectMarker(GraphMarkerType.verticalDrill);
    expect(controller.primaryTool, CanvasTool.marker);
    expect(controller.markerType.category, GraphMarkerCategory.treatment);
  });

  test('line and arrow use one continuous shaft geometry', () {
    const line = WallSegment(
      start: GraphPoint(x: 20, y: 40),
      end: GraphPoint(x: 220, y: 40),
    );
    const arrow = WallSegment(
      start: GraphPoint(x: 220, y: 180),
      end: GraphPoint(x: 40, y: 60),
      hasArrow: true,
    );

    final lineMetrics = buildWallSegmentPath(line).computeMetrics().toList();
    final arrowMetrics = buildWallSegmentPath(arrow).computeMetrics().toList();

    expect(lineMetrics, hasLength(1));
    expect(lineMetrics.single.length, closeTo(200, 0.01));
    expect(arrowMetrics, hasLength(1));
    expect(arrowMetrics.single.length, closeTo(216.33, 0.1));
  });

  test('toolbar cleanup preserves legacy enums but hides removed entries', () {
    const removed = <GraphMarkerType>{
      GraphMarkerType.carpenterAntEvidence,
      GraphMarkerType.carpenterBeeEvidence,
      GraphMarkerType.roachActivity,
      GraphMarkerType.otherPestEvidence,
      GraphMarkerType.conduciveCondition,
      GraphMarkerType.crawlspaceIssue,
      GraphMarkerType.woodDecay,
      GraphMarkerType.entryPoint,
      GraphMarkerType.termiteDamage,
      GraphMarkerType.activeTermites,
      GraphMarkerType.oldTermiteActivity,
      GraphMarkerType.oldDamage,
      GraphMarkerType.damage,
      GraphMarkerType.foundationCrack,
      GraphMarkerType.plumbingPenetration,
      GraphMarkerType.utilityPenetration,
      GraphMarkerType.expansionJoint,
      GraphMarkerType.pestEntryPoint,
      GraphMarkerType.highMoisture,
      GraphMarkerType.activeLeak,
      GraphMarkerType.condensation,
      GraphMarkerType.drainageConcern,
      GraphMarkerType.accessPoint,
      GraphMarkerType.vent,
      GraphMarkerType.door,
      GraphMarkerType.window,
      GraphMarkerType.garageDoor,
      GraphMarkerType.deckSupport,
      GraphMarkerType.foundationVent,
      GraphMarkerType.photoPoint,
      GraphMarkerType.camera,
      GraphMarkerType.notePoint,
    };

    expect(availableInspectionMarkers, isNot(containsAll(removed)));
    expect(availableInspectionMarkers.where(removed.contains), isEmpty);
    expect(availableInspectionMarkers, contains(GraphMarkerType.woodFungi));
    expect(availableInspectionMarkers.first, GraphMarkerType.moisture);
    expect(availableInspectionMarkers[1], GraphMarkerType.termiteActivity);
    expect(
      availableInspectionMarkers,
      isNot(contains(GraphMarkerType.moistureReading)),
    );
    expect(
      availableInspectionMarkers,
      isNot(contains(GraphMarkerType.generalPestActivity)),
    );
    expect(availableInspectionMarkers, contains(GraphMarkerType.rot));
    expect(GraphMarkerType.rot.label, 'Wood Rot');
    expect(GraphMarkerType.woodFungi.label, 'Wood Destroying Fungi');
    expect(availableTreatmentMarkers, contains(GraphMarkerType.treatmentArea));
    expect(availableTreatmentMarkers, contains(GraphMarkerType.rodentBox));
    expect(availableTreatmentMarkers, contains(GraphMarkerType.rodentTrap));
    expect(availableTreatmentMarkers, contains(GraphMarkerType.treatmentNote));
    expect(availableTreatmentMarkers, isNot(contains(GraphMarkerType.circle)));
    expect(drawingToolbarPresets, isNot(contains(GraphDrawingPreset.measurementLine)));
    expect(structureToolbarPresets,
        isNot(contains(GraphDrawingPreset.measurementLine)));
    expect(structureToolbarPresets,
        isNot(contains(GraphDrawingPreset.treatmentArea)));
    expect(basicLineToolbarActions.map((action) => action.tool), [
      CanvasTool.callout,
      CanvasTool.text,
      CanvasTool.arrow,
      CanvasTool.freehand,
    ]);
    expect(basicShapeToolbarActions.map((action) => action.tool), [
      CanvasTool.rectangle,
      CanvasTool.circle,
      CanvasTool.triangle,
      CanvasTool.wall,
    ]);
    expect(structureToolbarPresets,
        isNot(contains(GraphDrawingPreset.crawlspace)));
    expect(structureToolbarPresets,
        isNot(contains(GraphDrawingPreset.propertyLine)));
    expect(propertyToolbarActions.map((action) => action.preset), [
      GraphDrawingPreset.driveway,
      GraphDrawingPreset.walkway,
      GraphDrawingPreset.propertyLine,
    ]);
    expect(utilityToolbarMarkers, [
      GraphMarkerType.hvacUnit,
      GraphMarkerType.pier,
      GraphMarkerType.steps,
      GraphMarkerType.crawlspaceAccess,
      GraphMarkerType.gasLine,
      GraphMarkerType.waterLine,
    ]);
    expect(CanvasTool.select.icon, Icons.navigation);
    expect(CanvasTool.pan.icon, Icons.pan_tool_outlined);
    expect(GraphDrawingPreset.measurementLine.label, 'Quick Measure');
    expect(
        GraphDrawingPreset.measurementLine.kind, GraphDrawingPresetKind.area);
  });

  test('structure and property summaries use approved measurement units', () {
    const segments = [
      WallSegment(
        start: GraphPoint(x: 0, y: 0),
        end: GraphPoint(x: 24, y: 0),
      ),
      WallSegment(
        start: GraphPoint(x: 24, y: 0),
        end: GraphPoint(x: 24, y: 24),
      ),
      WallSegment(
        start: GraphPoint(x: 24, y: 24),
        end: GraphPoint(x: 0, y: 24),
      ),
      WallSegment(
        start: GraphPoint(x: 0, y: 24),
        end: GraphPoint(x: 0, y: 0),
      ),
    ];
    const structure = GraphShape(
      name: 'Main Structure',
      segmentIndexes: [0, 1, 2, 3],
      fillColor: Color(0xFFB6D94C),
      fillOpacity: 0.3,
      borderColor: Color(0xFF214D38),
      borderWidth: 3,
      pattern: GraphShapePattern.none,
      closed: true,
      rotationDegrees: 0,
      preset: GraphDrawingPreset.mainStructure,
    );
    const property = GraphShape(
      name: 'Property Line',
      segmentIndexes: [0, 1, 2, 3],
      fillColor: null,
      fillOpacity: 0,
      borderColor: Color(0xFF214D38),
      borderWidth: 2,
      pattern: GraphShapePattern.none,
      closed: true,
      rotationDegrees: 0,
      preset: GraphDrawingPreset.propertyLine,
    );
    const quickMeasure = GraphShape(
      name: 'Quick Measure',
      segmentIndexes: [0, 1, 2, 3],
      fillColor: Color(0xFF4D9CFF),
      fillOpacity: 0.14,
      borderColor: Color(0xFF245BDB),
      borderWidth: 3,
      pattern: GraphShapePattern.none,
      closed: true,
      rotationDegrees: 0,
      preset: GraphDrawingPreset.measurementLine,
    );
    const mainStructureWithFoundation = GraphShape(
      name: 'Main Structure',
      segmentIndexes: [0, 1, 2, 3],
      fillColor: Color(0xFFB6D94C),
      fillOpacity: 0.3,
      borderColor: Color(0xFF214D38),
      borderWidth: 3,
      pattern: GraphShapePattern.none,
      closed: true,
      rotationDegrees: 0,
      preset: GraphDrawingPreset.mainStructure,
      extraProperties: {'foundationType': 'crawlspace'},
    );

    expect(shapeMeasurementSummary(structure, segments), '4 lf • 1 sf');
    expect(
      shapeMeasurementSummary(property, segments),
      '0.0 ac • 1 sf • 4 lf',
    );
    expect(shapeMeasurementSummary(quickMeasure, segments), '4 lf • 1 sf');
    expect(
      shapeMeasurementSummary(quickMeasure.copyWith(closed: false), segments),
      '4 lf',
    );
    expect(
      mainStructureWithFoundation.foundationType,
      StructureFoundationType.crawlspace,
    );
    expect(segments.first.measurementLabel, '1 lf');
  });

  test('export measurements include every drawn shape and line', () {
    const areaSegments = [
      WallSegment(
        start: GraphPoint(x: 0, y: 0),
        end: GraphPoint(x: 24, y: 0),
      ),
      WallSegment(
        start: GraphPoint(x: 24, y: 0),
        end: GraphPoint(x: 24, y: 24),
      ),
      WallSegment(
        start: GraphPoint(x: 24, y: 24),
        end: GraphPoint(x: 0, y: 24),
      ),
      WallSegment(
        start: GraphPoint(x: 0, y: 24),
        end: GraphPoint(x: 0, y: 0),
      ),
    ];
    const lawn = GraphShape(
      name: 'Lawn',
      segmentIndexes: [0, 1, 2, 3],
      fillColor: null,
      fillOpacity: 0,
      borderColor: Colors.green,
      borderWidth: 2,
      pattern: GraphShapePattern.none,
      closed: true,
      rotationDegrees: 0,
    );
    const fence = GraphShape(
      name: 'Fence',
      segmentIndexes: [0],
      fillColor: null,
      fillOpacity: 0,
      borderColor: Colors.brown,
      borderWidth: 2,
      pattern: GraphShapePattern.none,
      closed: false,
      rotationDegrees: 0,
      preset: GraphDrawingPreset.fenceLine,
    );

    expect(shapeExportMeasurements(lawn, areaSegments), ['1 sf', '4 lf']);
    expect(shapeExportMeasurements(fence, areaSegments), ['4 lf']);
  });

  test('completed fence uses its saved X-mark segment styling', () {
    const fence = GraphShape(
      name: 'Fence Line',
      segmentIndexes: [0],
      fillColor: null,
      fillOpacity: 0,
      borderColor: Color(0xFF795548),
      borderWidth: 2,
      pattern: GraphShapePattern.none,
      closed: false,
      rotationDegrees: 0,
      preset: GraphDrawingPreset.fenceLine,
    );
    const segment = WallSegment(
      start: GraphPoint(x: 10, y: 10),
      end: GraphPoint(x: 200, y: 10),
      pattern: LinePattern.xMarks,
    );

    expect(usesStyledSegmentRendering(fence), isTrue);
    expect(segment.pattern, LinePattern.xMarks);
    expect(GraphDrawingPreset.fenceLine.defaultLinePattern,
        LinePatternValue.xMarks);
  });

  test('completed standard lines use measured segment rendering', () {
    const line = GraphShape(
      name: 'Line 1',
      segmentIndexes: [0],
      fillColor: Color(0xFFB6D94C),
      fillOpacity: 0.3,
      borderColor: Color(0xFF214D38),
      borderWidth: 3,
      pattern: GraphShapePattern.none,
      closed: true,
      rotationDegrees: 0,
      extraProperties: {'sourceTool': 'wall'},
    );
    const topEdge = WallSegment(
      start: GraphPoint(x: 0, y: 0),
      end: GraphPoint(x: 240, y: 0),
    );

    expect(usesStyledSegmentRendering(line), isTrue);
    expect(topEdge.measurementLabel, '10 lf');
    expect(
      wallMeasurementLabelCenter(
        topEdge,
        referencePoint: const Offset(120, 100),
      ).dy,
      lessThanOrEqualTo(-28),
    );
  });

  test('active drawing preview reports footage before the point is placed', () {
    const preview = WallSegment(
      start: GraphPoint(x: 0, y: 0),
      end: GraphPoint(x: 720, y: 0),
    );
    final painter = WallSegmentsPainter(
      segments: const [],
      selectedSegmentIndex: null,
      activeWallStart: preview.start,
      previewSegment: preview,
    );

    expect(painter.previewSegment?.measurementLabel, '30 lf');
  });

  test('canvas markers use the same recognizable icon mapping as toolbar', () {
    for (final marker in {
      ...availableInspectionMarkers,
      ...availableTreatmentMarkers,
      GraphMarkerType.pier,
    }) {
      expect(iconForGraphMarker(marker).codePoint, isPositive);
    }
    expect(iconForGraphMarker(GraphMarkerType.rodentBox),
        isNot(iconForGraphMarker(GraphMarkerType.rodentTrap)));
  });

  test('moisture readings use the approved threshold colors', () {
    expect(moistureMarkerColor(9).toARGB32(), 0xFFE0AD19);
    expect(moistureMarkerColor(10).toARGB32(), 0xFF2E7D55);
    expect(moistureMarkerColor(19).toARGB32(), 0xFFE0AD19);
    expect(moistureMarkerColor(20).toARGB32(), 0xFFE0AD19);
    expect(moistureMarkerColor(20.1).toARGB32(), 0xFFCC2000);
  });
}
