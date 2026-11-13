import 'dart:convert';

import 'package:bugman_graphs/services/address_suggestion_service.dart';
import 'package:bugman_graphs/services/address_suggestion_service_stub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../tool/satellite_preview/address_service.dart';

void main() {
  test('preview search uses its own endpoint and preserves approximate quality',
      () async {
    var requests = 0;
    final service = PreviewAddressService(
        origin: Uri.parse('https://preview.example'),
        client: MockClient((request) async {
          requests++;
          expect(request.url.host, 'preview.example');
          expect(request.url.path, '/api/preview/address-search');
          expect(request.url.queryParameters['address'],
              '363 Carroll Store Rd, Autryville, NC');
          return http.Response(
              jsonEncode({
                'matches': [
                  {
                    'address': '363 CARROLL STORE RD, AUTRYVILLE, NC, 28318',
                    'latitude': 35.0924,
                    'longitude': -78.6196
                  }
                ]
              }),
              200);
        }));
    addTearDown(service.dispose);
    final suggestions = await service.suggest(
        '363 Carroll Store Rd, Autryville, NC',
        sessionToken: 'preview');
    final selection =
        await service.select(suggestions.single, sessionToken: 'preview');
    expect(selection.coordinate!.latitude, 35.0924);
    expect(selection.quality.requiresReview, isTrue);
    expect(selection.quality.isPropertyLevel, isFalse);
    expect(requests, 1);
  });
  test('preview search surfaces service errors', () async {
    final service = PreviewAddressService(
        origin: Uri.parse('https://preview.example'),
        client: MockClient(
            (_) async => http.Response('{"error":"Try again"}', 503)));
    addTearDown(service.dispose);
    await expectLater(
        service.suggest('A North Carolina address', sessionToken: 'preview'),
        throwsA(isA<AddressSuggestionServiceException>()
            .having((e) => e.message, 'message', 'Try again')));
  });
  test('stale selections require another search', () async {
    final service = PreviewAddressService(
        client: MockClient((_) async => http.Response('{"matches":[]}', 200)));
    addTearDown(service.dispose);
    await expectLater(
        service.select(
            const AddressSuggestion(
                id: 'missing', address: 'Old', primaryText: 'Old'),
            sessionToken: 'preview'),
        throwsA(isA<AddressSuggestionServiceException>()));
  });
}
