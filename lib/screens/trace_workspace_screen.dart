import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/graph_document.dart';
import '../services/cloud_drafts/graph_draft_service.dart';
import '../models/trace_geometry.dart';
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
    this.onPortalSignIn,
    super.key,
  });

  final GraphDraftAccount? account;
  final String address;
  final Size canvasSize;
  final String traceLabel;
  final TraceMapProvider? provider;
  final AddressSuggestionService? addressService;
  final TraceGeometry? initialTrace;
  final bool autoSelectJobAddress;
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
    _savedTraceCenter = _centerFor(_points);
    _sessionToken = _newSessionToken();
    _initializeWorkspace();
  }

  void _accountChanged() {
    if (widget.account?.active == false) {
      _searchDebounce?.cancel();
      ++_searchRequest;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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
          widget.account?.active == false) return;
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
          widget.account?.active == false) return;
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
          widget.account?.active == false) return;
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
          widget.account?.active == false) return;
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

  void _finish() {
    if (widget.account?.active == false) return;
    if (_points.length < 3) return;
    final projection = TraceProjectionService.projectToCanvas(
      _points,
      canvasSize: widget.canvasSize,
    );
    Navigator.pop(
      context,
      TraceGeometry(
        id: widget.initialTrace?.id ?? newGraphId(),
        label: widget.initialTrace?.label ?? widget.traceLabel,
        address: _selectedAddress?.standardizedAddress ??
            ((widget.initialTrace?.address.trim().isNotEmpty ?? false)
                ? widget.initialTrace!.address
                : widget.address.trim()),
        geoPoints: List<GeoPoint>.of(_points),
        canvasPoints: projection.canvasPoints,
        metersPerCanvasUnit: projection.metersPerCanvasUnit,
      ),
    );
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
            onPressed: _points.isEmpty
                ? null
                : () => setState(() => _points.removeLast()),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Clear trace',
            onPressed:
                _points.isEmpty ? null : () => setState(() => _points.clear()),
            icon: const Icon(Icons.delete_outline),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
          builder: (context, constraints) => Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.5,
                    ),
                    child: SingleChildScrollView(child: _buildAddressSearch()),
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
                  Expanded(child: _buildMapBody()),
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
                                Text('${_points.length} points'),
                                Text(MeasurementFormat.linearFeet(
                                  measurement.linearFeet,
                                )),
                                Text(MeasurementFormat.squareFeet(
                                  measurement.squareFeet,
                                )),
                                Text(
                                    MeasurementFormat.acres(measurement.acres)),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            key: const ValueKey('finish-trace-button'),
                            onPressed: _points.length >= 3 ? _finish : null,
                            icon: const Icon(Icons.check),
                            label: Text(
                                editingTrace ? 'Save Trace' : 'Finish Trace'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )),
    );
  }

  Widget _buildAddressSearch() {
    final selection = _selectedAddress;
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.address.trim().isNotEmpty)
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
                    controller: _addressController,
                    onChanged: _onAddressChanged,
                    onSubmitted: (_) =>
                        _scheduleSuggestionSearch(immediate: true),
                    decoration: const InputDecoration(
                      labelText: 'Location Address',
                      hintText:
                          'Use this job address or choose another property',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _initializingMap || _selecting
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
            if (_suggestions.isNotEmpty) _buildSuggestions(),
            if (selection != null) _buildAddressQuality(selection),
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
                onTap: _selecting ? null : () => _selectAddress(suggestion),
              ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: _GoogleAttribution(),
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

  Widget _buildMapBody() {
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
            points: _points,
            onMapTap: (point) => setState(() => _points.add(point)),
            onVertexMoved: (index, point) => setState(() {
              if (index >= 0 && index < _points.length) {
                _points[index] = point;
              }
            }),
          ),
        ),
        const Positioned(
          left: 12,
          right: 64,
          top: 12,
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                'Zoom to the structure, tap each corner, then drag a numbered point to refine it.',
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
