import 'dart:convert';
import 'package:http/http.dart' as http;

class OpsGraphUser {
  const OpsGraphUser({required this.username, required this.name});
  final String username, name;
}

class OpsGraphUsers {
  const OpsGraphUsers({this.current, this.users = const []});
  final OpsGraphUser? current;
  final List<OpsGraphUser> users;
}

abstract class OpsUserService {
  Future<OpsGraphUsers> load();
}

class UnavailableOpsUserService implements OpsUserService {
  @override
  Future<OpsGraphUsers> load() async => const OpsGraphUsers();
}

/// Existing /me and admin-only /users endpoints. Never expands directory access.
class HttpOpsUserService implements OpsUserService {
  HttpOpsUserService(this.client, this.origin);
  final http.Client client;
  final String origin;
  OpsGraphUser? _parse(dynamic value) {
    if (value is! Map || value['active'] == false) return null;
    final username = '${value['username'] ?? ''}'.trim();
    final name = '${value['name'] ?? value['displayName'] ?? username}'.trim();
    return username.isEmpty || name.isEmpty
        ? null
        : OpsGraphUser(username: username, name: name);
  }

  @override
  Future<OpsGraphUsers> load() async {
    OpsGraphUser? current;
    final users = <OpsGraphUser>[];
    try {
      final response = await client.get(Uri.parse('$origin/api/me'));
      if (response.statusCode != 200) return const OpsGraphUsers();
      final payload = jsonDecode(response.body);
      final raw = payload is Map ? payload['user'] : null;
      current = _parse(raw);
      if (current != null) users.add(current);
      if (raw is Map && raw['role'] == 'admin') {
        final directory = await client.get(Uri.parse('$origin/api/users'));
        if (directory.statusCode == 200) {
          final data = jsonDecode(directory.body);
          if (data is Map && data['users'] is List) {
            for (final item in data['users']) {
              final user = _parse(item);
              if (user != null &&
                  !users.any((u) => u.username == user.username)) {
                users.add(user);
              }
            }
          }
        }
      }
    } catch (_) {/* Preserve current identity if directory lookup fails. */}
    return OpsGraphUsers(current: current, users: users);
  }
}
