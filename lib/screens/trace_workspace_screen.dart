import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/graph_document.dart';
import '../services/trace_area_service.dart';
import '../services/trace_imagery_service.dart';
import '../services/cloud_drafts/graph_draft_service.dart';
import '../models/trace_geometry.dart';
import '../models/graph_point.dart';
import '../services/address_suggestion_service.dart';
import '../services/address_suggestion_service_factory.dart';
import '../services/bugman_portal_service.dart';
import '../services/portal_sign_in.dart';
import '../services/measurement_format.dart';
import '../services/measurement_service.dart';
import '../services/trace_map_provider.dart';
import '../services/trace_map_provider_factory.dart';
import '../services/trace_projection_service.dart';

class TraceWorkspaceScreen extends StatefulWidget {
  const TraceWorkspaceScreen({
    required this.address,
    required this.canvasSize,
    required this.traceLabel,
    this.account,
    this.provider,
    this.addressService,
    this.initialTrace,
    this.autoSelectJobAddress = true,
    this.metersPerCanvasUnit = 0.3048 / 24,
    this.onPortalSignIn,
    this.imageryService = const TraceImageryService(),
    this.addressAttribution,
    super.key,
  });

  final TraceImageryService imageryService;
  final Widget? addressAttribution;
  final GraphDraftAccount? account;
  final String address;
  final Size canvasSize;
  final String traceLabel;
  final TraceMapProvider? provider;
  final AddressSuggestionService? addressService;
  final TraceGeometry? initialTrace;
  final bool autoSelectJobAddress;

  /// Canvas scale for new or edited geometry; unchanged saved frames are kept.
  final double metersPerCanvasUnit;
  final ValueChanged<String>? onPortalSignIn;

  @override
  State<TraceWorkspaceScreen> createState() => _TraceWorkspaceScreenState();
}

class _TraceWorkspaceScreenState extends State<TraceWorkspaceScreen> {
  static const _minimumQueryLength = 3;

  late final TraceMapProvider _provider;
  late final AddressSuggestionService _addressService;
  late final TextEditingController _addressController;
  late final GeoPoint? _savedTraceCenter;
  final List<GeoPoint> _points = <GeoPoint>[];
  final List<TraceGeometry> _exclusions = [];
  int? _activeExclusion;
  bool _includeImagery = false;
  bool _saving = false;
  TraceImageryCancellation? _activeTransfer;
  TraceImageryProgress? _transferProgress;
  List<GeoPoint> get _activePoints => _activeExclusion == null
      ? _points
      : _exclusions[_activeExclusion!].geoPoints;
  TraceGeometry get _preview => TraceGeometry(
      id: 'preview',
      label: widget.traceLabel,
      geoPoints: _points,
      canvasPoints: const [],
      exclusions: _exclusions);
  final Random _random = Random.secure();
  Timer? _searchDebounce;
  List<AddressSuggestion> _suggestions = const <AddressSuggestion>[];
  AddressSelection? _selectedAddress;
  String _sessionToken = '';
  String? _error;
  String? _signInUrl;
  int _searchRequest = 0;
  bool _initializingMap = true;
  bool _searching = false;
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    widget.account?.addListener(_accountChanged);
    _provider = widget.provider ?? createTraceMapProvider();
    _addressService = widget.addressService ?? createAddressSuggestionService();
    _addressController = TextEditingController(text: widget.address);
    _points.addAll(widget.initialTrace?.geoPoints ?? const <GeoPoint>[]);
    _exclusions.addAll((widget.initialTrace?.exclusions ?? [])
        .map((e) => e.copyWith(geoPoints: List.of(e.geoPoints))));
    _includeImagery = widget.initialTrace?.imagery != null;
    _savedTraceCenter = _centerFor(_points);
    _sessionToken = _newSessionToken();
    _initializeWorkspace();
  }

  void _accountChanged() {
    if (widget.account?.active == false) {
      _activeTransfer?.cancel();
      _searchDebounce?.cancel();
      ++_searchRequest;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _activeTransfer?.cancel();
    widget.account?.removeListener(_accountChanged);
    _searchDebounce?.cancel();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _initializeWorkspace() async {
    if (widget.account?.active == false) return;
    try {
      await _provider.initialize();
      if (!mounted || widget.account?.active == false) return;
      setState(() => _initializingMap = false);
      _scheduleSuggestionSearch(immediate: true);
    } catch (error) {
      if (!mounted || widget.account?.active == false) return;
      setState(() {
        _initializingMap = false;
        _error = _messageFor(error);
      });
    }
  }

  void _onAddressChanged(String _) {
    _signInUrl = null;
    _selectedAddress = null;
    _selecting = false;
    _error = null;
    _suggestions = const <AddressSuggestion>[];
    _sessionToken = _newSessionToken();
    _scheduleSuggestionSearch();
  }

  void _scheduleSuggestionSearch({bool immediate = false}) {
    _searchDebounce?.cancel();
    final request = ++_searchRequest;
    final query = _addressController.text.trim();
    if (query.length < _minimumQueryLength) {
      if (mounted) {
        setState(() {
          _searching = false;
          _suggestions = const <AddressSuggestion>[];
        });
      }
      return;
    }
    setState(() => _searching = true);
    void search() => _searchSuggestions(request, query, _sessionToken);
    if (immediate) {
      search();
    } else {
      _searchDebounce = Timer(const Duration(milliseconds: 300), search);
    }
  }

  Future<void> _searchSuggestions(
    int request,
    String query,
    String sessionToken,
  ) async {
    try {
      final suggestions = await _addressService.suggest(
        query,
        sessionToken: sessionToken,
      );
      if (!mounted ||
          request != _searchRequest ||
          widget.account?.active == false) {
        return;
      }
      _signInUrl = null;
      if (_shouldAutoSelectJobAddress(query, suggestions)) {
        setState(() {
          _searching = false;
          _suggestions = const <AddressSuggestion>[];
        });
        await _selectAddress(suggestions.single);
        return;
      }
      setState(() {
        _searching = false;
        _suggestions = suggestions;
        _error = suggestions.isEmpty
            ? 'No matching address was found. Refine the address and try again.'
            : null;
      });
    } catch (error) {
      if (!mounted ||
          request != _searchRequest ||
          widget.account?.active == false) {
        return;
      }
      setState(() {
        _searching = false;
        _suggestions = const <AddressSuggestion>[];
        _signInUrl =
            error is PortalAuthenticationException ? error.signInUrl : null;
        _error = _messageFor(error);
      });
    }
  }

  bool _shouldAutoSelectJobAddress(
    String query,
    List<AddressSuggestion> suggestions,
  ) =>
      widget.autoSelectJobAddress &&
      _selectedAddress == null &&
      query == widget.address.trim() &&
      suggestions.length == 1;

  Future<void> _selectAddress(AddressSuggestion suggestion) async {
    if (widget.account?.active == false) return;
    _searchDebounce?.cancel();
    final request = ++_searchRequest;
    final sessionToken = _sessionToken;
    setState(() {
      _selecting = true;
      _searching = false;
      _error = null;
      _signInUrl = null;
    });
    try {
      final selection = await _addressService.select(
        suggestion,
        sessionToken: sessionToken,
      );
      if (!mounted ||
          request != _searchRequest ||
          widget.account?.active == false) {
        return;
      }
      setState(() {
        _selecting = false;
        _selectedAddress = selection;
        _suggestions = const <AddressSuggestion>[];
        _sessionToken = _newSessionToken();
        _addressController.text = selection.standardizedAddress;
        _error = selection.coordinate == null
            ? 'This standardized address does not include a mappable location.'
            : null;
      });
    } catch (error) {
      if (!mounted ||
          request != _searchRequest ||
          widget.account?.active == false) {
        return;
      }
      setState(() {
        _selecting = false;
        _signInUrl =
            error is PortalAuthenticationException ? error.signInUrl : null;
        _error = _messageFor(error);
      });
    }
  }

  MeasurementResult get _measurement => MeasurementService.measureTrace(
        TraceGeometry(
          id: 'preview',
          label: widget.traceLabel,
          geoPoints: _points,
          canvasPoints: const [],
        ),
        status: MeasurementAccuracyStatus.estimated,
      );

  GeoPoint? _centerFor(List<GeoPoint> points) {
    if (points.isEmpty) return null;
    final latitude = points.fold<double>(
          0,
          (total, point) => total + point.latitude,
        ) /
        points.length;
    final longitude = points.fold<double>(
          0,
          (total, point) => total + point.longitude,
        ) /
        points.length;
    return GeoPoint(latitude: latitude, longitude: longitude);
  }

  // Reuse the imagery transfer's affine mapping for newly captured imagery
  // and deductions when main preserves an existing canvas frame.
  List<GraphPoint>? _reframeCanvasPoints(
    List<GraphPoint> points,
    List<GraphPoint> from,
    List<GraphPoint> to,
  ) {
    if (from.length < 3 || from.length != to.length) return null;
    var anchor = -1;
    for (var i = 2; i < from.length; i++) {
      final u = from[1].offset - from[0].offset;
      final v = from[i].offset - from[0].offset;
      if ((u.dx * v.dy - u.dy * v.dx).abs() > .0001) {
        anchor = i;
        break;
      }
    }
    if (anchor < 0) return null;
    final u = from[1].offset - from[0].offset;
    final v = from[anchor].offset - from[0].offset;
    final determinant = u.dx * v.dy - u.dy * v.dx;
    return points.map((point) {
      final d = point.offset - from[0].offset;
      final a = (d.dx * v.dy - d.dy * v.dx) / determinant;
      final b = (u.dx * d.dy - u.dy * d.dx) / determinant;
      return GraphPoint.fromOffset(
        to[0].offset +
            (to[1].offset - to[0].offset) * a +
            (to[anchor].offset - to[0].offset) * b,
      );
    }).toList();
  }

  Future<void> _finish() async {
    if (_saving || widget.account?.active == false || _points.length < 3) {
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final validation = TraceAreaService.validate(_preview);
    if (validation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validation)));
      return;
    }
    final operation = TraceImageryCancellation();
    setState(() {
      _saving = true;
      _activeTransfer = operation;
      _transferProgress = null;
    });
    try {
      final original = widget.initialTrace;
      final scale = original?.metersPerCanvasUnit;
      final unchanged =
          original != null &&
          original.geoPoints.length == _points.length &&
          List.generate(
            _points.length,
            (i) =>
                original.geoPoints[i].latitude == _points[i].latitude &&
                original.geoPoints[i].longitude == _points[i].longitude,
          ).every((v) => v);
      // Preserve the calibration fix from main, including moved/rotated frames.
      final preserveFrame =
          original != null &&
          unchanged &&
          original.canvasPoints.length == _points.length &&
          scale != null &&
          scale.isFinite &&
          scale > 0;
      final projection = preserveFrame
          ? TraceProjectionResult(
              canvasPoints: List.of(original.canvasPoints),
              metersPerCanvasUnit: scale,
            )
          : TraceProjectionService.projectToCanvas(
              _points,
              canvasSize: widget.canvasSize,
              metersPerCanvasUnit: widget.metersPerCanvasUnit,
            );
      final canonicalFrame = preserveFrame
          ? TraceProjectionService.projectToCanvas(
              _points,
              canvasSize: widget.canvasSize,
              metersPerCanvasUnit: projection.metersPerCanvasUnit,
            ).canvasPoints
          : projection.canvasPoints;
      List<GraphPoint> projectInFrame(List<GeoPoint> points) {
        final canonical = TraceProjectionService.projectToCanvas(
          points,
          canvasSize: widget.canvasSize,
          referencePoints: _points,
          metersPerCanvasUnit: projection.metersPerCanvasUnit,
        ).canvasPoints;
        return preserveFrame
            ? _reframeCanvasPoints(
                    canonical,
                    canonicalFrame,
                    projection.canvasPoints,
                  ) ??
                  (throw StateError('Cannot align the saved trace frame'))
            : canonical;
      }

      TraceImagery? imagery;
      if (_includeImagery) {
        if (unchanged && original.imagery != null) {
          if (preserveFrame) {
            imagery = original.imagery;
          } else {
            final corners = _reframeCanvasPoints(
              original.imagery!.corners,
              original.canvasPoints,
              projection.canvasPoints,
            );
            if (corners != null) {
              imagery = original.imagery!.copyWith(corners: corners);
            }
          }
        }
        if (imagery == null) {
          final west = _points.map((p) => p.longitude).reduce(min),
              east = _points.map((p) => p.longitude).reduce(max);
          final north = _points.map((p) => p.latitude).reduce(max),
              south = _points.map((p) => p.latitude).reduce(min);
          final dx = max((east - west) * 0.04, 0.00001),
              dy = max((north - south) * 0.04, 0.00001);
          final corners = [
            GeoPoint(latitude: north + dy, longitude: west - dx),
            GeoPoint(latitude: north + dy, longitude: east + dx),
            GeoPoint(latitude: south - dy, longitude: west - dx),
          ];
          final captured = await Future.any<TraceImagery>([
            widget.imageryService.capture(
              corners: corners,
              canvasCorners: projectInFrame(corners),
              cancellation: operation,
              onProgress: (progress) {
                if (mounted && identical(_activeTransfer, operation)) {
                  setState(() => _transferProgress = progress);
                }
              },
            ),
            operation.whenCancelled.then<TraceImagery>(
              (_) => throw const TraceImageryCancelledException(),
            ),
          ]);
          await Future.any([
            TraceImageryCache.instance
                .load(captured)
                .timeout(const Duration(seconds: 8)),
            operation.whenCancelled.then<void>(
              (_) => throw const TraceImageryCancelledException(),
            ),
          ]);
          imagery = captured;
        }
      }
      if (!mounted ||
          operation.isCancelled ||
          !identical(_activeTransfer, operation) ||
          widget.account?.active == false) {
        return;
      }
      Navigator.pop(
        context,
        TraceGeometry(
          id: widget.initialTrace?.id ?? newGraphId(),
          label: widget.initialTrace?.label ?? widget.traceLabel,
          address:
              _selectedAddress?.standardizedAddress ??
              ((widget.initialTrace?.address.trim().isNotEmpty ?? false)
                  ? widget.initialTrace!.address
                  : widget.address.trim()),
          geoPoints: List<GeoPoint>.of(_points),
          canvasPoints: projection.canvasPoints,
          metersPerCanvasUnit: projection.metersPerCanvasUnit,
          imagery: imagery,
          exclusions: [
            for (final e in _exclusions)
              e.copyWith(canvasPoints: projectInFrame(e.geoPoints)),
          ],
        ),
      );
    } catch (error) {
      if (operation.isCancelled || !identical(_activeTransfer, operation)) {
        return;
      }
      debugPrint('Satellite transfer failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            action: SnackBarAction(label: 'Retry', onPressed: _finish),
            content: Text(
              error is TimeoutException
                  ? 'Satellite transfer timed out. Your boundary and excluded areas are unchanged. Retry or turn off Include satellite imagery to save outlines.'
                  : 'Satellite transfer failed. Retry or turn off Include satellite imagery to save outlines.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && identical(_activeTransfer, operation)) {
        setState(() {
          _saving = false;
          _activeTransfer = null;
          _transferProgress = null;
        });
      }
    }
  }

  void _cancelTransfer() {
    _activeTransfer?.cancel();
    setState(() {
      _activeTransfer = null;
      _saving = false;
      _transferProgress = null;
    });
  }
  Future<void> _addExclusion() async {
    var areaLabel = 'Excluded area ${_exclusions.length + 1}';
    final label = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Exclude an area'),
                content: TextFormField(
                    initialValue: areaLabel,
                    onChanged: (v) => areaLabel = v,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Home, building, driveway…')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, areaLabel.trim()),
                      child: const Text('Trace area'))
                ]));
    if (!mounted || label == null || label.isEmpty) return;
    setState(() {
      _exclusions.add(TraceGeometry(
          id: newGraphId(),
          label: label,
          geoPoints: [],
          canvasPoints: const []));
      _activeExclusion = _exclusions.length - 1;
    });
  }

  List<Widget> _areaChips() => [
        ChoiceChip(
            label: const Text('Yard boundary'),
            selected: _activeExclusion == null,
            onSelected: _saving
                ? null
                : (_) => setState(() => _activeExclusion = null)),
        for (var i = 0; i < _exclusions.length; i++)
          InputChip(
              label: Text(_exclusions[i].label),
              selected: _activeExclusion == i,
              onPressed:
                  _saving ? null : () => setState(() => _activeExclusion = i),
              onDeleted: _saving
                  ? null
                  : () => setState(() {
                        _exclusions.removeAt(i);
                        _activeExclusion = null;
                      })),
      ];

  Widget _buildAreaControls({bool compact = false}) {
    if (compact) {
      return Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final chip in _areaChips())
                Padding(padding: const EdgeInsets.only(right: 6), child: chip),
            ]),
          ),
        ),
        IconButton(
            key: const ValueKey('add-trace-exclusion'),
            tooltip: 'Exclude area',
            onPressed: _saving || _points.length < 3 ? null : _addExclusion,
            icon: const Icon(Icons.add)),
        PopupMenuButton<String>(
            key: const ValueKey('trace-options'),
            tooltip: 'Trace options',
            enabled: !_saving,
            icon: Icon(_includeImagery ? Icons.satellite_alt : Icons.tune,
                color: _includeImagery
                    ? Theme.of(context).colorScheme.primary
                    : null),
            onSelected: (value) {
              if (value == 'imagery') {
                setState(() => _includeImagery = !_includeImagery);
              } else {
                _showTraceHelp();
              }
            },
            itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                      key: const ValueKey('include-trace-imagery'),
                      value: 'imagery',
                      checked: _includeImagery,
                      child: const Text('Include satellite imagery')),
                  const PopupMenuItem(value: 'help', child: Text('Trace help')),
                ]),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 4, children: [
        ..._areaChips(),
        TextButton.icon(
            key: const ValueKey('add-trace-exclusion'),
            onPressed: _saving || _points.length < 3 ? null : _addExclusion,
            icon: const Icon(Icons.add),
            label: const Text('Exclude area')),
      ]),
      CheckboxListTile(
          key: const ValueKey('include-trace-imagery'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Include satellite imagery in graph and exports'),
          value: _includeImagery,
          onChanged:
              _saving ? null : (v) => setState(() => _includeImagery = v!)),
      const Text(
          'Acreage is estimated from your traced boundary and exclusions.',
          style: TextStyle(fontSize: 12)),
    ]);
  }

  void _showTraceHelp() {
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Trace help'),
              content: SingleChildScrollView(
                  child: Text(
                      '${_activeExclusion == null ? 'Tap the yard boundary corners. Drag numbered points to refine the outline.' : 'Trace ${_exclusions[_activeExclusion!].label}. Keep it inside the yard boundary and separate from other exclusions.'}\n\n'
                      'Use + to exclude a home, building, or other area. Select a chip to edit that outline, or its × to remove an exclusion.\n\n'
                      'Trace options lets you include satellite imagery in the saved graph and exports.\n\n'
                      'Acreage is estimated from your traced boundary and exclusions.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.account?.active == false) {
      return Scaffold(
          appBar: AppBar(title: const Text('Sign in required')),
          body: const Center(
              child: Text(
                  'Sign in to the original account to access this trace. Recovery remains stored on this device.')));
    }
    final measurement = _measurement;
    final editingTrace = widget.initialTrace != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          editingTrace
              ? 'Edit ${widget.initialTrace!.label}'
              : 'New Satellite Trace',
        ),
        actions: [
          IconButton(
            tooltip: 'Undo last trace point',
            onPressed: _saving || _activePoints.isEmpty
                ? null
                : () => setState(() => _activePoints.removeLast()),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Clear trace',
            onPressed: _saving || _activePoints.isEmpty
                ? null
                : () => setState(() => _activePoints.clear()),
            icon: const Icon(Icons.delete_outline),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 600 || constraints.maxHeight < 430;
        return Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.5,
              ),
              child: SingleChildScrollView(
                  child: _buildAddressSearch(compact: compact)),
            ),
            if (_signInUrl != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    const Text(
                        'Sign in in a separate tab, then return and retry. Your trace stays open.'),
                    TextButton.icon(
                      onPressed: () => (widget.onPortalSignIn ??
                          openPortalSignIn)(_signInUrl!),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Sign in to OpsBrain'),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildMapBody(compact: compact)),
            Material(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 18,
                        runSpacing: 4,
                        children: [
                          Text('${_activePoints.length} points'),
                          Text(MeasurementFormat.linearFeet(
                            measurement.linearFeet,
                          )),
                          Text(MeasurementFormat.squareFeet(
                            measurement.squareFeet,
                          )),
                          Text(
                              'Total: ${MeasurementFormat.acres(measurement.acres)}'),
                          Text(
                              'Excluded: ${MeasurementFormat.acres(TraceAreaService.excludedSquareMeters(_preview) / 4046.8564224)}'),
                          Text(
                              'Net yard: ${MeasurementFormat.acres(TraceAreaService.netSquareMeters(_preview) / 4046.8564224)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_saving) ...[
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _transferProgress?.message ?? 'Preparing image…',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        FilledButton.icon(
                          key: const ValueKey('finish-trace-button'),
                          onPressed: _saving
                              ? _cancelTransfer
                              : _points.length >= 3
                              ? _finish
                              : null,
                          icon: _saving
                              ? const ExcludeSemantics(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(
                            _saving
                                ? 'Cancel transfer'
                                : editingTrace
                                ? 'Save Trace'
                                : 'Finish Trace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildAddressSearch({bool compact = false}) {
    final selection = _selectedAddress;
    return Material(
      elevation: 2,
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
            : const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact && widget.address.trim().isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 18),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Map opens at this job address. Change it only for a different property.',
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('trace-address-field'),
                    enabled: !_saving,
                    controller: _addressController,
                    onChanged: _onAddressChanged,
                    onSubmitted: (_) =>
                        _scheduleSuggestionSearch(immediate: true),
                    decoration: InputDecoration(
                      isDense: compact,
                      contentPadding: compact
                          ? const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10)
                          : null,
                      labelText: compact ? null : 'Location Address',
                      hintText: compact
                          ? 'Location address'
                          : 'Use this job address or choose another property',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      prefixIconConstraints: compact
                          ? const BoxConstraints(minWidth: 40, minHeight: 44)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (compact)
                  IconButton.filled(
                    tooltip: 'Search',
                    onPressed: _saving || _initializingMap || _selecting
                        ? null
                        : () => _scheduleSuggestionSearch(immediate: true),
                    icon: const Icon(Icons.search),
                  )
                else
                  FilledButton.icon(
                    onPressed: _saving || _initializingMap || _selecting
                        ? null
                        : () => _scheduleSuggestionSearch(immediate: true),
                    icon: const Icon(Icons.search),
                    label: const Text('Search'),
                  ),
              ],
            ),
            if (_searching || _selecting)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Semantics(
                key: const ValueKey('trace-workspace-error'),
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            if (_suggestions.isNotEmpty) _buildSuggestions(),
            if (selection != null) _buildAddressQuality(selection),
            _buildAreaControls(compact: compact),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return Semantics(
      label: 'Address suggestions',
      child: Card(
        key: const ValueKey('trace-address-suggestions'),
        margin: const EdgeInsets.only(top: 8),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final suggestion in _suggestions)
              ListTile(
                key: ValueKey('trace-address-suggestion-${suggestion.id}'),
                leading: const Icon(Icons.location_on_outlined),
                title: Text(suggestion.primaryText),
                subtitle: suggestion.secondaryText == null
                    ? null
                    : Text(suggestion.secondaryText!),
                onTap: _saving || _selecting
                    ? null
                    : () => _selectAddress(suggestion),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: widget.addressAttribution ?? const _GoogleAttribution(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressQuality(AddressSelection selection) {
    final quality = selection.quality;
    final qualityLabel = quality.isPropertyLevel
        ? 'Property-level location'
        : 'Approximate location (${_displayGranularity(quality.geocodeGranularity)})';
    return Semantics(
      label: 'Selected address quality: $qualityLabel',
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Icon(
              quality.isPropertyLevel ? Icons.verified : Icons.info_outline,
              color: quality.isPropertyLevel ? Colors.green.shade700 : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                quality.requiresReview
                    ? '$qualityLabel. Review the address before tracing.'
                    : qualityLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapBody({bool compact = false}) {
    if (_initializingMap) {
      return const Center(child: CircularProgressIndicator());
    }
    // A saved trace already has geographic points. Use their center while an
    // optional job-address lookup is pending or unavailable, so reopening a
    // trace never leaves the editor on an indefinite searching screen.
    final center = _selectedAddress?.coordinate ?? _savedTraceCenter;
    if (center == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined, size: 54),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Finding the job address…',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'If needed, edit the address and choose a result. NC OneMap '
                  'aerial imagery remains the tracing map.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: _provider.buildMap(
            center: center,
            selectedAddress: center,
            points: _activePoints,
            referencePolygons: [
              if (_activeExclusion != null) _points,
              for (var i = 0; i < _exclusions.length; i++)
                if (i != _activeExclusion) _exclusions[i].geoPoints
            ],
            onMapTap: (point) {
              if (!_saving) setState(() => _activePoints.add(point));
            },
            onVertexMoved: (index, point) => setState(() {
              if (!_saving && index >= 0 && index < _activePoints.length) {
                _activePoints[index] = point;
              }
            }),
          ),
        ),
        if (compact)
          Positioned(
            left: 8,
            top: 8,
            child: Card(
                child: IconButton(
              tooltip: 'Trace help',
              onPressed: _showTraceHelp,
              icon: const Icon(Icons.help_outline),
            )),
          )
        else
          Positioned(
            left: 12,
            right: 64,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _activeExclusion == null
                      ? 'Tap the yard boundary corners. Drag numbered points to refine, then exclude buildings or other areas.'
                      : 'Trace ${_exclusions[_activeExclusion!].label}. Keep it inside the yard boundary and separate from other exclusions.',
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _newSessionToken() {
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    return List<String>.generate(
      30,
      (_) => characters[_random.nextInt(characters.length)],
      growable: false,
    ).join();
  }

  String _messageFor(Object error) => error.toString().replaceFirst(
        RegExp(r'^Exception:\\s*'),
        '',
      );

  String _displayGranularity(String granularity) =>
      granularity.toLowerCase().replaceAll('_', ' ').replaceFirstMapped(
            RegExp(r'^.'),
            (match) => match.group(0)!.toUpperCase(),
          );
}

class _GoogleAttribution extends StatelessWidget {
  const _GoogleAttribution();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Powered by', style: TextStyle(fontSize: 11)),
        const SizedBox(width: 4),
        Image.network(
          'https://maps.gstatic.com/mapfiles/api-3/images/powered-by-google-on-white3.png',
          width: 120,
          height: 14,
          errorBuilder: (context, error, stackTrace) => const Text(
            'Google',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
