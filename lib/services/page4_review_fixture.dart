import 'package:web/web.dart' as web;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/graph_annotation.dart';
import '../models/graph_document.dart';
import '../models/graph_point.dart';
import '../models/graph_shape.dart';
import '../models/wall_segment.dart';
import 'bugman_portal_service.dart';

Map<String, String> get page4ReviewParameters =>
    Uri.parse(web.window.location.href).queryParameters;

/// Synthetic-only fixture, reachable solely from the isolated preview target.
void populateReviewFixture(GraphDocument document, String format) {
  final wide = format == 'wide';
  final tall = format == 'tall';
  final right = wide ? 3500.0 : 450.0;
  final bottom = tall ? 3400.0 : 400.0;
  final points = [
    const GraphPoint(x: -240, y: -180),
    GraphPoint(x: right, y: -180),
    GraphPoint(x: right, y: bottom),
    GraphPoint(x: -240, y: bottom)
  ];
  final segments = <WallSegment>[
    for (var i = 0; i < 4; i++)
      WallSegment(
          start: points[i],
          end: points[(i + 1) % 4],
          color: const Color(0xFF214D38),
          controlPoint: i == 3 ? GraphPoint(x: -500, y: bottom / 2) : null),
    WallSegment(
        start: GraphPoint(x: right + 70, y: -100),
        end: GraphPoint(x: right + 70, y: bottom),
        color: Colors.green,
        pattern: LinePattern.dashed),
    WallSegment(
        start: GraphPoint(x: right + 140, y: -100),
        end: GraphPoint(x: right + 140, y: bottom),
        color: Colors.blue,
        pattern: LinePattern.dashed),
  ];
  document.replaceWallSegments(segments);
  document.replaceShapes([
    const GraphShape(
        name: 'Synthetic Basement',
        segmentIndexes: [0, 1, 2, 3],
        fillColor: Color(0xFFE2EFC5),
        fillOpacity: .7,
        borderColor: Color(0xFF214D38),
        borderWidth: 3,
        pattern: GraphShapePattern.blockwork,
        closed: true,
        rotationDegrees: 0,
        preset: GraphDrawingPreset.basement)
  ]);
  document.replaceAnnotations([
    const GraphAnnotation(
        kind: GraphAnnotationKind.marker,
        point: GraphPoint(x: 300, y: 170),
        label: 'Termite activity',
        markerType: GraphMarkerType.termiteActivity),
    const GraphAnnotation(
        kind: GraphAnnotationKind.marker,
        point: GraphPoint(x: 200, y: 250),
        label: 'Steps side',
        markerType: GraphMarkerType.steps),
    const GraphAnnotation(
        kind: GraphAnnotationKind.text,
        point: GraphPoint(x: -420, y: -340),
        label: 'Synthetic callout\nCheck boundary',
        backgroundColor: Colors.white,
        borderColor: Color(0xFFC20000),
        extraProperties: {
          'calloutTipX': -240.0,
          'calloutTipY': -180.0,
          'calloutWidth': 240.0
        }),
    const GraphAnnotation(
        kind: GraphAnnotationKind.marker,
        point: GraphPoint(x: 100, y: 100),
        label: 'Access',
        markerType: GraphMarkerType.crawlspaceAccess),
    const GraphAnnotation(
        kind: GraphAnnotationKind.marker,
        point: GraphPoint(x: 240, y: 100),
        label: 'Piers',
        markerType: GraphMarkerType.pier),
    const GraphAnnotation(
        kind: GraphAnnotationKind.marker,
        point: GraphPoint(x: 100, y: 250),
        label: 'Steps',
        markerType: GraphMarkerType.stepsFront),
  ]);
}

/// Writes synthetic review exports only to the loopback review server.
class Page4ReviewPortal implements BugManPortalService {
  @override
  bool get isAvailable => true;
  @override
  String? buildCustomerFolderUrl({required String billToNumber,required String locationNumber}) => null;
  @override
  Future<PortalGraphPackage> loadGraph(String key) =>
      throw UnimplementedError();
  @override
  Future<PortalUploadResult> saveGraph(
          GraphDocument document, Map<String, Uint8List> blobs,
          {String? existingKey}) async =>
      const PortalUploadResult(
          key: 'synthetic-review', message: 'Synthetic review held in memory');
  @override
  Future<PortalUploadResult> uploadGraphExport(
      {required GraphCustomerInfo customer,
      required String fileName,
      required Uint8List bytes,
      required String contentType,
      required DateTime graphCreatedAt}) async {
    final format = page4ReviewParameters['fixture'] ?? 'standard';
    final extension = contentType == 'application/pdf' ? 'pdf' : 'png';
    final response = await http.post(
        Uri.base.resolve('/__review/$format.$extension'),
        body: bytes,
        headers: {'Content-Type': contentType});
    if (response.statusCode != 200) {
      throw StateError('Local review write failed: ${response.statusCode}');
    }
    return PortalUploadResult(
        key: fileName, message: 'Local $format $extension review exported');
  }

  @override
  String? buildSalesBrainReportUrl(
          {required String billToNumber,
          required String locationNumber,
          required String graphKey}) =>
      null;
}
