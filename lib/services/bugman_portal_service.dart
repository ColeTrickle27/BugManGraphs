import 'dart:convert';
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
      {required this.document,
      required this.blobs,
      required this.name,
      this.finalization});

  factory PortalGraphPackage.fromResponse(Map<String, dynamic> payload) {
    final graph = payload['graph'];
    if (graph is! Map || graph['document'] is! Map) {
      throw const FormatException('This BugMan graph could not be opened.');
    }
    final documentJson = (graph['document'] as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final finalization =
        PortalGraphFinalization.verify(payload, graph, documentJson);
    final blobs = <String, Uint8List>{};
    final encodedBlobs = graph['blobs'];
    if (encodedBlobs is Map) {
      for (final entry in encodedBlobs.entries) {
        if (entry.value is String) {
          blobs[entry.key.toString()] = base64Decode(entry.value as String);
        }
      }
    }
    return PortalGraphPackage(
      document: GraphDocument.fromJson(documentJson),
      blobs: blobs,
      name: payload['name']?.toString() ?? 'BugMan Graph',
      finalization: finalization,
    );
  }

  final GraphDocument document;
  final Map<String, Uint8List> blobs;
  final String name;
  final PortalGraphFinalization? finalization;
  bool get isFinalized => finalization != null;
}

class PortalFinalizationException implements Exception {
  const PortalFinalizationException();
  @override
  String toString() =>
      'Finalized graph verification failed. The saved file was not changed. Reload from OpsBrain.';
}

/// A server-confirmed lock whose immutable receipt is not yet verified.
/// No document is returned or persisted until verification completes.
class PortalFinalizationPendingException extends PortalFinalizationException {
  const PortalFinalizationPendingException(this.etag, this.claim);
  final String etag;
  final PortalGraphFinalization claim;
  @override
  String toString() =>
      'Finalization receipt is pending. This graph remains read-only.';
}

abstract interface class PortalFinalizationRecovery {
  Future<PortalGraphPackage> retryFinalization(String key);
}

/// Retains the authenticated server's verified immutable-package identity.
/// This validates matching claims; receipt cryptography remains server-side.
class PortalGraphFinalization {
  const PortalGraphFinalization._(this.finalizedAt, this.finalizedBy,
      this.finalizedRole, this.snapshotSha256);
  final String finalizedAt;
  final String finalizedBy;
  final String finalizedRole;
  final String snapshotSha256;

  static PortalGraphFinalization? verify(Map payload, Map graph, Map document) {
    final metadata = document['metadata'];
    final markers = [
      payload['finalization'],
      graph['_opsFinalization'],
      document['_opsFinalization'],
      if (metadata is Map) metadata['_opsFinalization']
    ];
    if (markers.every((marker) => marker == null)) return null;
    final authoritative = markers[0], embedded = markers[1];
    if (authoritative is! Map || embedded is! Map) {
      throw const PortalFinalizationException();
    }
    if (authoritative['receiptVerified'] == false &&
        (embedded['receiptVerified'] == null ||
            embedded['receiptVerified'] == false) &&
        markers.skip(2).whereType<Map>().every((m) =>
            (m['receiptVerified'] == null || m['receiptVerified'] == false))) {
      // Validate every other lock claim with the exact verified validator.
      final checked = [
        for (final marker in markers)
          if (marker is Map) {...marker, 'receiptVerified': true} else marker
      ];
      final claim = verify({
        'finalization': checked[0]
      }, {
        '_opsFinalization': checked[1]
      }, {
        '_opsFinalization': checked[2],
        if (metadata is Map) 'metadata': {'_opsFinalization': checked[3]}
      });
      final etag = payload['etag'];
      if (etag is! String || etag.trim().isEmpty) {
        throw const PortalFinalizationException();
      }
      throw PortalFinalizationPendingException(etag, claim!);
    }
    const fields = [
      'finalizedAt',
      'finalizedBy',
      'finalizedRole',
      'snapshotSha256'
    ];
    for (final marker in markers.where((value) => value != null)) {
      if (marker is! Map ||
          marker['locked'] != true ||
          marker['receiptVerified'] != true ||
          fields.any((field) =>
              marker[field] is! String ||
              (marker[field] as String).isEmpty ||
              marker[field] != authoritative[field])) {
        throw const PortalFinalizationException();
      }
    }
    final at = authoritative['finalizedAt'] as String;
    final digest = authoritative['snapshotSha256'] as String;
    if (DateTime.tryParse(at) == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const PortalFinalizationException();
    }
    return PortalGraphFinalization._(at, authoritative['finalizedBy'] as String,
        authoritative['finalizedRole'] as String, digest);
  }
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

/// Performs only conditional receipt repair; never saves graph content.
Future<PortalGraphPackage> recoverPendingGraphFinalization({
  required Future<PortalGraphPackage> Function() load,
  required Future<void> Function(String etag) repair,
}) async {
  try {
    final current = await load();
    if (!current.isFinalized) throw const PortalFinalizationException();
    return current;
  } on PortalFinalizationPendingException catch (pending) {
    await repair(pending.etag);
    final verified = await load();
    final claim = verified.finalization;
    if (claim == null ||
        claim.snapshotSha256 != pending.claim.snapshotSha256 ||
        claim.finalizedAt != pending.claim.finalizedAt ||
        claim.finalizedBy != pending.claim.finalizedBy ||
        claim.finalizedRole != pending.claim.finalizedRole) {
      throw const PortalFinalizationException();
    }
    return verified;
  }
}
