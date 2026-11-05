import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/services/graph_image_export.dart';
import 'package:bugman_graphs/services/graph_pdf_export.dart';
import 'package:bugman_graphs/services/locked_graph_watermark.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

GraphDocument syntheticDocument() => GraphDocument.forJob(
      Job(
        customerName: 'Synthetic watermark test',
        serviceAddress: '125 Synthetic Lane',
        pestPacBillToNumber: '990901',
        pestPacLocationNumber: '990902',
        serviceType: 'Inspection',
        createdBy: 'Synthetic technician',
        createdDate: DateTime(2026, 10, 22),
      ),
    );

Future<Uint8List> scenePng(ui.Image logo, {required bool locked}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
  paintSyntheticScene(canvas, logo, locked: locked);
  final picture = recorder.endRecording();
  final image = await picture.toImage(800, 600);
  picture.dispose();
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
  }
}

void paintSyntheticScene(
  ui.Canvas canvas,
  ui.Image logo, {
  required bool locked,
}) {
  LockedGraphWatermark.paint(
    canvas,
    locked: locked,
    structureBounds: const ui.Rect.fromLTWH(100, 100, 600, 400),
    logo: logo,
  );
  // Drawn after the translucent mark: readings/dimensions remain fully opaque.
  canvas.drawRect(
    const ui.Rect.fromLTWH(100, 100, 600, 400),
    ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(390, 290, 20, 20),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'watermark follows world structure bounds, excludes treatment, never edits the document',
    () {
      final document = syntheticDocument();
      document.replaceWallSegments(const [
        WallSegment(
          start: GraphPoint(x: -500, y: -200),
          end: GraphPoint(x: -100, y: 100),
        ),
        WallSegment(
          start: GraphPoint(x: 5000, y: 5000),
          end: GraphPoint(x: 6000, y: 6000),
        ),
      ]);
      document.replaceShapes(const [
        GraphShape(
          name: 'Old treatment area',
          segmentIndexes: [1],
          fillColor: null,
          fillOpacity: 0,
          borderColor: ui.Color(0xFF000000),
          borderWidth: 1,
          pattern: GraphShapePattern.none,
          closed: false,
          rotationDegrees: 0,
          preset: GraphDrawingPreset.treatmentArea,
        ),
      ]);
      final before = jsonEncode(document.toJson());
      final bounds = LockedGraphWatermark.structureBounds(document);
      expect(bounds, const ui.Rect.fromLTRB(-500, -200, -100, 100));
      final destination = LockedGraphWatermark.destination(
        bounds,
        const ui.Size(1000, 1000),
      )!;
      expect(destination.center, bounds!.center);
      expect(bounds.contains(destination.topLeft), isTrue);
      expect(bounds.contains(destination.bottomRight), isTrue);
      expect(jsonEncode(document.toJson()), before);
      expect(LockedGraphWatermark.structureBounds(syntheticDocument()), isNull);
      expect(
        LockedGraphWatermark.destination(ui.Rect.zero, const ui.Size(10, 10)),
        isNull,
      );
    },
  );

  test('filtered presentation watermark excludes hidden distant freehand', () {
    final document = GraphDocument.fromJson({
      'wallSegments': [
        {
          'start': {'x': 0, 'y': 0},
          'end': {'x': 200, 'y': 200}
        }
      ],
      'freehandStrokes': [
        {
          'points': [
            {'x': 5000, 'y': 5000},
            {'x': 6000, 'y': 6000}
          ]
        }
      ]
    });
    expect(document.freehandStrokes, hasLength(1));
    final bounds =
        LockedGraphWatermark.structureBounds(document, includeFreehand: false);
    expect(bounds, const ui.Rect.fromLTRB(0, 0, 200, 200));
    expect(
        LockedGraphWatermark.destination(bounds, const ui.Size(1000, 1000))!
            .center,
        const ui.Offset(100, 100));
    document.dispose();
  });

  testWidgets(
    'authorized brand is translucent, structure labels remain opaque, unlocked copy has no mark',
    (tester) async {
      await tester.runAsync(() async {
        final logo = await LockedGraphWatermark.loadLogo();
        try {
          final locked = img.decodePng(await scenePng(logo, locked: true))!;
          final unlocked = img.decodePng(await scenePng(logo, locked: false))!;
          expect(locked.getPixel(400, 300).r, 0);
          expect(locked.getPixel(400, 300).g, 0);
          var changed = 0;
          for (var y = 150; y < 450; y++) {
            for (var x = 150; x < 650; x++) {
              if (x >= 390 && x < 410 && y >= 290 && y < 310) continue;
              final pixel = locked.getPixel(x, y);
              final original = unlocked.getPixel(x, y);
              if (pixel.r != original.r ||
                  pixel.g != original.g ||
                  pixel.b != original.b) {
                changed++;
                expect(pixel.r, greaterThanOrEqualTo(215));
                expect(pixel.g, greaterThanOrEqualTo(215));
                expect(pixel.b, greaterThanOrEqualTo(215));
              }
            }
          }
          expect(changed, greaterThan(1000));
          expect(locked.getPixel(30, 30).r, 255);
          expect(unlocked.getPixel(350, 250).r, 255);
        } finally {
          logo.dispose();
        }
      });
    },
  );

  testWidgets(
    'shared scene produces identical live/export pixels and retains the marked diagram in multipage PDF',
    (tester) async {
      await tester.runAsync(() async {
        final logo = await LockedGraphWatermark.loadLogo();
        try {
          final live = await scenePng(logo, locked: true);
          final exported = await GraphImageExport.capturePng(
            RenderRepaintBoundary(),
            const ui.Rect.fromLTWH(0, 0, 800, 600),
            paintScene: (canvas, size) {
              canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
              paintSyntheticScene(canvas, logo, locked: true);
            },
          );
          expect(
            img.decodePng(exported)!.getBytes(),
            img.decodePng(live)!.getBytes(),
          );
          final singlePage = await GraphPdfExport.build(
            graphPng: exported,
            title: 'Locked synthetic graph',
          );
          final multipage = await GraphPdfExport.build(
            graphPng: exported,
            title: 'Locked synthetic graph',
            photos: [
              for (var index = 1; index <= 3; index++)
                GraphPdfPhoto(
                  referenceLabel: 'S$index',
                  filename: 'synthetic-$index.png',
                  bytes: exported,
                ),
            ],
          );
          int pages(Uint8List bytes) => RegExp(
                r'/Type\s*/Page\b',
              ).allMatches(latin1.decode(bytes)).length;
          expect(pages(singlePage), 1);
          expect(pages(multipage), 3);
          expect(multipage.length, greaterThan(singlePage.length));
          // PDF image input is exactly the same marked raster as PNG/live scene.
          // Platform PDF raster parity still requires the supported browser QA.
          expect(latin1.decode(multipage), contains('/Width 800'));
        } finally {
          logo.dispose();
        }
      });
    },
  );
}
