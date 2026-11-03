import 'dart:convert';
import 'package:http/browser_client.dart';

/// Uses OpsBrain's existing same-origin employee session. Standalone Graphs
/// does not have permission to read /api/me across origins.
Future<String?> loadAuthenticatedName() async {
  if (!Uri.base.path.startsWith('/bugman-graphs/')) return null;
  final client = BrowserClient()..withCredentials = true;
  try {
    final response = await client.get(Uri.base.resolve('/api/me'));
    if (response.statusCode != 200) return null;
    final payload = jsonDecode(response.body);
    final user = payload is Map ? payload['user'] : null;
    if (user is! Map) return null;
    final name = (user['name'] ?? user['username'] ?? '').toString().trim();
    return name.isEmpty ? null : name;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}
