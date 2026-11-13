import 'package:flutter/widgets.dart';

import '../models/trace_geometry.dart';

class TraceMapConfigurationException implements Exception {
  const TraceMapConfigurationException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class TraceMapProvider {
  Future<void> initialize();

  Widget buildMap({
    required GeoPoint center,
    required GeoPoint selectedAddress,
    required List<GeoPoint> points,
    List<List<GeoPoint>> referencePolygons = const [],
    required ValueChanged<GeoPoint> onMapTap,
    required void Function(int index, GeoPoint point) onVertexMoved,
  });
}
