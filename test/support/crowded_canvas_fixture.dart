import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:flutter/material.dart';

GraphDocument crowdedCanvasFixture() {
  const points = [GraphPoint(x: 300,y: 300), GraphPoint(x: 2100,y: 300),
    GraphPoint(x: 2100,y: 1300), GraphPoint(x: 2400,y: 1300),
    GraphPoint(x: 2400,y: 1800), GraphPoint(x: 2300,y: 1820),
    GraphPoint(x: 2290,y: 1890), GraphPoint(x: 2250,y: 1895),
    GraphPoint(x: 2230,y: 1850), GraphPoint(x: 2200,y: 1880),
    GraphPoint(x: 2180,y: 1850), GraphPoint(x: 2140,y: 1870),
    GraphPoint(x: 2100,y: 1850), GraphPoint(x: 2100,y: 1780),
    GraphPoint(x: 300,y: 1780)];
  const corners = [GraphPoint(x: 850,y: 700), GraphPoint(x: 1550,y: 700),
    GraphPoint(x: 1550,y: 1200), GraphPoint(x: 850,y: 1200)];
  const labelCorners = [GraphPoint(x: 2140,y: 1850), GraphPoint(x: 2180,y: 1850),
    GraphPoint(x: 2180,y: 1920), GraphPoint(x: 2140,y: 1920)];
  return GraphDocument(id: 'synthetic-canvas-review', customer: const GraphCustomerInfo(
    name: 'Synthetic canvas review', serviceAddress: '', pestPacLocationNumber: '',
    pestPacBillToNumber: '', serviceType: 'Inspection', createdBy: 'Regression fixture'),
    layers: const {'trace': GraphLayerState(visible: true)},
    wallSegments: [for(final polygon in [corners,labelCorners])
      for(var i=0;i<4;i++) WallSegment(start: polygon[i],end: polygon[(i+1)%4])],
    shapes: const [GraphShape(name: 'Main Structure',segmentIndexes: [0,1,2,3],fillColor: Colors.green,
      fillOpacity: 0.15,borderColor: Colors.green,borderWidth: 3,pattern: GraphShapePattern.none,
      closed: true,rotationDegrees: 0,preset: GraphDrawingPreset.mainStructure),
      GraphShape(name: 'Treatment',text: 'Treatment Area',segmentIndexes: [4,5,6,7],fillColor: Colors.yellow,
      fillOpacity: 0.3,borderColor: Colors.orange,borderWidth: 2,pattern: GraphShapePattern.none,
      closed: true,rotationDegrees: 0)],
    annotations: const [GraphAnnotation(id: 'overlay-marker',kind: GraphAnnotationKind.marker,
      point: GraphPoint(x:850,y:700),label:'Side Door',markerType: GraphMarkerType.entryPoint),
      GraphAnnotation(id: 'overlay-marker-2',kind: GraphAnnotationKind.marker,
      point: GraphPoint(x:850,y:700),label:'Mud Tube',markerType: GraphMarkerType.mudTube)],
    traces: [TraceGeometry(id:'crowded-trace',label:'Property Trace',canvasPoints:points,
      geoPoints: [for(final p in points) GeoPoint(latitude: p.y * 0.00000012,longitude:p.x * 0.00000012)],
      metersPerCanvasUnit:0.013)]);
}
