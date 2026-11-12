// Standalone review target: synthetic graph identity and in-memory saves only.
import 'dart:convert';

import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/screens/trace_workspace_screen.dart';
import 'package:bugman_graphs/services/bugman_portal_service_stub.dart';
import 'package:bugman_graphs/services/graph_repository_stub.dart';
import 'package:bugman_graphs/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'satellite_preview/address_service.dart';

void main() => runApp(MaterialApp(
    title: 'Satellite acreage preview',
    theme: buildBugManTheme(),
    home: const SatellitePreviewHome()));

const sampleTrace = TraceGeometry(
  id: 'preview-yard',
  label: 'Sample yard',
  geoPoints: [
    GeoPoint(latitude: 35.09445, longitude: -78.61855),
    GeoPoint(latitude: 35.09445, longitude: -78.61805),
    GeoPoint(latitude: 35.09385, longitude: -78.61805),
    GeoPoint(latitude: 35.0938, longitude: -78.61775),
    GeoPoint(latitude: 35.0936, longitude: -78.6176),
    GeoPoint(latitude: 35.0929, longitude: -78.61795),
    GeoPoint(latitude: 35.09285, longitude: -78.61815),
  ],
  canvasPoints: [],
  exclusions: [
    TraceGeometry(id: 'preview-home', label: 'Home', geoPoints: [
      GeoPoint(latitude: 35.09348, longitude: -78.61803),
      GeoPoint(latitude: 35.09348, longitude: -78.61788),
      GeoPoint(latitude: 35.0933, longitude: -78.61788),
      GeoPoint(latitude: 35.0933, longitude: -78.61803),
    ], canvasPoints: [])
  ],
);

class SatellitePreviewHome extends StatefulWidget {
  const SatellitePreviewHome({super.key});
  @override
  State<SatellitePreviewHome> createState() => _SatellitePreviewHomeState();
}

class _SatellitePreviewHomeState extends State<SatellitePreviewHome> {
  final _repository = MemoryGraphRepository();
  GraphDocument? _document;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open(sample: true));
  }

  Future<void> _open({required bool sample}) async {
    if (_opening) return;
    _opening = true;
    final addresses = PreviewAddressService();
    final trace = await Navigator.of(context).push<TraceGeometry>(
      MaterialPageRoute(
        builder: (_) => TraceWorkspaceScreen(
          address: '',
          canvasSize: const Size(3600, 2600),
          traceLabel: sample ? 'Sample yard' : 'Yard boundary',
          initialTrace: sample ? sampleTrace : null,
          addressService: addresses,
          addressAttribution: const Text('U.S. Census Geocoder',
              style: TextStyle(fontSize: 11)),
        ),
      ),
    );
    addresses.dispose();
    _opening = false;
    if (!mounted || trace == null) return;
    final document = GraphDocument(
        customer: const GraphCustomerInfo(
            name: 'Satellite acreage preview',
            serviceAddress: '',
            pestPacLocationNumber: '',
            pestPacBillToNumber: '',
            serviceType: 'Yard measurement',
            createdBy: 'Preview'),
        traces: [trace],
        layers: const {'trace': GraphLayerState(visible: true)});
    // Exercise the real saved-graph contract before opening the real editor.
    _document =
        GraphDocument.fromJson(jsonDecode(jsonEncode(document.toJson())));
    document.dispose();
    await _showGraph();
  }

  Future<void> _showGraph() async {
    final addresses = PreviewAddressService();
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => GraphCanvasScreen(
              document: _document!,
              repository: _repository,
              traceAddressService: addresses,
              traceAddressAttribution: const Text('U.S. Census Geocoder',
                  style: TextStyle(fontSize: 11)),
              portalService: UnavailableBugManPortalService())));
    } finally {
      addresses.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Satellite acreage preview')),
      body: Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Try a sample yard or trace a North Carolina property.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => _open(sample: true),
                    child: const Text('Open sample yard')),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: () => _open(sample: false),
                    child: const Text('Start a new property')),
                if (_document != null)
                  TextButton(
                      onPressed: _showGraph,
                      child: const Text('View saved preview graph')),
                const SizedBox(height: 16),
                const Text(
                    'Preview only. Changes stay in this browser session.',
                    textAlign: TextAlign.center),
              ]))));
}
