import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/cloud_graph_draft.dart';
import 'graph_draft_service.dart';

class HttpGraphDraftService implements GraphDraftService {
  HttpGraphDraftService(
      {required http.Client client,
      required this.origin,
      required Uri currentOrigin,
      required this.account})
      : _client = client {
    if (origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        !origin.hasAuthority ||
        !currentOrigin.hasAuthority ||
        origin.origin != currentOrigin.origin ||
        !(origin.scheme == 'https' ||
            (origin.scheme == 'http' &&
                ['localhost', '127.0.0.1', '::1'].contains(origin.host)))) {
      throw const FormatException('A same-origin graph API is required');
    }
  }
  final http.Client _client;
  final Uri origin;
  final GraphDraftAccount account;
  static const maxRequestBytes = 25 * 1024 * 1024 - 64 * 1024;
  void _active() {
    if (!account.active) {
      throw const GraphDraftException(401,
          'Sign in again to resume cloud sync. Your local recovery copy is retained.');
    }
  }

  Future<Map<String, Object?>> _request(String method, String path,
      {Map<String, String>? query,
      Map<String, Object?>? body,
      Set<int> successes = const {200}}) async {
    _active();
    final uri =
        Uri.parse('${origin.origin}$path').replace(queryParameters: query);
    final request = http.Request(method, uri)..followRedirects = false;
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      if (bytes.length > maxRequestBytes) {
        throw const GraphDraftException(413,
            'This complete graph is too large for cloud sync. No photos were removed.');
      }
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = bytes;
    }
    final response =
        await http.Response.fromStream(await _client.send(request));
    _active();
    Map<String, Object?> data;
    try {
      data = (jsonDecode(response.body) as Map).cast<String, Object?>();
    } catch (_) {
      throw const GraphDraftException(503,
          'Cloud sync is unavailable. Your local recovery copy is retained.');
    }
    if (!successes.contains(response.statusCode)) {
      throw GraphDraftException(
          response.statusCode >= 200 && response.statusCode < 300
              ? 503
              : response.statusCode,
          data['error'] as String? ?? 'Cloud sync could not finish.');
    }
    return data;
  }

  @override
  Future<GraphDraftAuthors> authors() async => GraphDraftAuthors.fromJson(
      await _request('GET', '/api/graph-drafts/authors'));
  @override
  Future<GraphDraftPage> list({int limit = 100, String? cursor}) async {
    if (limit < 1 || limit > 300) throw ArgumentError.value(limit, 'limit');
    final data = await _request('GET', '/api/graph-drafts',
        query: {'limit': '$limit', if (cursor != null) 'cursor': cursor});
    if (data['drafts'] is! List ||
        (data['nextCursor'] != null && data['nextCursor'] is! String)) {
      throw const FormatException('Invalid graph list');
    }
    return GraphDraftPage(
        (data['drafts'] as List)
            .map((s) =>
                GraphDraftSummary.fromJson((s as Map).cast<String, Object?>()))
            .toList(),
        data['nextCursor'] as String?);
  }

  @override
  Future<RemoteGraphDraft> get(String id) async {
    validateDraftId(id);
    final data = await _request('GET', '/api/graph-drafts/$id');
    final package = GraphDraftPackage.fromJson(
        (data['package'] as Map).cast<String, Object?>());
    if (data['id'] != id || package.id != id) {
      throw const FormatException('Graph identity did not match');
    }
    return RemoteGraphDraft(
        package,
        draftRevision(data['revision']),
        GraphDraftAuthor.fromJson(
            (data['author'] as Map).cast<String, Object?>()));
  }

  @override
  Future<GraphDraftWriteResult> save(GraphDraftPackage package,
      {required String? expectedRevision, String? authorId}) async {
    if (expectedRevision != null) draftRevision(expectedRevision);
    final data =
        await _request('POST', '/api/graph-drafts/${package.id}', body: {
      'package': package.toJson(),
      'expectedRevision': expectedRevision,
      if (authorId != null) 'authorId': authorId
    }, successes: const {
      200,
      201
    });
    if (data['id'] != package.id) {
      throw const FormatException('Graph identity did not match');
    }
    return GraphDraftWriteResult(
        package.id,
        draftRevision(data['revision']),
        DateTime.parse(draftString(data['updatedAt'], 'updated time')),
        GraphDraftAuthor.fromJson(
            (data['author'] as Map).cast<String, Object?>()));
  }
}
