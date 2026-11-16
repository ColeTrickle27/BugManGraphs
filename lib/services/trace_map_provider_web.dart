import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart' as latlong;

import '../models/trace_geometry.dart';
import 'trace_map_provider.dart';

TraceMapProvider createTraceMapProvider() => NorthCarolinaTraceMapProvider();

class NorthCarolinaTraceMapProvider implements TraceMapProvider {
  // NC OneMap publishes this fused tile cache alongside the dynamic WMS
  // service. Keeping the same imagery provider preserves the field tracing
  // workflow while avoiding per-tile WMS rendering work.
  static const String _imageryTileUrl =
      'https://services.nconemap.gov/secure/rest/services/Imagery/'
      'Orthoimagery_Latest_cached/ImageServer/tile/{z}/{y}/{x}';

  @override
  Future<void> initialize() async {}

  @override
  Widget buildMap({
    required GeoPoint center,
    required GeoPoint selectedAddress,
    required List<GeoPoint> points,
    List<List<GeoPoint>> referencePolygons = const [],
    required ValueChanged<GeoPoint> onMapTap,
    required void Function(int index, GeoPoint point) onVertexMoved,
  }) =>
      _NorthCarolinaTraceMap(
        imageryTileUrl: _imageryTileUrl,
        center: center,
        selectedAddress: selectedAddress,
        points: points,
        referencePolygons: referencePolygons,
        onMapTap: onMapTap,
        onVertexMoved: onVertexMoved,
      );
}

class _NorthCarolinaTraceMap extends StatefulWidget {
  const _NorthCarolinaTraceMap({
    required this.imageryTileUrl,
    required this.center,
    required this.selectedAddress,
    required this.points,
    required this.referencePolygons,
    required this.onMapTap,
    required this.onVertexMoved,
  });

  final String imageryTileUrl;
  final GeoPoint center;
  final GeoPoint selectedAddress;
  final List<GeoPoint> points;
  final List<List<GeoPoint>> referencePolygons;
  final ValueChanged<GeoPoint> onMapTap;
  final void Function(int index, GeoPoint point) onVertexMoved;

  @override
  State<_NorthCarolinaTraceMap> createState() => _NorthCarolinaTraceMapState();
}

class _NorthCarolinaTraceMapState extends State<_NorthCarolinaTraceMap> {
  static const _minimumZoom = 4.0;
  static const _maximumDisplayZoom = 22.0;
  static const _maximumNativeZoom = 20;

  final MapController _mapController = MapController();
  bool _mapReady = false;

  @override
  void didUpdateWidget(covariant _NorthCarolinaTraceMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_mapReady ||
        _samePoint(oldWidget.selectedAddress, widget.selectedAddress)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      final camera = _mapController.camera;
      _mapController.move(
        latlong.LatLng(
          widget.selectedAddress.latitude,
          widget.selectedAddress.longitude,
        ),
        camera.zoom < 19 ? 19 : camera.zoom,
      );
    });
  }

  void _zoomBy(double amount) {
    if (!_mapReady) return;
    final camera = _mapController.camera;
    final nextZoom = (camera.zoom + amount)
        .clamp(_minimumZoom, _maximumDisplayZoom)
        .toDouble();
    _mapController.move(camera.center, nextZoom);
  }

  bool _samePoint(GeoPoint first, GeoPoint second) =>
      first.latitude == second.latitude && first.longitude == second.longitude;

  @override
  Widget build(BuildContext context) {
    final mapPoints = <latlong.LatLng>[
      for (final point in widget.points)
        latlong.LatLng(point.latitude, point.longitude),
    ];
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: latlong.LatLng(
              widget.center.latitude,
              widget.center.longitude,
            ),
            initialZoom: 19,
            initialCameraFit: mapPoints.length >= 2
                ? CameraFit.coordinates(
                    coordinates: mapPoints,
                    padding: const EdgeInsets.all(56),
                    maxZoom: _maximumNativeZoom.toDouble(),
                  )
                : null,
            minZoom: _minimumZoom,
            // NC OneMap's imagery is natively available through level 20.
            // Display zooms 21–22 rescale those level-20 tiles rather than
            // requesting blank level-21 tiles, so close corners can be placed
            // precisely without changing the saved geographic points.
            maxZoom: _maximumDisplayZoom,
            onMapReady: () => setState(() => _mapReady = true),
            onTap: (_, position) => widget.onMapTap(
              GeoPoint(
                latitude: position.latitude,
                longitude: position.longitude,
              ),
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: widget.imageryTileUrl,
              maxZoom: _maximumDisplayZoom,
              maxNativeZoom: _maximumNativeZoom,
              userAgentPackageName: 'com.holloman.bugman_graphs',
            ),
            PolygonLayer(polygons: [
              for (final ring in widget.referencePolygons)
                if (ring.length >= 3)
                  Polygon(
                      points: [
                        for (final p in ring)
                          latlong.LatLng(p.latitude, p.longitude)
                      ],
                      color: const Color(0x22FFB300),
                      borderColor: const Color(0xFFFFB300),
                      borderStrokeWidth: 3)
            ]),
            // This is a temporary trace-workspace aid only. It represents the
            // selected address result, not a saved graph object or an
            // inspection marker.
            MarkerLayer(
              markers: [
                Marker(
                  point: latlong.LatLng(
                    widget.selectedAddress.latitude,
                    widget.selectedAddress.longitude,
                  ),
                  width: 32,
                  height: 32,
                  child: const Tooltip(
                    message: 'Selected address',
                    child: Icon(
                      Icons.gps_fixed,
                      key: ValueKey('trace-search-result-pin'),
                      color: Color(0xFF1565C0),
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
            if (mapPoints.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: mapPoints,
                    color: const Color(0x33CC2000),
                    borderColor: const Color(0xFFCC2000),
                    borderStrokeWidth: 4,
                  ),
                ],
              ),
            if (mapPoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: mapPoints,
                    color: const Color(0xFFCC2000),
                    strokeWidth: 4,
                  ),
                ],
              ),
            DragMarkers(
              markers: [
                for (var index = 0; index < mapPoints.length; index += 1)
                  DragMarker(
                    point: mapPoints[index],
                    // The tap area remains practical for field use while the
                    // visible pin stays small enough for tight corners.
                    size: const Size(32, 32),
                    builder: (context, position, isDragging) => Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: _VertexPin(number: index + 1),
                      ),
                    ),
                    onDragEnd: (_, position) => widget.onVertexMoved(
                      index,
                      GeoPoint(
                        latitude: position.latitude,
                        longitude: position.longitude,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 12,
          top: 12,
          child: _MapZoomControls(
            enabled: _mapReady,
            onZoomIn: () => _zoomBy(1),
            onZoomOut: () => _zoomBy(-1),
          ),
        ),
        const Positioned(
          right: 6,
          bottom: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Color(0xCCFFFFFF)),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Text(
                'NC OneMap Orthoimagery · NCCGIA / NC 911 Board',
                style: TextStyle(fontSize: 10, color: Colors.black),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  const _MapZoomControls({
    required this.enabled,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final bool enabled;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('trace-map-zoom-in'),
              tooltip: 'Zoom in closer',
              constraints: const BoxConstraints.tightFor(width: 42, height: 42),
              onPressed: enabled ? onZoomIn : null,
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 32, child: Divider(height: 1)),
            IconButton(
              key: const ValueKey('trace-map-zoom-out'),
              tooltip: 'Zoom out',
              constraints: const BoxConstraints.tightFor(width: 42, height: 42),
              onPressed: enabled ? onZoomOut : null,
              icon: const Icon(Icons.remove),
            ),
          ],
        ),
      );
}

class _VertexPin extends StatelessWidget {
  const _VertexPin({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFCC2000),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Center(
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 9,
          ),
        ),
      ),
    );
  }
}
