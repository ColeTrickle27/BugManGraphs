import 'dart:convert';
import 'package:http/http.dart' as http;
import 'graph_draft_http_service.dart';
import 'graph_draft_service.dart';

/// Existing credentials go only to the same-origin relay. No token is readable
/// or stored in Dart: the backend's signed session remains a host-only cookie.
class GraphDraftAuthentication {
  GraphDraftAuthentication(
      {required this.client,
      required this.origin,
      required Uri currentOrigin}) {
    if (origin.origin != currentOrigin.origin ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        !(origin.scheme == 'https' ||
            (origin.scheme == 'http' &&
                ['localhost', '127.0.0.1'].contains(origin.host)))) {
      throw const FormatException(
          'Same-origin account authentication is required.');
    }
  }
  final http.Client client;
  final Uri origin;
  Future<Map<String, Object?>> _request(String method, String path,
      [Map<String, String>? body]) async {
    final request = http.Request(method, Uri.parse('${origin.origin}$path'))
      ..followRedirects = false;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await client.send(request));
    if (response.statusCode != 200) {
      throw GraphDraftException(response.statusCode,
          'Sign-in could not complete. Your stored graph recovery was retained.');
    }
    try {
      return (jsonDecode(response.body) as Map).cast<String, Object?>();
    } catch (_) {
      throw const GraphDraftException(
          503, 'The account service returned an unexpected response.');
    }
  }

  Future<HttpGraphDraftService> connect({String? expectedAccountId}) async {
    final payload = await _request('GET', '/api/me');
    final user = payload['user'];
    if (user is! Map) {
      throw const GraphDraftException(401, 'Sign in to access your graphs.');
    }
    final name =
        (user['name'] ?? user['username'] ?? 'Your account').toString();
    return HttpGraphDraftService.connect(
        client: client,
        origin: origin,
        currentOrigin: origin,
        expectedAccountId: expectedAccountId,
        displayName: name);
  }

  Future<HttpGraphDraftService> login(String username, String password) async {
    await _request(
        'POST', '/api/login', {'username': username, 'password': password});
    return connect();
  }

  Future<void> logout() async {
    await _request('POST', '/api/logout', {});
  }

  void close() => client.close();
}
