import 'dart:ui';

import 'graph_point.dart';

/// How a graph's real-world measurements were established.
enum MeasurementSource {
  legacyCanvasScale,
  mapGeodesic,
  calibratedImage,
}

/// Communicates whether measurements are suitable for downstream calculations.
enum MeasurementAccuracyStatus {
  uncalibrated,
  estimated,
  verified,
  outsideTolerance,
  modifiedSinceVerification,
}

class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  factory GeoPoint.fromJson(Map<String, Object?> json) => GeoPoint(
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      );

  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };
}

/// Relates canvas coordinates to real-world metres.
///
/// Legacy graphs retain the original 24 px/ft behavior, while calibrated
/// images can store an explicit scale. Map traces do not use this scale for
/// measurement; their latitude/longitude vertices remain authoritative.
class MeasurementCalibration {
  const MeasurementCalibration({
    required this.source,
    required this.status,
    this.metersPerCanvasUnit,
    this.residualErrorMeters,
    this.verifiedAt,
    this.note = '',
  });

  factory MeasurementCalibration.legacy() => const MeasurementCalibration(
        source: MeasurementSource.legacyCanvasScale,
        status: MeasurementAccuracyStatus.estimated,
        metersPerCanvasUnit: 0.3048 / 24,
        note: 'Legacy 24 px/ft canvas scale',
      );

  factory MeasurementCalibration.fromJson(Map<String, Object?> json) {
    T readEnum<T extends Enum>(
      Iterable<T> values,
      Object? value,
      T fallback,
    ) =>
        values.firstWhere(
          (item) => item.name == value,
          orElse: () => fallback,
        );

    return MeasurementCalibration(
      source: readEnum(
        MeasurementSource.values,
        json['source'],
        MeasurementSource.legacyCanvasScale,
      ),
      status: readEnum(
        MeasurementAccuracyStatus.values,
        json['status'],
        MeasurementAccuracyStatus.estimated,
      ),
      metersPerCanvasUnit: (json['metersPerCanvasUnit'] as num?)?.toDouble(),
      residualErrorMeters: (json['residualErrorMeters'] as num?)?.toDouble(),
      verifiedAt: json['verifiedAt'] is String
          ? DateTime.tryParse(json['verifiedAt']! as String)
          : null,
      note: json['note']?.toString() ?? '',
    );
  }

  final MeasurementSource source;
  final MeasurementAccuracyStatus status;
  final double? metersPerCanvasUnit;
  final double? residualErrorMeters;
  final DateTime? verifiedAt;
  final String note;

  bool get isUsableForBusinessCalculations =>
      status == MeasurementAccuracyStatus.verified;

  Map<String, Object?> toJson() => {
        'source': source.name,
        'status': status.name,
        'metersPerCanvasUnit': metersPerCanvasUnit,
        'residualErrorMeters': residualErrorMeters,
        'verifiedAt': verifiedAt?.toIso8601String(),
        'note': note,
      };
}

/// A traced map feature stores both geographic and canvas coordinates.
/// Geographic coordinates own measurements; canvas coordinates only own
/// presentation and hit testing.
class TraceGeometry {
  const TraceGeometry({
    required this.id,
    required this.label,
    required this.geoPoints,
    required this.canvasPoints,
    this.address = '',
    this.closed = true,
    this.metersPerCanvasUnit,
    this.exclusions = const [],
    this.imagery,
  });

  factory TraceGeometry.fromJson(Map<String, Object?> json) => TraceGeometry(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        geoPoints: (json['geoPoints'] as List? ?? const <Object?>[])
            .whereType<Map>()
            .map((value) => GeoPoint.fromJson(
                  value.map((key, item) => MapEntry(key.toString(), item)),
                ))
            .toList(),
        canvasPoints: (json['canvasPoints'] as List? ?? const <Object?>[])
            .whereType<Map>()
            .map((value) => GraphPoint(
                  x: (value['x'] as num?)?.toDouble() ?? 0,
                  y: (value['y'] as num?)?.toDouble() ?? 0,
                ))
            .toList(),
        exclusions: (json['exclusions'] as List? ?? const [])
            .whereType<Map>()
            .map((value) => TraceGeometry.fromJson(
                value.map((key, item) => MapEntry(key.toString(), item))))
            .toList(),
        imagery: json['imagery'] is Map
            ? TraceImagery.fromJson(
                Map<String, Object?>.from(json['imagery']! as Map))
            : null,
        closed: json['closed'] as bool? ?? true,
        metersPerCanvasUnit: (json['metersPerCanvasUnit'] as num?)?.toDouble(),
      );

  final String id;
  final String label;
  final String address;
  final List<GeoPoint> geoPoints;
  final List<GraphPoint> canvasPoints;
  final List<TraceGeometry> exclusions;
  final TraceImagery? imagery;
  final bool closed;
  final double? metersPerCanvasUnit;

  TraceGeometry copyWith({
    String? id,
    String? label,
    String? address,
    List<GeoPoint>? geoPoints,
    List<GraphPoint>? canvasPoints,
    List<TraceGeometry>? exclusions,
    TraceImagery? imagery,
    bool removeImagery = false,
    bool? closed,
    double? metersPerCanvasUnit,
  }) =>
      TraceGeometry(
        id: id ?? this.id,
        label: label ?? this.label,
        address: address ?? this.address,
        geoPoints: geoPoints ?? this.geoPoints,
        canvasPoints: canvasPoints ?? this.canvasPoints,
        exclusions: exclusions ?? this.exclusions,
        imagery: removeImagery ? null : imagery ?? this.imagery,
        closed: closed ?? this.closed,
        metersPerCanvasUnit: metersPerCanvasUnit ?? this.metersPerCanvasUnit,
      );

  TraceGeometry transformCanvas(GraphPoint Function(GraphPoint) transform) =>
      copyWith(
        canvasPoints: canvasPoints.map(transform).toList(),
        exclusions:
            exclusions.map((e) => e.transformCanvas(transform)).toList(),
        imagery: imagery?.copyWith(
            corners: imagery!.corners.map(transform).toList()),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'address': address,
        'geoPoints': geoPoints.map((point) => point.toJson()).toList(),
        'canvasPoints':
            canvasPoints.map((point) => {'x': point.x, 'y': point.y}).toList(),
        if (exclusions.isNotEmpty)
          'exclusions': exclusions.map((e) => e.toJson()).toList(),
        if (imagery != null) 'imagery': imagery!.toJson(),
        'closed': closed,
        'metersPerCanvasUnit': metersPerCanvasUnit,
      };
}

/// A bounded NC OneMap snapshot. Corners are top-left, top-right, bottom-left
/// in graph coordinates so translation/rotation never detaches the photo.
class TraceImagery {
  const TraceImagery(
      {required this.base64Jpeg,
      required this.corners,
      required this.capturedAt,
      this.attribution = 'NC OneMap Orthoimagery · NCCGIA / NC 911 Board'});
  final String base64Jpeg;
  final List<GraphPoint> corners;
  final String capturedAt;
  final String attribution;
  Rect? get bounds {
    if (corners.length != 3) return null;
    final fourth = corners[1].offset + corners[2].offset - corners[0].offset;
    return [corners[0].offset, corners[1].offset, corners[2].offset, fourth]
        .map((p) => Rect.fromLTWH(p.dx, p.dy, 0, 0))
        .reduce((a, b) => a.expandToInclude(b));
  }

  TraceImagery copyWith({List<GraphPoint>? corners}) => TraceImagery(
      base64Jpeg: base64Jpeg,
      corners: corners ?? this.corners,
      capturedAt: capturedAt,
      attribution: attribution);
  factory TraceImagery.fromJson(Map<String, Object?> json) => TraceImagery(
      base64Jpeg: json['base64Jpeg'] as String? ?? '',
      capturedAt: json['capturedAt'] as String? ?? '',
      attribution: json['attribution'] as String? ??
          'NC OneMap Orthoimagery · NCCGIA / NC 911 Board',
      corners: (json['corners'] as List? ?? [])
          .whereType<Map>()
          .map((p) => GraphPoint(
              x: (p['x'] as num).toDouble(), y: (p['y'] as num).toDouble()))
          .toList());
  Map<String, Object?> toJson() => {
        'base64Jpeg': base64Jpeg,
        'capturedAt': capturedAt,
        'attribution': attribution,
        'corners': corners.map((p) => {'x': p.x, 'y': p.y}).toList(),
      };
}
