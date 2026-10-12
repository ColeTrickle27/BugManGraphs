import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_authentication.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store.dart';
import 'package:bugman_graphs/screens/cloud_drafts/graph_draft_session_screen.dart';
import 'graph_draft_sync_test.dart' show ownerA;

void main() {
  test(
      'existing credentials are used only for login; server context pins account, logout is exact',
      () async {
    final calls = <http.Request>[];
    final auth = GraphDraftAuthentication(
        origin: Uri.parse('https://fixture.invalid'),
        currentOrigin: Uri.parse('https://fixture.invalid'),
        client: MockClient((r) async {
          calls.add(r);
          if (r.url.path == '/api/graph-drafts/context') {
            return http.Response(jsonEncode({'accountId': ownerA}), 200);
          }
          return http.Response(
              jsonEncode({
                'user': {'name': 'Synthetic account'}
              }),
              200);
        }));
    final service = await auth.login('synthetic', 'fixture-only-password');
    expect(service.account.id, ownerA);
    expect(service.account.displayName, 'Synthetic account');
    expect(jsonDecode(calls.first.body),
        {'username': 'synthetic', 'password': 'fixture-only-password'});
    expect(
        calls.skip(1).every((r) => !r.body.contains('fixture-only-password')),
        isTrue);
    await auth.logout();
    expect(calls.last.url.path, '/api/logout');
    expect(calls.last.method, 'POST');
    expect(calls.every((r) => r.followRedirects == false), isTrue);
    auth.close();
  });
  test('authentication rejects cross-origin and redirect responses', () async {
    final client = MockClient((_) async =>
        http.Response('', 302, headers: {'Location': 'https://evil.invalid'}));
    expect(
        () => GraphDraftAuthentication(
            client: client,
            origin: Uri.parse('https://evil.invalid'),
            currentOrigin: Uri.parse('https://fixture.invalid')),
        throwsFormatException);
    final auth = GraphDraftAuthentication(
        client: client,
        origin: Uri.parse('https://fixture.invalid'),
        currentOrigin: Uri.parse('https://fixture.invalid'));
    await expectLater(auth.connect(), throwsA(isA<Exception>()));
    auth.close();
  });
  testWidgets(
      'sign-in screen uses server context and clears password after submission',
      (tester) async {
    var authenticated = false;
    final auth = GraphDraftAuthentication(
        origin: Uri.parse('https://fixture.invalid'),
        currentOrigin: Uri.parse('https://fixture.invalid'),
        client: MockClient((r) async {
          if (r.url.path == '/api/login') {
            authenticated = true;
            return http.Response('{"user":{"name":"Synthetic"}}', 200);
          }
          if (!authenticated) return http.Response('{"error":"Sign in"}', 401);
          if (r.url.path.endsWith('/context')) {
            return http.Response(jsonEncode({'accountId': ownerA}), 200);
          }
          if (r.url.path.endsWith('/authors')) {
            return http.Response(
                '{"defaultAuthorId":"synthetic-author","authors":[{"id":"synthetic-author","name":"Synthetic"}]}',
                200);
          }
          if (r.url.path == '/api/graph-drafts') {
            return http.Response('{"drafts":[],"nextCursor":null}', 200);
          }
          return http.Response('{"user":{"name":"Synthetic"}}', 200);
        }));
    await tester.pumpWidget(MaterialApp(
        home: GraphDraftSessionScreen(
            authentication: auth, store: MemoryGraphDraftStore())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'synthetic');
    await tester.enterText(
        find.byType(TextField).last, 'fixture-only-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('My Graphs'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    auth.close();
  });
}
