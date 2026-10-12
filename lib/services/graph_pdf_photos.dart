import 'dart:typed_data';
import '../models/graph_document.dart';
import 'graph_pdf_export.dart';

class GraphPdfPhotoException implements Exception {
  const GraphPdfPhotoException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<List<GraphPdfPhoto>> loadGraphPdfPhotos(GraphDocument source,
    {required Future<Uint8List?> Function(String blobKey) loadBlob}) async {
  final photoIds = source.photos.expand((a) => a.attachmentIds).toSet();
  final attachments = {for (final a in source.attachments) a.id: a};
  if (photoIds.any((id) => !attachments.containsKey(id))) {
    throw const GraphPdfPhotoException(
        'PDF not exported: a referenced photo is unavailable. Restore the photo or remove its reference before retrying.');
  }
  final result = <GraphPdfPhoto>[];
  for (final attachment in source.attachments) {
    if (!photoIds.contains(attachment.id)) continue;
    final bytes = await loadBlob(attachment.blobKey);
    if (bytes == null || !GraphPdfExport.isReadablePhoto(bytes)) {
      throw GraphPdfPhotoException(
          'PDF not exported: photo "${attachment.name}" is unavailable or unreadable. Restore the photo or remove its reference before retrying.');
    }
    result.add(GraphPdfPhoto(
        referenceLabel: attachment.referenceLabel.isEmpty
            ? 'Photo'
            : attachment.referenceLabel,
        filename: attachment.name,
        caption: source.photos
                .where((a) => a.attachmentIds.contains(attachment.id))
                .map((a) => a.note)
                .firstOrNull ??
            '',
        bytes: bytes));
  }
  return result;
}
