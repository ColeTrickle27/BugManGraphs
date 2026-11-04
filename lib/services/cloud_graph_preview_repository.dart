import 'dart:typed_data';

import '../models/graph_document.dart';
import 'bugman_portal_service.dart';
import 'graph_repository.dart';

/// A package-backed preview, never connected to IndexedDB or a write API.
class CloudGraphPreviewRepository implements GraphRepository {
  CloudGraphPreviewRepository(this.package);
  final PortalGraphPackage package;

  @override
  Future<List<SavedGraphSummary>> listGraphs() async =>
      [summaryForDocument(package.document)];
  @override
  Future<GraphDocument?> loadGraph(String id) async =>
      id == package.document.id ? package.document : null;
  @override
  Future<Uint8List?> loadBlob(String key) async => package.blobs[key];
  @override
  Future<void> saveGraph(GraphDocument document, {
    Map<String, Uint8List> blobs = const {},
    Set<String> deletedBlobKeys = const {},
  }) async => throw UnsupportedError('Cloud history is read only.');
  @override
  Future<void> deleteGraph(String id) async =>
      throw UnsupportedError('Cloud history is read only.');
}
