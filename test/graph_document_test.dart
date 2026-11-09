import 'package:bugman_graphs/models/freehand_stroke.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final job = Job(
    customerName: 'Ada Customer',
    serviceAddress: '1 Graph Lane',
    pestPacLocationNumber: 'LOC-100',
    pestPacBillToNumber: 'BILL-200',
    serviceType: 'Inspection',
    createdBy: 'Inspector',
    createdDate: DateTime(2026, 7, 14),
  );

  test('tracks dirty state for graph and layer changes', () {
    final document = GraphDocument.forJob(job);

    expect(document.isDirty, isFalse);
    expect(document.revision, 0);
    expect(document.id, job.id);
    expect(document.createdAt, job.createdDate);
    expect(document.customer.pestPacLocationNumber, 'LOC-100');
    expect(document.customer.pestPacBillToNumber, 'BILL-200');

    document.replaceWallSegments(const [
      WallSegment(
        start: GraphPoint(x: 10, y: 20),
        end: GraphPoint(x: 80, y: 20),
      ),
    ]);

    expect(document.isDirty, isTrue);
    expect(document.revision, 1);

    document.markClean();
    expect(document.isDirty, isFalse);

    document.setLayer(
      'findings',
      document.layer('findings').copyWith(locked: true),
    );
    expect(document.isDirty, isTrue);
    expect(document.layer('findings').locked, isTrue);
  });

  test('round-trips every graph object through the document format', () {
    final document = GraphDocument(
      customer: GraphCustomerInfo.fromJob(job),
      wallSegments: const [
        WallSegment(
          start: GraphPoint(x: 1, y: 2),
          end: GraphPoint(x: 40, y: 45),
          controlPoint: GraphPoint(x: 20, y: 5),
          color: Color(0xFF245BDB),
          hasArrow: true,
        ),
      ],
      annotations: const [
        GraphAnnotation(
          kind: GraphAnnotationKind.marker,
          point: GraphPoint(x: 12, y: 18),
          label: 'Active termites',
          markerType: GraphMarkerType.activeTermites,
          note: 'Photo 1',
        ),
      ],
      shapes: const [
        GraphShape(
          name: 'Circle 1',
          segmentIndexes: [0],
          fillColor: Color(0xFFB6D94C),
          fillOpacity: 0.3,
          borderColor: Color(0xFF214D38),
          borderWidth: 3,
          pattern: GraphShapePattern.dots,
          closed: true,
          rotationDegrees: 15,
          text: 'Kitchen',
        ),
      ],
      freehandStrokes: const [
        FreehandStroke(
          points: [GraphPoint(x: 3, y: 4), GraphPoint(x: 9, y: 12)],
        ),
      ],
      metadata: const {'inspectionId': 'I-42'},
      traces: const [
        TraceGeometry(
          id: 'property',
          label: 'Property boundary',
          geoPoints: [
            GeoPoint(latitude: 35, longitude: -86),
            GeoPoint(latitude: 35.001, longitude: -86),
          ],
          canvasPoints: [
            GraphPoint(x: 10, y: 10),
            GraphPoint(x: 10, y: 100),
          ],
          closed: false,
        ),
      ],
      measurementCalibration: const MeasurementCalibration(
        source: MeasurementSource.mapGeodesic,
        status: MeasurementAccuracyStatus.verified,
      ),
    );

    final restored = GraphDocument.fromJson(document.toJson());

    expect(restored.customer.name, 'Ada Customer');
    expect(restored.customer.pestPacLocationNumber, 'LOC-100');
    expect(restored.customer.pestPacBillToNumber, 'BILL-200');
    expect(restored.wallSegments.single.isCurve, isTrue);
    expect(restored.wallSegments.single.hasArrow, isTrue);
    expect(
        restored.annotations.single.markerType, GraphMarkerType.activeTermites);
    expect(restored.shapes.single.pattern, GraphShapePattern.dots);
    expect(restored.shapes.single.text, 'Kitchen');
    expect(restored.freehandStrokes.single.points, hasLength(2));
    expect(restored.metadata['inspectionId'], 'I-42');
    expect(restored.traces.single.label, 'Property boundary');
    expect(restored.traces.single.geoPoints.first.latitude, 35);
    expect(
      restored.measurementCalibration.status,
      MeasurementAccuracyStatus.verified,
    );
    expect(restored.toJson()['schemaVersion'], 5);
    expect(restored.isDirty, isFalse);
  });

  test('loads the original flat graph payload', () {
    final restored = GraphDocument.fromJson({
      'legacyVendorField': 'keep-me',
      'job': {
        'customerName': 'Legacy Customer',
        'serviceAddress': 'Old Format Road',
        'pestPacAccountNumber': 'LEGACY-300',
      },
      'wallSegments': [
        {
          'start': {'x': 0, 'y': 0},
          'end': {'x': 24, 'y': 0},
        },
      ],
      'annotations': <Object?>[],
      'shapes': [
        {
          'name': 'Legacy Main',
          'segmentIndexes': [0],
          'closed': true,
          'legacyShapeField': 42,
        },
      ],
      'freehandStrokes': <Object?>[],
    });

    expect(restored.customer.name, 'Legacy Customer');
    expect(restored.customer.pestPacLocationNumber, 'LEGACY-300');
    expect(restored.customer.pestPacBillToNumber, isEmpty);
    expect(restored.wallSegments.single.measurementLabel, '1 lf');
    expect(restored.shapes.single.name, 'Legacy Main');
    expect(restored.shapes.single.extraProperties['legacyShapeField'], 42);
    expect(restored.toJson()['legacyVendorField'], 'keep-me');
    final customerJson = restored.toJson()['customer'] as Map<String, Object?>;
    expect(customerJson['pestPacLocationNumber'], 'LEGACY-300');
    expect(customerJson['pestPacBillToNumber'], '');
    expect(customerJson['pestPacAccountNumber'], 'LEGACY-300');
  });

  test('persists stable photo references and the next pin number', () {
    final document = GraphDocument(
      customer: GraphCustomerInfo.fromJob(job),
      annotations: const [
        GraphAnnotation(
          id: 'pin-3',
          kind: GraphAnnotationKind.photo,
          point: GraphPoint(x: 20, y: 30),
          label: '3',
          attachmentIds: ['photo-3a'],
        ),
      ],
      attachments: const [
        GraphAttachment(
          id: 'photo-3a',
          name: 'inspection.jpg',
          annotationId: 'pin-3',
          referenceLabel: '3a',
        ),
      ],
      metadata: const {'nextPhotoNumber': 4},
    );

    final restored = GraphDocument.fromJson(document.toJson());
    expect(restored.attachments.single.referenceLabel, '3a');
    expect(restored.nextPhotoNumber, 4);
    expect(restored.reservePhotoNumber(), 4);
    expect(restored.nextPhotoNumber, 5);
  });

  test('retains marker category and type in saved documents', () {
    final document = GraphDocument(
      customer: GraphCustomerInfo.fromJob(job),
      annotations: const [
        GraphAnnotation(
          kind: GraphAnnotationKind.marker,
          point: GraphPoint(x: 20, y: 30),
          label: 'VD',
          markerType: GraphMarkerType.verticalDrill,
        ),
      ],
    );

    final restored = GraphDocument.fromJson(document.toJson());
    expect(
        restored.annotations.single.markerType, GraphMarkerType.verticalDrill);
    expect(restored.annotations.single.markerType.category,
        GraphMarkerCategory.treatment);
  });

  test('older graphs retain marker types removed from new-placement UI', () {
    final restored = GraphDocument.fromJson({
      'schemaVersion': 2,
      'customer': GraphCustomerInfo.fromJob(job).toJson(),
      'annotations': [
        {
          'kind': 'marker',
          'point': {'x': 42, 'y': 64},
          'label': 'AT',
          'markerType': 'activeTermites',
        },
        {
          'kind': 'marker',
          'point': {'x': 80, 'y': 96},
          'label': 'CAM',
          'markerType': 'camera',
        },
      ],
    });

    expect(restored.annotations.map((item) => item.markerType), [
      GraphMarkerType.activeTermites,
      GraphMarkerType.camera,
    ]);
    final roundTripped = GraphDocument.fromJson(restored.toJson());
    expect(roundTripped.annotations, hasLength(2));
  });

  test('re-saving identical structural content does not dirty the document', () {
    final document = GraphDocument.forJob(job);
    const segments = [
      WallSegment(
        start: GraphPoint(x: 10, y: 20),
        end: GraphPoint(x: 80, y: 20),
      ),
    ];

    document.replaceWallSegments(segments);
    document.markClean();
    expect(document.isDirty, isFalse);

    document.replaceMetadata(document.metadata);
    expect(document.isDirty, isFalse, reason: 'unchanged metadata should not dirty the document');

    document.updateCustomer(document.customer);
    expect(document.isDirty, isFalse, reason: 'unchanged customer info should not dirty the document');

    document.setMeasurementCalibration(document.measurementCalibration);
    expect(document.isDirty, isFalse, reason: 'unchanged calibration should not dirty the document');

    document.setLayer('structure', document.layer('structure'));
    expect(document.isDirty, isFalse, reason: 'unchanged layer state should not dirty the document');

    document.replaceAttachments(document.attachments);
    expect(document.isDirty, isFalse, reason: 'unchanged attachments should not dirty the document');

    document.updateJob(job);
    expect(document.isDirty, isFalse, reason: 're-syncing the same job should not dirty the document');

    final differentJob = Job(
      customerName: 'Different Customer',
      serviceAddress: job.serviceAddress,
      pestPacLocationNumber: job.pestPacLocationNumber,
      pestPacBillToNumber: job.pestPacBillToNumber,
      serviceType: job.serviceType,
      createdBy: job.createdBy,
      createdDate: DateTime(2027, 1, 1),
    );
    document.updateJob(differentJob);
    expect(document.isDirty, isTrue, reason: 'a real customer change must still dirty the document');
  });

  test('updateJob never rewrites the original Creation Date', () {
    final document = GraphDocument.forJob(job);
    final originalCreatedAt = document.createdAt;
    document.markClean();

    final laterJob = Job(
      customerName: 'Renamed Customer',
      serviceAddress: job.serviceAddress,
      pestPacLocationNumber: job.pestPacLocationNumber,
      pestPacBillToNumber: job.pestPacBillToNumber,
      serviceType: job.serviceType,
      createdBy: job.createdBy,
      createdDate: DateTime(2030, 5, 5),
    );

    document.updateJob(laterJob);

    expect(document.createdAt, originalCreatedAt,
        reason: 'Creation Date must be set once and never reset by later job edits');
    expect(document.customer.name, 'Renamed Customer');
    expect(document.isDirty, isTrue);
  });

  test('duplicateStructureFrom copies only wall/shape geometry and never touches the source', () {
    final source = GraphDocument(
      customer: GraphCustomerInfo.fromJob(job),
      wallSegments: const [
        WallSegment(start: GraphPoint(x: 0, y: 0), end: GraphPoint(x: 100, y: 0)),
      ],
      shapes: const [
        GraphShape(
          name: 'Main Structure',
          segmentIndexes: [0],
          fillColor: null,
          fillOpacity: 0.3,
          borderColor: Color(0xFF214D38),
          borderWidth: 3,
          pattern: GraphShapePattern.none,
          closed: true,
          rotationDegrees: 0,
        ),
      ],
      annotations: const [
        GraphAnnotation(
          kind: GraphAnnotationKind.marker,
          point: GraphPoint(x: 10, y: 10),
          label: 'AT',
          markerType: GraphMarkerType.activeTermites,
        ),
      ],
      attachments: const [
        GraphAttachment(id: 'photo-1', name: 'photo.jpg'),
      ],
      metadata: const {'nextPhotoNumber': 7},
    );
    source.markClean();
    final sourceJsonBefore = source.toJson();

    final duplicate = GraphDocument.duplicateStructureFrom(source);

    expect(duplicate.id, isNot(source.id), reason: 'duplicate must get its own fresh id');
    expect(duplicate.wallSegments, hasLength(1));
    expect(duplicate.shapes, hasLength(1));
    expect(duplicate.annotations, isEmpty, reason: 'annotations must not carry over');
    expect(duplicate.attachments, isEmpty, reason: 'attachments must not carry over');
    expect(duplicate.metadata['nextPhotoNumber'], isNull, reason: 'metadata must not carry over');
    expect(duplicate.isDirty, isTrue, reason: 'a new structure copy must allow its first save before further edits');
    expect(duplicate.customer.name, source.customer.name);

    // Mutating the duplicate must never affect the original source document.
    duplicate.replaceWallSegments(const []);
    expect(source.wallSegments, hasLength(1),
        reason: 'editing the duplicate must never mutate the original');
    expect(source.toJson(), sourceJsonBefore,
        reason: 'the original document must be completely untouched');
  });

  test('withNewIdentity copies every field but assigns a fresh id', () {
    final source = GraphDocument(
      customer: GraphCustomerInfo.fromJob(job),
      wallSegments: const [
        WallSegment(start: GraphPoint(x: 0, y: 0), end: GraphPoint(x: 50, y: 0)),
      ],
      annotations: const [
        GraphAnnotation(
          kind: GraphAnnotationKind.marker,
          point: GraphPoint(x: 5, y: 5),
          label: 'M',
          markerType: GraphMarkerType.moisture,
        ),
      ],
    );

    final copy = GraphDocument.withNewIdentity(source);

    expect(copy.id, isNot(source.id));
    expect(copy.wallSegments, hasLength(1));
    expect(copy.annotations, hasLength(1));
    expect(copy.annotations.single.markerType, GraphMarkerType.moisture);
  });

  test(
      'buildGraphFileName matches holloman-ops-brain\'s server-side format '
      'for every file kind (item 9)', () {
    const customer = GraphCustomerInfo(
      name: 'Ada  Customer!!',
      serviceAddress: '1 Graph Lane',
      pestPacLocationNumber: 'LOC-100',
      pestPacBillToNumber: 'BILL-200',
      serviceType: 'Inspection',
      createdBy: 'J. Inspector',
    );
    final createdAt = DateTime(2026, 7, 14);

    // MM-DD-YY, then sanitized BillTo-Name-ServiceType-CreatedBy segments,
    // then the kind suffix and extension -- mirrors
    // bugManGraphFileName()/sanitizeBugManFileSegment()/
    // formatBugManFileDate() in holloman-ops-brain's
    // functions/api/[[path]].js exactly.
    expect(
      buildGraphFileName(customer, createdAt, GraphFileKind.bgraph),
      '07-14-26-BILL-200-Ada-Customer-Inspection-J-Inspector-BGRAPH.bgraph',
    );
    expect(
      buildGraphFileName(customer, createdAt, GraphFileKind.pdfExport),
      '07-14-26-BILL-200-Ada-Customer-Inspection-J-Inspector-PDFEXPORT.pdf',
    );
    expect(
      buildGraphFileName(customer, createdAt, GraphFileKind.pngExport),
      '07-14-26-BILL-200-Ada-Customer-Inspection-J-Inspector-PNGEXPORT.png',
    );

    // Blank optional segments (e.g. no BillTo) are dropped rather than
    // leaving stray double-hyphens in the filename.
    const noBillTo = GraphCustomerInfo(
      name: 'Ada Customer',
      serviceAddress: '1 Graph Lane',
      pestPacLocationNumber: 'LOC-100',
      pestPacBillToNumber: '',
      serviceType: 'Inspection',
      createdBy: 'Inspector',
    );
    expect(
      buildGraphFileName(noBillTo, createdAt, GraphFileKind.bgraph),
      '07-14-26-Ada-Customer-Inspection-Inspector-BGRAPH.bgraph',
    );
  });
}
