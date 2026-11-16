import 'dart:convert';
import 'dart:io';

import 'dart:ui' as ui;

import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/services/graph_pdf_export.dart';
import 'package:bugman_graphs/services/measurement_service.dart';
import 'package:bugman_graphs/services/trace_area_service.dart';
import 'package:bugman_graphs/services/trace_imagery_service.dart';
import 'package:bugman_graphs/services/trace_projection_service.dart';
import 'package:bugman_graphs/widgets/trace_geometry_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

TraceGeometry rectangle(
    String label, double x, double y, double width, double height) {
  const origin = GeoPoint(latitude: 35, longitude: -78);
  return TraceGeometry(
      id: label,
      label: label,
      canvasPoints: const [],
      geoPoints: [
        for (final p in [
          Offset(x, y),
          Offset(x + width, y),
          Offset(x + width, y + height),
          Offset(x, y + height)
        ])
          TraceProjectionService.moveGeoPointByCanvasDelta(
              point: origin, canvasDelta: p, metersPerCanvasUnit: 0.3048),
      ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final yard = rectangle('Yard', 0, 0, 100, 100);
  final house = rectangle('Home', 10, 10, 20, 40);
  final building = rectangle('Building', 70, 70, 10, 10);
  final plan = yard.copyWith(exclusions: [house, building]);

  test('100x100 ft yard less two buildings has 9100 sf net', () {
    expect(TraceAreaService.validate(plan), isNull);
    expect(
        MeasurementService.geodesicAreaSquareMeters(yard.geoPoints) *
            10.763910416709722,
        closeTo(10000, 0.1));
    expect(TraceAreaService.excludedSquareMeters(plan) * 10.763910416709722,
        closeTo(900, 0.1));
    expect(TraceAreaService.netSquareMeters(plan) * 10.763910416709722,
        closeTo(9100, 0.1));
    expect(TraceAreaService.netSquareMeters(plan) / 4046.8564224,
        closeTo(9100 / 43560, 0.00001));
  });
  test('rejects overlap, containment, touching, outside and self intersections',
      () {
    for (final invalid in [
      rectangle('Overlap', 20, 20, 20, 20),
      rectangle('Nested', 15, 15, 5, 5),
      rectangle('Touches', 30, 10, 10, 10),
      rectangle('Outside', 95, 95, 10, 10),
      house.copyWith(geoPoints: [
        house.geoPoints[0],
        house.geoPoints[2],
        house.geoPoints[1],
        house.geoPoints[3]
      ]),
      house.copyWith(geoPoints: house.geoPoints.take(2).toList()),
    ]) {
      expect(
          TraceAreaService.validate(
              yard.copyWith(exclusions: [house, invalid])),
          isNotNull,
          reason: invalid.label);
    }
    final bowtie = yard.copyWith(geoPoints: [
      yard.geoPoints[0],
      yard.geoPoints[2],
      yard.geoPoints[1],
      yard.geoPoints[3]
    ]);
    expect(TraceAreaService.validate(bowtie), isNotNull);
  });
  test('rejects an exclusion edge crossing a concave boundary', () {
    final concave = rectangle('Concave', 0, 0, 100, 100);
    final notch = rectangle('Notch', 40, 40, 20, 60);
    final ring = [
      concave.geoPoints[0],
      concave.geoPoints[1],
      concave.geoPoints[2],
      notch.geoPoints[2],
      notch.geoPoints[1],
      notch.geoPoints[0],
      notch.geoPoints[3],
      concave.geoPoints[3]
    ];
    expect(
        TraceAreaService.validate(concave.copyWith(
            geoPoints: ring,
            exclusions: [rectangle('Crossing notch', 30, 30, 40, 20)])),
        isNotNull);
  });
  test('old graph loads, new graph round trips imagery and deductions', () {
    final legacy = TraceGeometry.fromJson(yard.toJson());
    expect(legacy.exclusions, isEmpty);
    expect(legacy.imagery, isNull);
    const imagery = TraceImagery(
        base64Jpeg: 'fixture',
        capturedAt: '2026-11-10T00:00:00Z',
        corners: [
          GraphPoint(x: 0, y: 0),
          GraphPoint(x: 100, y: 0),
          GraphPoint(x: 0, y: 100)
        ]);
    final doc = GraphDocument(
        customer: const GraphCustomerInfo(
            name: 'QA',
            serviceAddress: '',
            pestPacLocationNumber: '',
            pestPacBillToNumber: '',
            serviceType: '',
            createdBy: 'QA'),
        layers: const {'trace': GraphLayerState(visible: true)},
        traces: [plan.copyWith(imagery: imagery)]);
    final reopened = GraphDocument.fromJson(
        jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
    expect(reopened.traces.single.imagery!.base64Jpeg, 'fixture');
    expect(reopened.traces.single.exclusions.map((e) => e.label),
        ['Home', 'Building']);
    expect(TraceAreaService.netSquareMeters(reopened.traces.single),
        TraceAreaService.netSquareMeters(plan));
    final moved = reopened.traces.single
        .transformCanvas((p) => GraphPoint(x: p.x + 100, y: p.y + 50));
    expect(moved.imagery!.corners.first.x, 100);
    expect(moved.exclusions.first.geoPoints.first.latitude,
        house.geoPoints.first.latitude);
    final summary = GraphPdfExport.summariesForDocument(doc)
        .map((e) => e.measurements.join(' '))
        .join(' ');
    expect(summary, contains('Net yard: 0.21 ac (9100 sf)'));
    doc.dispose();
    reopened.dispose();
  });
  test('exclusions share the boundary coordinate frame', () {
    final boundary = TraceProjectionService.projectToCanvas(yard.geoPoints,
        canvasSize: const Size(3600, 2600));
    final exclusion = TraceProjectionService.projectToCanvas(house.geoPoints,
        canvasSize: const Size(3600, 2600), referencePoints: yard.geoPoints);
    expect(exclusion.canvasPoints.first.x - boundary.canvasPoints.first.x,
        closeTo(10 * 24, 0.01));
    expect(exclusion.canvasPoints.first.y - boundary.canvasPoints.first.y,
        closeTo(10 * 24, 0.01));
  });
  testWidgets(
      'snapshot uses public tiles, renders offline, and stays aligned after rotation',
      (tester) async {
    if (Platform.environment['TRACE_QA_OUTPUT'] != null) {
      final loader = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
      await tester.runAsync(loader.load);
    }
    final tile = img.Image(width: 256, height: 256)
      ..clear(img.ColorRgb8(40, 130, 70));
    final tileBytes = img.encodeJpg(tile);
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response.bytes(tileBytes, 200,
          headers: {'content-type': 'image/jpeg'});
    });
    final service = TraceImageryService(client: client);
    final corners = [yard.geoPoints[0], yard.geoPoints[1], yard.geoPoints[3]];
    const canvasCorners = [
      GraphPoint(x: 100, y: 100),
      GraphPoint(x: 700, y: 100),
      GraphPoint(x: 100, y: 700)
    ];
    final imagery = await tester.runAsync(
        () => service.capture(corners: corners, canvasCorners: canvasCorners));
    expect(requests, isNotEmpty);
    expect(requests.length, lessThanOrEqualTo(64));
    expect(
        requests.every((uri) => uri.path.contains('/tile/') && !uri.hasQuery),
        isTrue);
    final decoded = img.decodeJpg(base64Decode(imagery!.base64Jpeg))!;
    expect(decoded.width, 1600);
    expect(decoded.height, closeTo(1600, 1));
    await tester.runAsync(() => TraceImageryCache.instance.load(imagery));
    final projected = yard.copyWith(canvasPoints: const [
      GraphPoint(x: 150, y: 150),
      GraphPoint(x: 650, y: 150),
      GraphPoint(x: 650, y: 650),
      GraphPoint(x: 150, y: 650)
    ], imagery: imagery);
    final rotated =
        projected.transformCanvas((p) => GraphPoint(x: 800 - p.y, y: p.x));
    final recorder = ui.PictureRecorder();
    TraceGeometryPainter(traces: [rotated])
        .paint(Canvas(recorder), const Size(800, 800));
    final picture = recorder.endRecording();
    final rendered = await tester.runAsync(() => picture.toImage(800, 800));
    final png = await tester
        .runAsync(() => rendered!.toByteData(format: ui.ImageByteFormat.png));
    final output = img.decodePng(png!.buffer.asUint8List())!;
    // Visible photo outside the boundary is unaffected by boundary fill/labels.
    final pixel = output.getPixel(125, 125);
    expect(pixel.g, greaterThan(pixel.r + 60));
    final exportTrace = rotated.copyWith(exclusions: [
      house.copyWith(canvasPoints: const [
        GraphPoint(x: 450, y: 250),
        GraphPoint(x: 550, y: 250),
        GraphPoint(x: 550, y: 450),
        GraphPoint(x: 450, y: 450)
      ])
    ]);
    final exportDocument = GraphDocument(
        customer: const GraphCustomerInfo(
            name: 'Yard acreage QA',
            serviceAddress: 'Synthetic measurement fixture',
            pestPacLocationNumber: '',
            pestPacBillToNumber: '',
            serviceType: 'Measurement',
            createdBy: 'QA'),
        traces: [exportTrace],
        layers: const {'trace': GraphLayerState(visible: true)});
    final exportRecorder = ui.PictureRecorder();
    TraceGeometryPainter(traces: [exportTrace])
        .paint(Canvas(exportRecorder), const Size(800, 800));
    final exportPicture = exportRecorder.endRecording();
    final exportImage =
        await tester.runAsync(() => exportPicture.toImage(800, 800));
    final exportPng = await tester.runAsync(
        () => exportImage!.toByteData(format: ui.ImageByteFormat.png));
    final pdf = await tester.runAsync(() => GraphPdfExport.build(
        graphPng: exportPng!.buffer.asUint8List(),
        sourceDocument: exportDocument,
        title: 'Yard acreage QA'));
    expect(pdf, isNotNull);
    expect(ascii.decode(pdf!.take(4).toList()), '%PDF');
    final artifactPath = Platform.environment['TRACE_QA_OUTPUT'];
    if (artifactPath != null) {
      await tester.runAsync(() async {
        await Directory(artifactPath).create(recursive: true);
        await File('$artifactPath/yard-acreage.png')
            .writeAsBytes(exportPng!.buffer.asUint8List());
        await File('$artifactPath/yard-acreage.pdf').writeAsBytes(pdf);
      });
    }
    exportImage!.dispose();
    exportPicture.dispose();
    exportDocument.dispose();
    rendered!.dispose();
    picture.dispose();
    client.close();
  });
  testWidgets(
      'failed tile fetch reports failure rather than saving a blank photo',
      (tester) async {
    final client = MockClient((_) async => http.Response('Unavailable', 503));
    await tester.runAsync(() async {
      await expectLater(
          TraceImageryService(client: client).capture(corners: [
            yard.geoPoints[0],
            yard.geoPoints[1],
            yard.geoPoints[3]
          ], canvasCorners: const []),
          throwsStateError);
    });
    client.close();
  });
}
