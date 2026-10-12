import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/models/graph_annotation.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/services/graph_pdf_photos.dart';
import 'graph_pdf_print_layout_test.dart' show printFixture, photo;

GraphDocument photoDocument() => printFixture('small')
  ..replaceAnnotations([
    const GraphAnnotation(
        id: 'photo-reference',
        kind: GraphAnnotationKind.photo,
        label: 'Synthetic photo',
        point: GraphPoint(x: 100, y: 100),
        attachmentIds: ['photo-2', 'photo-1'],
        note: 'Existing synthetic caption')
  ])
  ..replaceAttachments([
    const GraphAttachment(
        id: 'photo-1',
        name: 'portrait.jpg',
        referenceLabel: '1a',
        blobKey: 'portrait'),
    const GraphAttachment(
        id: 'photo-2',
        name: 'landscape.jpg',
        referenceLabel: '1b',
        blobKey: 'landscape')
  ]);
void main() {
  test(
      'photo loader preserves attachment order, reference labels, captions and bytes',
      () async {
    final doc = photoDocument(), before = doc.toJson();
    final portrait = photo(500, 900, 1), landscape = photo(900, 500, 2);
    final result = await loadGraphPdfPhotos(doc,
        loadBlob: (key) async => key == 'portrait' ? portrait : landscape);
    expect(result.map((p) => p.filename), ['portrait.jpg', 'landscape.jpg']);
    expect(result.map((p) => p.referenceLabel), ['1a', '1b']);
    expect(
        result.every((p) => p.caption == 'Existing synthetic caption'), isTrue);
    expect(result.first.bytes, portrait);
    expect(result.last.bytes, landscape);
    expect(doc.toJson(), before);
  });
  test(
      'missing photo blob fails explicitly without producing a partial appendix',
      () async {
    final doc = photoDocument(), before = doc.toJson();
    await expectLater(
        loadGraphPdfPhotos(doc,
            loadBlob: (key) async =>
                key == 'portrait' ? photo(50, 90, 1) : null),
        throwsA(isA<GraphPdfPhotoException>()
            .having((e) => e.message, 'message', contains('landscape.jpg'))));
    expect(doc.toJson(), before);
  });
  test('missing attachment reference fails explicitly', () async {
    final doc = photoDocument()..replaceAttachments([]);
    await expectLater(
        loadGraphPdfPhotos(doc, loadBlob: (_) async => null),
        throwsA(isA<GraphPdfPhotoException>().having((e) => e.message,
            'message', contains('referenced photo is unavailable'))));
  });
  test('unreadable photo bytes fail explicitly', () async {
    await expectLater(
        loadGraphPdfPhotos(photoDocument(),
            loadBlob: (_) async => Uint8List.fromList([1, 2, 3])),
        throwsA(isA<GraphPdfPhotoException>()));
  });
}
