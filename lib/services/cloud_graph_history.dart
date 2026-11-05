import 'dart:convert';

import 'package:http/http.dart' as http;

import 'bugman_portal_service.dart';

class CloudGraphHistoryEntry {
  const CloudGraphHistoryEntry({
    required this.key,
    required this.name,
    this.customerName = '',
    this.serviceAddress = '',
    this.updatedAt,
    this.finalized = false,
  });
  final String key;
  final String name;
  final String customerName;
  final String serviceAddress;
  final DateTime? updatedAt;
  final bool finalized;
}

class CloudGraphHistoryPage {
  const CloudGraphHistoryPage(this.graphs, this.nextCursor);
  final List<CloudGraphHistoryEntry> graphs;
  final String? nextCursor;
}

abstract class CloudGraphHistoryService {
  bool get isAvailable;
  Future<CloudGraphHistoryPage> list({String? cursor});
  void close();
}

class CloudGraphHistoryAccessException implements Exception {}

/// Uses the existing shared Customer Files authorization, never account-draft
/// ownership. The browser factory supplies only the approved OpsBrain origin.
class HttpCloudGraphHistoryService implements CloudGraphHistoryService {
  HttpCloudGraphHistoryService({required this.origin, required this.client});
  final Uri origin;
  final http.Client client;
  @override
  bool get isAvailable => true;

  @override
  Future<CloudGraphHistoryPage> list({String? cursor}) async {
    final response = await client.get(
      origin.replace(
        path: '/api/bugman-graphs/recent',
        queryParameters: cursor == null ? null : {'cursor': cursor},
      ),
    );
    if (response.statusCode == 401) {
      throw PortalAuthenticationException(origin.toString());
    }
    if (response.statusCode == 403) throw CloudGraphHistoryAccessException();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const FormatException('Cloud graph history is unavailable.');
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map ||
        payload['graphs'] is! List ||
        payload['truncated'] is! bool) {
      throw const FormatException('Invalid cloud history response.');
    }
    final next = payload['nextCursor'];
    final truncated = payload['truncated'] == true;
    if (truncated && (next is! String || next.isEmpty || next == cursor)) {
      throw const FormatException('Invalid cloud history pagination.');
    }
    final graphs = <CloudGraphHistoryEntry>[];
    for (final row in payload['graphs'] as List) {
      if (row is! Map ||
          row['key'] is! String ||
          (row['key'] as String).isEmpty) {
        throw const FormatException('Invalid cloud history entry.');
      }
      final finalization = row['finalization'];
      graphs.add(
        CloudGraphHistoryEntry(
          key: row['key'] as String,
          name: row['name']?.toString() ?? 'Saved graph',
          customerName: row['customerName']?.toString() ?? '',
          serviceAddress: row['serviceAddress']?.toString() ?? '',
          updatedAt: DateTime.tryParse(row['updatedAt']?.toString() ?? ''),
          finalized: finalization is Map && finalization['locked'] == true,
        ),
      );
    }
    return CloudGraphHistoryPage(graphs, truncated ? next as String : null);
  }

  @override
  void close() => client.close();
}
