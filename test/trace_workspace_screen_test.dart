import 'dart:async';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/services/trace_area_service.dart';
import 'package:bugman_graphs/services/trace_imagery_service.dart';

import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/screens/trace_workspace_screen.dart';
import 'package:bugman_graphs/services/address_suggestion_service.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:bugman_graphs/services/trace_map_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'phone workflow deducts a building, preserves failed transfer, and saves satellite imagery',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final provider = _FakeTraceMapProvider();
    final imageryService = _FakeImageryService();
    final image = img.Image(width: 32, height: 32)
      ..clear(img.ColorRgb8(40, 130, 70));
    imageryService.jpeg = base64Encode(img.encodeJpg(image));
    await tester.runAsync(() => TraceImageryCache.instance.load(TraceImagery(
        base64Jpeg: imageryService.jpeg, capturedAt: 'QA', corners: const [])));
    TraceGeometry? result;
    const original = TraceGeometry(id: 'yard', label: 'Yard', geoPoints: [
      GeoPoint(latitude: 35, longitude: -78),
      GeoPoint(latitude: 35, longitude: -77.999),
      GeoPoint(latitude: 34.999, longitude: -77.999),
      GeoPoint(latitude: 34.999, longitude: -78),
    ], canvasPoints: []);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await Navigator.push<TraceGeometry>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TraceWorkspaceScreen(
                                  address: '',
                                  canvasSize: const Size(3600, 2600),
                                  traceLabel: 'Yard',
                                  initialTrace: original,
                                  provider: provider,
                                  addressService:
                                      _FakeAddressSuggestionService(),
                                  imageryService: imageryService)));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-trace-exclusion')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Home');
    await tester.tap(find.text('Trace area'));
    await tester.pumpAndSettle();
    for (final p in const [
      GeoPoint(latitude: 34.9999, longitude: -77.9999),
      GeoPoint(latitude: 34.9999, longitude: -77.9997),
      GeoPoint(latitude: 34.9997, longitude: -77.9997),
      GeoPoint(latitude: 34.9997, longitude: -77.9999)
    ]) {
      provider.tapPoint(p);
      await tester.pump();
    }
    expect(find.text('Home'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trace-options')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('include-trace-imagery')));
    await tester.tap(find.byKey(const ValueKey('include-trace-imagery')));
    await tester.pumpAndSettle();
    imageryService.fail = true;
    await tester.tap(find.byKey(const ValueKey('finish-trace-button')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('Satellite transfer failed'), findsOneWidget);
    expect(provider.points, hasLength(4));
    imageryService.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.imagery, isNotNull);
    expect(result!.exclusions.single.label, 'Home');
    expect(result!.exclusions.single.canvasPoints, hasLength(4));
    expect(TraceAreaService.netSquareMeters(result!),
        lessThan(TraceAreaService.netSquareMeters(original)));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'phone keeps controls compact with help and imagery options available',
      (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: TraceWorkspaceScreen(
      address: '',
      canvasSize: const Size(3600, 2600),
      traceLabel: 'Sample yard',
      provider: _FakeTraceMapProvider(),
      addressService: _FakeAddressSuggestionService(),
      initialTrace:
          const TraceGeometry(id: 'sample', label: 'Sample yard', geoPoints: [
        GeoPoint(latitude: 35, longitude: -78),
        GeoPoint(latitude: 35.001, longitude: -78),
        GeoPoint(latitude: 35.001, longitude: -78.001)
      ], canvasPoints: [], exclusions: [
        TraceGeometry(
            id: 'home', label: 'Home', geoPoints: [], canvasPoints: [])
      ]),
    )));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('fake-trace-map'))).dy,
        lessThan(180));
    expect(find.textContaining('Tap the yard boundary corners.'), findsNothing);
    await tester.tap(find.byTooltip('Trace help'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Acreage is estimated'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trace-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('include-trace-imagery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trace-options')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
                find.byKey(const ValueKey('include-trace-imagery')))
            .checked,
        isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('search errors remain visible while a saved trace is displayed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: TraceWorkspaceScreen(
            address: 'A failing address',
            canvasSize: const Size(3600, 2600),
            traceLabel: 'Test',
            provider: _FakeTraceMapProvider(),
            addressService: _FailedAddressService(),
            initialTrace:
                const TraceGeometry(id: 'saved', label: 'Saved', geoPoints: [
              GeoPoint(latitude: 35, longitude: -78),
              GeoPoint(latitude: 35.001, longitude: -78),
              GeoPoint(latitude: 35.001, longitude: -78.001)
            ], canvasPoints: []))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fake-trace-map')), findsOneWidget);
    expect(find.textContaining('Address search could not be reached.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('trace-workspace-error')), findsOneWidget);
  });
  testWidgets('five address suggestions fit above the map on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: TraceWorkspaceScreen(
      address: 'Main Street',
      canvasSize: const Size(3600, 2600),
      traceLabel: 'Test',
      provider: _FakeTraceMapProvider(),
      addressService: _ManySuggestionsService(),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('finish-trace-button')), findsOneWidget);
  });
  testWidgets(
      'editing during selection unlocks search and ignores old selection',
      (tester) async {
    final service = _DelayedSelectionService();
    final provider = _FakeTraceMapProvider();
    await tester.pumpWidget(MaterialApp(
        home: TraceWorkspaceScreen(
      address: '',
      canvasSize: const Size(3600, 2600),
      traceLabel: 'Test',
      provider: provider,
      addressService: service,
    )));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('trace-address-field'));
    await tester.enterText(field, 'Old address');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey('trace-address-suggestion-test-address')));
    await tester.pump();
    await tester.enterText(field, 'New address');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Search'))
            .onPressed,
        isNotNull);
    await tester.tap(
        find.byKey(const ValueKey('trace-address-suggestion-test-address')));
    await tester.pump();
    expect(service.pending, hasLength(2));
    service.pending[0].complete(await _FakeAddressSuggestionService().select(
        const AddressSuggestion(id: 'old', address: 'Old', primaryText: 'Old'),
        sessionToken: 'old'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'New address');
    service.pending[1].complete(await _FakeAddressSuggestionService().select(
        const AddressSuggestion(id: 'new', address: 'New', primaryText: 'New'),
        sessionToken: 'new'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fake-trace-map')), findsOneWidget);
  });
  testWidgets('trace sign in preserves the address and all existing points',
      (tester) async {
    final provider = _FakeTraceMapProvider();
    final service = _FakeAddressSuggestionService()..requiresSignIn = true;
    String? signInUrl;
    const trace = TraceGeometry(
      id: 'recovery-trace',
      label: 'Recovery trace',
      geoPoints: [
        GeoPoint(latitude: 35, longitude: -86),
        GeoPoint(latitude: 35.0001, longitude: -86),
        GeoPoint(latitude: 35.0001, longitude: -86.0001),
      ],
      canvasPoints: [],
    );
    await tester.pumpWidget(MaterialApp(
        home: TraceWorkspaceScreen(
      address: '123 Main Street',
      canvasSize: const Size(3600, 2600),
      traceLabel: 'Recovery trace',
      provider: provider,
      addressService: service,
      initialTrace: trace,
      onPortalSignIn: (url) => signInUrl = url,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to OpsBrain'), findsOneWidget);
    expect(provider.points, trace.geoPoints);
    await tester.tap(find.text('Sign in to OpsBrain'));
    await tester.pumpAndSettle();
    expect(signInUrl, 'https://ops.holloman-ext.com/');
    expect(provider.points, trace.geoPoints);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('trace-address-field')))
            .controller!
            .text,
        '123 Main Street');
    service.requiresSignIn = false;
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to OpsBrain'), findsNothing);
    expect(provider.points, trace.geoPoints);
  });
  testWidgets(
      'trace workspace opens at the job address and returns a scaled trace',
      (tester) async {
    final provider = _FakeTraceMapProvider();
    final addressService = _FakeAddressSuggestionService();
    TraceGeometry? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await Navigator.push<TraceGeometry>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TraceWorkspaceScreen(
                        address: '123 Main Street',
                        canvasSize: const Size(3600, 2600),
                        traceLabel: 'Property Trace 1',
                        provider: provider,
                        addressService: addressService,
                      ),
                    ),
                  );
                },
                child: const Text('Open Trace'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Trace'));
    await tester.pumpAndSettle();
    expect(addressService.lastQuery, '123 Main Street');
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('trace-address-field')),
    );
    expect(field.controller?.text, '123 Main Street, Raleigh, NC 27601');
    expect(
        find.byKey(const ValueKey('trace-address-suggestions')), findsNothing);
    expect(
        provider.selectedAddress, const GeoPoint(latitude: 35, longitude: -86));
    expect(find.text('Property-level location'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fake-trace-map')));
    await tester.tap(find.byKey(const ValueKey('fake-trace-map')));
    await tester.tap(find.byKey(const ValueKey('fake-trace-map')));
    await tester.pump();
    final finish = tester.widget<FilledButton>(
      find.byKey(const ValueKey('finish-trace-button')),
    );
    expect(finish.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('finish-trace-button')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.geoPoints, hasLength(3));
    expect(result!.address, '123 Main Street, Raleigh, NC 27601');
    expect(result!.canvasPoints, hasLength(3));
    expect(result!.metersPerCanvasUnit, greaterThan(0));
  });

  testWidgets(
      'existing trace reopens at the job address and keeps points editable',
      (tester) async {
    final provider = _FakeTraceMapProvider();
    final addressService = _FakeAddressSuggestionService();
    TraceGeometry? result;
    const original = TraceGeometry(
      id: 'property-trace-2',
      label: 'Property Trace 2',
      geoPoints: [
        GeoPoint(latitude: 35.0, longitude: -86.0),
        GeoPoint(latitude: 35.0001, longitude: -86.0001),
        GeoPoint(latitude: 35.0002, longitude: -86.0),
      ],
      canvasPoints: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await Navigator.push<TraceGeometry>(
                context,
                MaterialPageRoute(
                  builder: (_) => TraceWorkspaceScreen(
                    address: '123 Main Street',
                    canvasSize: const Size(3600, 2600),
                    traceLabel: original.label,
                    initialTrace: original,
                    provider: provider,
                    addressService: addressService,
                  ),
                ),
              );
            },
            child: const Text('Edit Trace'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit Trace'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Property Trace 2'), findsOneWidget);
    expect(
        provider.selectedAddress, const GeoPoint(latitude: 35, longitude: -86));
    expect(provider.points, hasLength(3));
    expect(provider.points[1].latitude, 35.0001);

    provider.moveVertex(
      1,
      const GeoPoint(latitude: 35.00015, longitude: -86.00015),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('finish-trace-button')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.id, original.id);
    expect(result!.label, original.label);
    expect(result!.geoPoints[1].latitude, 35.00015);
    expect(result!.geoPoints[1].longitude, -86.00015);
  });

  testWidgets(
      'existing trace opens from saved points while job-address lookup is pending',
      (tester) async {
    final provider = _FakeTraceMapProvider();
    final addressService = _DelayedAddressSuggestionService();
    const original = TraceGeometry(
      id: 'property-trace-3',
      label: 'Property Trace 3',
      geoPoints: [
        GeoPoint(latitude: 35.0, longitude: -86.0),
        GeoPoint(latitude: 35.0003, longitude: -86.0003),
        GeoPoint(latitude: 35.0006, longitude: -86.0),
      ],
      canvasPoints: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TraceWorkspaceScreen(
          address: '123 Main Street',
          canvasSize: const Size(3600, 2600),
          traceLabel: original.label,
          initialTrace: original,
          provider: provider,
          addressService: addressService,
        ),
      ),
    );
    await tester.pump();

    expect(addressService.requests, ['123 Main Street']);
    expect(find.byKey(const ValueKey('fake-trace-map')), findsOneWidget);
    expect(provider.selectedAddress, isNotNull);
    expect(provider.selectedAddress!.latitude, closeTo(35.0003, 0.0000001));
    expect(provider.selectedAddress!.longitude, closeTo(-86.0001, 0.0000001));
  });

  testWidgets('trace workspace ignores a stale suggestion request',
      (tester) async {
    final service = _DelayedAddressSuggestionService();
    await tester.pumpWidget(
      MaterialApp(
        home: TraceWorkspaceScreen(
          address: '',
          canvasSize: const Size(3600, 2600),
          traceLabel: 'Property Trace 1',
          provider: _FakeTraceMapProvider(),
          addressService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('trace-address-field')),
      'Old address',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.requests, ['Old address']);

    await tester.enterText(
      find.byKey(const ValueKey('trace-address-field')),
      'New address',
    );
    service.complete('Old address', 'old-address');
    await tester.pump();
    expect(find.byKey(const ValueKey('trace-address-suggestion-old-address')),
        findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    service.complete('New address', 'new-address');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trace-address-suggestion-new-address')),
        findsOneWidget);
  });
}

class _FakeTraceMapProvider implements TraceMapProvider {
  GeoPoint? selectedAddress;
  List<GeoPoint> points = const <GeoPoint>[];
  void Function(int index, GeoPoint point)? _onVertexMoved;
  ValueChanged<GeoPoint>? _onMapTap;
  void tapPoint(GeoPoint point) => _onMapTap!(point);

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
  }) {
    this.selectedAddress = selectedAddress;
    this.points = List<GeoPoint>.of(points);
    _onVertexMoved = onVertexMoved;
    _onMapTap = onMapTap;
    return GestureDetector(
      key: const ValueKey('fake-trace-map'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final offset = points.length * 0.0001;
        onMapTap(
          GeoPoint(
            latitude: center.latitude + (points.length == 2 ? offset : 0),
            longitude: center.longitude + offset,
          ),
        );
      },
      child: const ColoredBox(color: Colors.blueGrey),
    );
  }

  void moveVertex(int index, GeoPoint point) => _onVertexMoved!(index, point);
}

class _FakeAddressSuggestionService implements AddressSuggestionService {
  bool requiresSignIn = false;
  String? lastQuery;
  String? lastSessionToken;

  @override
  Future<AddressSelection> select(
    AddressSuggestion suggestion, {
    required String sessionToken,
  }) async {
    lastSessionToken = sessionToken;
    return const AddressSelection(
      standardizedAddress: '123 Main Street, Raleigh, NC 27601',
      coordinate: GeoPoint(latitude: 35, longitude: -86),
      quality: AddressQuality(
        geocodeGranularity: 'PREMISE',
        validationGranularity: 'PREMISE',
        isPropertyLevel: true,
        addressComplete: true,
        requiresReview: false,
      ),
    );
  }

  @override
  Future<List<AddressSuggestion>> suggest(
    String query, {
    required String sessionToken,
  }) async {
    if (requiresSignIn) {
      throw const PortalAuthenticationException(
          'https://ops.holloman-ext.com/');
    }
    lastQuery = query;
    lastSessionToken = sessionToken;
    return const [
      AddressSuggestion(
        id: 'test-address',
        address: '123 Main Street, Raleigh, NC',
        primaryText: '123 Main Street',
        secondaryText: 'Raleigh, NC',
      ),
    ];
  }
}

class _DelayedAddressSuggestionService implements AddressSuggestionService {
  final Map<String, Completer<List<AddressSuggestion>>> _pending = {};
  final List<String> requests = [];

  @override
  Future<AddressSelection> select(
    AddressSuggestion suggestion, {
    required String sessionToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<AddressSuggestion>> suggest(
    String query, {
    required String sessionToken,
  }) {
    requests.add(query);
    return (_pending[query] ??= Completer<List<AddressSuggestion>>()).future;
  }

  void complete(String query, String id) {
    _pending[query]!.complete([
      AddressSuggestion(
        id: id,
        address: '$query, Raleigh, NC',
        primaryText: query,
        secondaryText: 'Raleigh, NC',
      ),
    ]);
  }
}

class _DelayedSelectionService extends _FakeAddressSuggestionService {
  final pending = <Completer<AddressSelection>>[];
  @override
  Future<AddressSelection> select(AddressSuggestion suggestion,
      {required String sessionToken}) {
    final result = Completer<AddressSelection>();
    pending.add(result);
    return result.future;
  }
}

class _ManySuggestionsService extends _FakeAddressSuggestionService {
  @override
  Future<List<AddressSuggestion>> suggest(String query,
          {required String sessionToken}) async =>
      [
        for (var i = 0; i < 5; i++)
          AddressSuggestion(
              id: '$i',
              address: '$i Main Street, Raleigh, NC',
              primaryText: '$i Main Street',
              secondaryText: 'Raleigh, NC'),
      ];
}

class _FakeImageryService extends TraceImageryService {
  bool fail = false;
  String jpeg = '';
  @override
  Future<TraceImagery> capture(
      {required List<GeoPoint> corners,
      required List<GraphPoint> canvasCorners}) async {
    if (fail) throw StateError('Offline');
    return TraceImagery(
        base64Jpeg: jpeg, corners: canvasCorners, capturedAt: 'QA');
  }
}

class _FailedAddressService extends _FakeAddressSuggestionService {
  @override
  Future<List<AddressSuggestion>> suggest(String query,
          {required String sessionToken}) async =>
      throw Exception('Address search could not be reached.');
}
