import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';
import 'package:http_parser/http_parser.dart';

import '../models/graph_document.dart';
import 'bugman_portal_service.dart';

BugManPortalService createPortalService() => HttpBugManPortalService();

class HttpBugManPortalService implements BugManPortalService {
  static const _opsBrainOrigin = 'https://ops.holloman-ext.com';
  static const _cloudflareHosts = {
    'graphs.holloman-ext.com',
    'bugman-graphs.pages.dev',
  };

  late final BrowserClient _client = BrowserClient()..withCredentials = true;

  String get _apiOrigin => Uri.base.path.startsWith('/bugman-graphs/')
      ? Uri.base.origin
      : _opsBrainOrigin;

  @override
  bool get isAvailable =>
      Uri.base.path.startsWith('/bugman-graphs/') ||
      _cloudflareHosts.contains(Uri.base.host);

  @override
  Future<PortalUploadResult> saveGraph(
    GraphDocument document,
    Map<String, Uint8List> blobs, {
    String? existingKey,
  }) =>
      _sendGraph(
        '/api/bugman-graphs/save',
        document,
        blobs,
        existingKey: existingKey,
      );

  @override
  Future<PortalUploadResult> uploadGraphExport({
    required GraphCustomerInfo customer,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    required DateTime graphCreatedAt,
  }) async {
    final uri = Uri.parse('$_apiOrigin/api/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['scope'] = 'customer'
      ..fields['folder'] = 'bugman-graphs'
      ..fields['billToNumber'] = customer.pestPacBillToNumber
      ..fields['locationNumber'] = customer.pestPacLocationNumber
      // Only used as a fallback by the server if the customer's location
      // folder doesn't already exist yet -- normal case is that it does,
      // since a graph can't exist for a customer without one.
      ..fields['billToName'] = customer.name
      ..fields['locationName'] = customer.serviceAddress
      // Item 15: enriches the generic upload's R2 metadata with the same
      // canonical Bill-To/Location/graph fields the .bgraph save path
      // already writes via bugManGraphMetadata() server-side, restricted
      // to the whitelist the server accepts (see uploadFile() in
      // functions/api/[[path]].js).
      ..fields['extraMetadata'] = jsonEncode({
        'customerName': customer.name,
        'serviceAddress': customer.serviceAddress,
        'graphType': customer.serviceType,
        'graphedBy': customer.createdBy,
        'originalGraphCreatedAt': graphCreatedAt.toIso8601String(),
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          'files',
          bytes,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ),
      );
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    final payload = _decodeResponse(response);
    return PortalUploadResult(
      key: payload['key']?.toString() ?? '',
      message: payload['message']?.toString() ?? 'File uploaded.',
    );
  }

  Future<PortalUploadResult> _sendGraph(
    String path,
    GraphDocument document,
    Map<String, Uint8List> blobs, {
    String? existingKey,
  }) async {
    final uri = Uri.parse('$_apiOrigin$path').replace(
      queryParameters: existingKey == null ? null : {'key': existingKey},
    );
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'type': 'bugman-graph',
        'version': 1,
        'document': document.toJson(),
        'blobs': {
          for (final entry in blobs.entries)
            entry.key: base64Encode(entry.value),
        },
      }),
    );
    final payload = _decodeResponse(response);
    return PortalUploadResult(
      key: payload['key']?.toString() ?? '',
      message: payload['message']?.toString() ?? 'Graph uploaded.',
    );
  }

  @override
  Future<PortalGraphPackage> loadGraph(String key) async {
    final uri = Uri.parse('$_apiOrigin/api/bugman-graphs/load')
        .replace(queryParameters: {'key': key});
    final response = await _client.get(uri);
    final payload = _decodeResponse(response);
    final graph = payload['graph'];
    if (graph is! Map || graph['document'] is! Map) {
      throw const FormatException('This BugMan graph could not be opened.');
    }
    final documentJson = (graph['document'] as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
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
    );
  }

  @override
  String? buildSalesBrainReportUrl({
    required String billToNumber,
    required String locationNumber,
    required String graphKey,
  }) {
    if (!isAvailable) return null;
    final salesUrl = Uri.base.path.startsWith('/bugman-graphs/')
        ? '$_apiOrigin/sales-brain/'
        : 'https://sales.holloman-ext.com/';
    final uri = Uri.parse(salesUrl).replace(
      queryParameters: {
        'billTo': billToNumber,
        'location': locationNumber,
        'graphKey': graphKey,
      },
    );
    return uri.toString();
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw PortalAuthenticationException('$_apiOrigin/');
    }
    final decoded = jsonDecode(response.body);
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : decoded is Map
            ? decoded.map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        payload['error']?.toString() ??
            'Holloman Ops Brain request failed (${response.statusCode}).',
      );
    }
    return payload;
  }
}
