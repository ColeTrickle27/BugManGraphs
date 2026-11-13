import 'dart:async';

import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/services/trace_imagery_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const corners = [
  GeoPoint(latitude: 35, longitude: -78),
  GeoPoint(latitude: 35, longitude: -77.999),
  GeoPoint(latitude: 34.999, longitude: -78),
];
const canvasCorners = [
  GraphPoint(x: 0, y: 0),
  GraphPoint(x: 100, y: 0),
  GraphPoint(x: 0, y: 100)
];

void main() {
  test('a stalled provider has one overall deadline', () async {
    final pending = Completer<http.Response>();
    var requests = 0;
    final service = TraceImageryService(
      client: MockClient((_) {
        requests++;
        return pending.future;
      }),
      transferTimeout: const Duration(milliseconds: 30),
    );
    await expectLater(
        service.capture(corners: corners, canvasCorners: canvasCorners),
        throwsA(isA<TimeoutException>()));
    expect(requests, lessThanOrEqualTo(4));
    pending.complete(http.Response('unavailable', 503));
  });

  test('cancellation stops a pending capture without waiting for a provider',
      () async {
    final pending = Completer<http.Response>();
    final operation = TraceImageryCancellation();
    final service =
        TraceImageryService(client: MockClient((_) => pending.future));
    final result = service.capture(
        corners: corners,
        canvasCorners: canvasCorners,
        cancellation: operation);
    final checked =
        expectLater(result, throwsA(isA<TraceImageryCancelledException>()));
    operation.cancel();
    await checked;
    pending.complete(http.Response('unavailable', 503));
  });

  test('a failed tile does not wait for unrelated stalled tiles', () async {
    final pending = Completer<http.Response>();
    var requests = 0;
    final service = TraceImageryService(client: MockClient((_) {
      return requests++ == 0
          ? Future.value(http.Response('unavailable', 503))
          : pending.future;
    }));
    await expectLater(
        service
            .capture(corners: corners, canvasCorners: canvasCorners)
            .timeout(const Duration(seconds: 1)),
        throwsStateError);
    expect(requests, lessThanOrEqualTo(4));
    pending.complete(http.Response('unavailable', 503));
  });
}
