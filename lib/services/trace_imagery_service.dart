import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'trace_image_encoder.dart';
import '../models/trace_geometry.dart';
import '../models/graph_point.dart';

class TraceImageryCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

class TraceImageryCancelledException implements Exception {
  const TraceImageryCancelledException();
}

class TraceImageryProgress {
  const TraceImageryProgress(this.completed, this.total,
      {this.preparing = false});
  final int completed;
  final int total;
  final bool preparing;
  String get message =>
      preparing ? 'Preparing image…' : 'Downloading image $completed/$total';
}

class TraceImageryService {
  const TraceImageryService(
      {this.client, this.transferTimeout = const Duration(seconds: 45)});
  final http.Client? client;
  final Duration transferTimeout;
  static const tileEndpoint =
      'https://services.nconemap.gov/secure/rest/services/Imagery/Orthoimagery_Latest_cached/ImageServer/tile';

  Future<TraceImagery> capture(
      {required List<GeoPoint> corners,
      required List<GraphPoint> canvasCorners,
      TraceImageryCancellation? cancellation,
      ValueChanged<TraceImageryProgress>? onProgress}) async {
    if (cancellation?.isCancelled == true) {
      throw const TraceImageryCancelledException();
    }
    final west = corners[0].longitude, east = corners[1].longitude;
    final north = corners[0].latitude, south = corners[2].latitude;
    if (!(west < east && south < north)) {
      throw ArgumentError('Invalid satellite image extent');
    }
    double tileX(double lon, int z) => (lon + 180) / 360 * math.pow(2, z);
    double tileY(double lat, int z) {
      final rad = lat * math.pi / 180;
      return (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) /
          2 *
          math.pow(2, z);
    }

    double tileLatitude(int y, int z) {
      final n = math.pi * (1 - 2 * y / math.pow(2, z));
      return math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
    }

    var zoom = 20;
    while (zoom > 1 &&
        math.max((tileX(east, zoom) - tileX(west, zoom)) * 256,
                (tileY(south, zoom) - tileY(north, zoom)) * 256) >
            1600) {
      zoom--;
    }
    final firstX = tileX(west, zoom).floor(),
        lastX = tileX(east, zoom).ceil() - 1;
    final firstY = tileY(north, zoom).floor(),
        lastY = tileY(south, zoom).ceil() - 1;
    final aspect = (east - west) *
        math.cos((north + south) / 2 * math.pi / 180) /
        (north - south);
    final width = aspect >= 1 ? 1600 : math.max(1, (1600 * aspect).round());
    final height = aspect >= 1 ? math.max(1, (1600 / aspect).round()) : 1600;
    final tiles = [
      for (var y = firstY; y <= lastY; y++)
        for (var x = firstX; x <= lastX; x++) (x: x, y: y)
    ];
    final images = <({int x, int y}), ui.Image>{};
    final connection = client ?? http.Client();
    var stopped = false;
    void checkActive() {
      if (stopped || cancellation?.isCancelled == true) {
        throw const TraceImageryCancelledException();
      }
    }

    Future<TraceImagery> transfer() async {
      // Use the same public cached tiles as the map. Dynamic exportImage on
      // this service requires a token; cached imagery needs no credentials.
      // Four workers bound connection and decode pressure on field devices.
      var next = 0;
      var completed = 0;
      onProgress?.call(TraceImageryProgress(0, tiles.length));
      await Future.wait(
          List.generate(math.min(4, tiles.length), (_) async {
            while (next < tiles.length) {
              checkActive();
              final tile = tiles[next++];
              final response = await connection
                  .get(Uri.parse('$tileEndpoint/$zoom/${tile.y}/${tile.x}'))
                  .timeout(const Duration(seconds: 30));
              checkActive();
              if (response.statusCode != 200) {
                throw StateError('Satellite tile unavailable');
              }
              final codec = await ui
                  .instantiateImageCodec(response.bodyBytes)
                  .then((codec) {
                if (stopped || cancellation?.isCancelled == true) {
                  codec.dispose();
                  throw const TraceImageryCancelledException();
                }
                return codec;
              }).timeout(const Duration(seconds: 8));
              try {
                final frame = await codec.getNextFrame().then((frame) {
                  if (stopped || cancellation?.isCancelled == true) {
                    frame.image.dispose();
                    throw const TraceImageryCancelledException();
                  }
                  return frame;
                }).timeout(const Duration(seconds: 8));
                images[tile] = frame.image;
                onProgress
                    ?.call(TraceImageryProgress(++completed, tiles.length));
              } finally {
                codec.dispose();
              }
            }
          }),
          eagerError: true);
      checkActive();
      onProgress?.call(
          TraceImageryProgress(completed, tiles.length, preparing: true));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..clipRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
      for (final tile in tiles) {
        final image = images[tile]!;
        final left = (tile.x / math.pow(2, zoom) * 360 - 180 - west) /
            (east - west) *
            width;
        final right = ((tile.x + 1) / math.pow(2, zoom) * 360 - 180 - west) /
            (east - west) *
            width;
        final top =
            (north - tileLatitude(tile.y, zoom)) / (north - south) * height;
        final bottom =
            (north - tileLatitude(tile.y + 1, zoom)) / (north - south) * height;
        canvas.drawImageRect(
            image,
            ui.Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble()),
            ui.Rect.fromLTRB(left, top, right, bottom),
            ui.Paint()..filterQuality = ui.FilterQuality.medium);
      }
      final picture = recorder.endRecording();
      try {
        final snapshot = await picture.toImage(width, height).then((image) {
          if (stopped || cancellation?.isCancelled == true) {
            image.dispose();
            throw const TraceImageryCancelledException();
          }
          return image;
        }).timeout(const Duration(seconds: 8));
        try {
          final jpeg = await encodeTraceImage(snapshot)
              .timeout(const Duration(seconds: 10));
          checkActive();
          return TraceImagery(
              base64Jpeg: base64Encode(jpeg),
              corners: canvasCorners,
              capturedAt: DateTime.now().toUtc().toIso8601String());
        } finally {
          snapshot.dispose();
        }
      } finally {
        picture.dispose();
      }
    }

    try {
      return await Future.any([
        transfer().timeout(transferTimeout),
        if (cancellation != null)
          cancellation.whenCancelled.then<TraceImagery>(
              (_) => throw const TraceImageryCancelledException()),
      ]);
    } finally {
      stopped = true;
      if (client == null) connection.close();
      for (final image in images.values) {
        image.dispose();
      }
    }
  }
}

/// Shared decoded snapshots for canvas rendering and export. The encoded image
/// remains in the graph, allowing offline reopen without provider requests.
class TraceImageryCache extends ChangeNotifier {
  static final instance = TraceImageryCache();
  final _images = <String, ui.Image>{};
  final _pending = <String, Future<void>>{};
  final _owners = <Object, Set<String>>{};
  void retain(Object owner, Iterable<TraceGeometry> traces) {
    _owners[owner] = {
      for (final trace in traces)
        if (trace.imagery != null) trace.imagery!.base64Jpeg
    };
  }

  void release(Object owner) {
    _owners.remove(owner);
    _prune();
  }

  void _prune() {
    final retained = _owners.values.expand((keys) => keys).toSet();
    for (final key in _images.keys.toList()) {
      if (_images.length <= 12) break;
      if (!retained.contains(key)) _images.remove(key)!.dispose();
    }
  }

  ui.Image? image(TraceImagery imagery) => _images[imagery.base64Jpeg];
  Future<void> load(TraceImagery imagery) async {
    final key = imagery.base64Jpeg;
    if (_images.containsKey(key)) return;
    await (_pending[key] ??= _decode(key));
  }

  Future<void> _decode(String key) async {
    try {
      final codec = await ui.instantiateImageCodec(base64Decode(key));
      try {
        _images[key] = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }

      _prune();
      notifyListeners();
    } finally {
      _pending.remove(key);
    }
  }
}
