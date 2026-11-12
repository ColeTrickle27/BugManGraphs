import 'dart:convert';
import 'dart:typed_data';

import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/screens/home_screen.dart';
import 'package:bugman_graphs/screens/new_job_screen.dart';
import 'package:bugman_graphs/services/graph_repository.dart';
import 'package:bugman_graphs/services/graph_repository_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> stationGraph(String markerType,
        {bool flat = false, bool details = true}) =>
    {
      'id': 'synthetic-station',
      'customer': {
        'name': 'Synthetic station',
        'pestPacLocationNumber': '990001'
      },
      if (flat)
        'annotations': [annotation(markerType, details: details)]
      else
        'graphObjects': {
          'annotations': [annotation(markerType, details: details)],
        },
      'measurementCalibration': {
        'source': 'calibratedImage',
        'status': 'verified',
        'metersPerCanvasUnit': 0.2,
      },
    };

Map<String, Object?> annotation(String markerType, {bool details = true}) => {
      'id': 'physical-station-4',
      'kind': 'marker',
      'point': {'x': 20, 'y': 30},
      'label': '#4',
      'markerType': markerType,
      if (details)
        'atbsStation': {
          'schema': 1,
          'status': markerType.startsWith('planned') ? 'planned' : 'installed',
          'type': markerType.contains('Soil') ? 'soil' : 'core',
          'id': 'physical-station-4',
          'physicalNumber': 4,
          'routeId': 'physical-route-1',
        },
    };

class StoredStationRepository extends MemoryGraphRepository {
  int writes = 0;

  @override
  Future<List<SavedGraphSummary>> listGraphs() async => [
        summaryForDocument(
            GraphDocument.fromJson(stationGraph('installedCoreStation'))),
      ];

  @override
  Future<GraphDocument?> loadGraph(String id) async =>
      GraphDocument.fromJson(stationGraph('installedCoreStation'));

  @override
  Future<void> saveGraph(GraphDocument document,
      {Map<String, Uint8List> blobs = const {},
      Set<String> deletedBlobKeys = const {}}) async {
    writes++;
    await super
        .saveGraph(document, blobs: blobs, deletedBlobKeys: deletedBlobKeys);
  }
}

void main() {
  testWidgets(
      'gallery job-information editing defers station files without writes',
      (tester) async {
    final repository = StoredStationRepository();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repository),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic station'), findsOneWidget);
    await tester.tap(find.byTooltip('Job actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit job information'));
    await tester.pumpAndSettle();
    expect(find.text(GraphDocument.stationWorkspaceMessage), findsOneWidget);
    expect(find.byType(NewJobScreen), findsNothing);
    expect(repository.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });
  for (final marker in [
    'plannedSoilStation',
    'installedSoilStation',
    'plannedCoreStation',
    'installedCoreStation',
  ]) {
    for (final flat in [false, true]) {
      test(
          '$marker in ${flat ? 'legacy' : 'nested'} records cannot be rewritten',
          () async {
        final source = stationGraph(marker, flat: flat);
        final original = jsonEncode(source);
        final document = GraphDocument.fromJson(source);
        expect(document.requiresStationWorkspace, isTrue);
        expect(summaryForDocument(document).id, 'synthetic-station');
        final repository = MemoryGraphRepository();
        await expectLater(
            repository.saveGraph(document), throwsFormatException);
        expect(await repository.listGraphs(), isEmpty);
        expect(jsonEncode(source), original);
        expect(document.serializationState, jsonDecode(original));
      });
    }
  }

  test('already degraded station metadata is kept out of this editor', () {
    final document = GraphDocument.fromJson(stationGraph('damage'));
    expect(document.requiresStationWorkspace, isTrue);
    expect(() => document.toJson(), throwsFormatException);
  });

  test('legacy structure-only copies with retained station routes are deferred',
      () {
    final source = stationGraph('installedCoreStation');
    source['graphObjects'] = {
      'annotations': <Object?>[],
      'shapes': [
        {
          'stationRoutes': [
            {'schema': 1, 'status': 'installed', 'completed': true}
          ]
        }
      ]
    };
    final document = GraphDocument.fromJson(source);
    expect(document.requiresStationWorkspace, isTrue);
    expect(() => document.toJson(), throwsFormatException);
  });

  test('station type alone is sufficient even without metadata', () {
    final document = GraphDocument.fromJson(
        stationGraph('installedCoreStation', details: false));
    expect(document.requiresStationWorkspace, isTrue);
  });

  test('ordinary markers and unused text marker values remain supported', () {
    final source = stationGraph('damage', details: false);
    final objects = source['graphObjects']! as Map<String, Object?>;
    (objects['annotations']! as List).add({
      'id': 'history-note',
      'kind': 'text',
      'point': {'x': 1, 'y': 2},
      'label': 'Historical note',
      'markerType': 'installedCoreStation',
    });
    final document = GraphDocument.fromJson(source);
    expect(document.requiresStationWorkspace, isFalse);
    expect(document.toJson()['id'], source['id']);
  });

  for (final presentation in [false, true]) {
    testWidgets(
        'station ${presentation ? 'preview' : 'editor'} shows a safe exit',
        (tester) async {
      final document =
          GraphDocument.fromJson(stationGraph('installedCoreStation'));
      String? opened;
      await tester.pumpWidget(MaterialApp(
        home: GraphCanvasScreen(
          document: document,
          presentationMode: presentation,
          onPortalSignIn: (url) => opened = url,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(GraphDocument.stationWorkspaceMessage), findsOneWidget);
      expect(find.text('Canvas options'), findsNothing);
      expect(find.text('Save and share'), findsNothing);
      await tester.tap(find.text('Open OpsBrain'));
      expect(opened, 'https://ops.holloman-ext.com/');
      expect(document.isDirty, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
