import 'dart:typed_data';

import '../models/graph_document.dart';

class PortalAuthenticationException implements Exception {
  const PortalAuthenticationException(this.signInUrl);

  final String signInUrl;

  @override
  String toString() => 'Sign in to Holloman Ops Brain to continue.';
}

class PortalGraphPackage {
  const PortalGraphPackage(
      {required this.document, required this.blobs, required this.name});

  final GraphDocument document;
  final Map<String, Uint8List> blobs;
  final String name;
}

class PortalUploadResult {
  const PortalUploadResult({required this.key, required this.message});

  final String key;
  final String message;
}

abstract class BugManPortalService {
  bool get isAvailable;

  Future<PortalUploadResult> saveGraph(
    GraphDocument document,
    Map<String, Uint8List> blobs, {
    String? existingKey,
  });

  // Note: a standalone uploadGraph() (POST /api/bugman-graphs/upload) used
  // to live here. It was never actually called anywhere in the app -- the
  // real duplicate-Upload-action problem (item 8 of the production pass)
  // was graph_canvas_screen.dart's `_uploadDocument()` calling the same
  // `saveGraph()` method as the Save action, not this method -- so it has
  // been removed as genuine dead code rather than kept around unused.

  /// Saves a rendered PDF/PNG export of a graph into the customer's BugMan
  /// Graphs folder in Holloman Ops Brain (item 8 of the production pass).
  /// This is a read-only rendered artifact, not the editable `.bgraph`
  /// document -- it goes through the same generic customer-upload route
  /// the rest of Ops Brain already uses (see `uploadFile()` in
  /// functions/api/[[path]].js) rather than a graph-specific endpoint.
  Future<PortalUploadResult> uploadGraphExport({
    required GraphCustomerInfo customer,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    required DateTime graphCreatedAt,
  });

  Future<PortalGraphPackage> loadGraph(String key);

  /// Builds the Sales Brain report handoff URL for a saved graph (item 14
  /// of the production pass), or null when Sales Brain isn't reachable
  /// from this session (e.g. BugMan Graphs opened standalone, not through
  /// Holloman Ops Brain). Sales Brain resolves `billTo`/`location` itself
  /// against Ops Brain's own customer records and only uses `graphKey` to
  /// preselect the saved graph for human review -- it never auto-finalizes
  /// anything from this handoff.
  String? buildSalesBrainReportUrl({
    required String billToNumber,
    required String locationNumber,
    required String graphKey,
  });

  /// Builds a direct link to the customer's BugMan Graphs folder in
  /// Holloman Ops Brain, or null when the required customer identity is
  /// unavailable in this session.
  String? buildCustomerFolderUrl({
    required String billToNumber,
    required String locationNumber,
  });
}
