import 'dart:typed_data';

import '../models/graph_document.dart';
import 'bugman_portal_service.dart';

BugManPortalService createPortalService() => UnavailableBugManPortalService();

class UnavailableBugManPortalService implements BugManPortalService {
  @override
  bool get isAvailable => false;

  @override
  Future<PortalGraphPackage> loadGraph(String key) =>
      Future.error(UnsupportedError('Holloman Ops Brain is unavailable.'));

  @override
  Future<PortalUploadResult> saveGraph(
    GraphDocument document,
    Map<String, Uint8List> blobs, {
    String? existingKey,
  }) =>
      Future.error(UnsupportedError('Holloman Ops Brain is unavailable.'));

  @override
  Future<PortalUploadResult> uploadGraphExport({
    required GraphCustomerInfo customer,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    required DateTime graphCreatedAt,
  }) =>
      Future.error(UnsupportedError('Holloman Ops Brain is unavailable.'));

  @override
  String? buildSalesBrainReportUrl({
    required String billToNumber,
    required String locationNumber,
    required String graphKey,
  }) =>
      null;

  @override
  String? buildCustomerFolderUrl({
    required String billToNumber,
    required String locationNumber,
  }) =>
      null;
}
