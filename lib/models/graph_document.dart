import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'freehand_stroke.dart';
import 'graph_annotation.dart';
import 'graph_point.dart';
import 'graph_shape.dart';
import 'job.dart';
import 'wall_segment.dart';
import 'trace_geometry.dart';

/// The durable, serializable source of truth for one inspection graph.
///
/// UI-only state such as the selected tool and current zoom deliberately stays
/// in the editor. Everything that belongs in a saved inspection lives here.
class GraphDocument extends ChangeNotifier {
  GraphDocument({
    String? id,
    required this.customer,
    List<WallSegment> wallSegments = const <WallSegment>[],
    List<GraphAnnotation> annotations = const <GraphAnnotation>[],
    List<GraphShape> shapes = const <GraphShape>[],
    List<FreehandStroke> freehandStrokes = const <FreehandStroke>[],
    Map<String, GraphLayerState>? layers,
    List<GraphAttachment> attachments = const <GraphAttachment>[],
    List<TraceGeometry> traces = const <TraceGeometry>[],
    MeasurementCalibration? measurementCalibration,
    Map<String, Object?> metadata = const <String, Object?>{},
    Map<String, Object?> extraProperties = const <String, Object?>{},
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? newGraphId(),
        _wallSegments = List<WallSegment>.of(wallSegments),
        _annotations = List<GraphAnnotation>.of(annotations),
        _shapes = List<GraphShape>.of(shapes),
        _freehandStrokes = List<FreehandStroke>.of(freehandStrokes),
        _layers = <String, GraphLayerState>{
          ...defaultLayers,
          ...?layers,
        },
        _attachments = List<GraphAttachment>.of(attachments),
        _traces = List<TraceGeometry>.of(traces),
        _measurementCalibration =
            measurementCalibration ?? MeasurementCalibration.legacy(),
        _metadata = Map<String, Object?>.of(metadata),
        _extraProperties = Map<String, Object?>.of(extraProperties),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  factory GraphDocument.forJob(Job job) {
    return GraphDocument(
      id: job.id,
      customer: GraphCustomerInfo.fromJob(job),
      createdAt: job.createdDate,
    );
  }

  /// "+ New w/ Existing Structure" (item 7 of the production pass): starts
  /// a brand new, independent graph that reuses only the structural
  /// wall/shape geometry already drawn on [source] -- the physical layout
  /// of a building rarely changes between visits, so retracing it for
  /// every follow-up inspection is pure busywork.
  ///
  /// Deliberately NOT copied: annotations (inspection/treatment markers,
  /// notes, photos), attachments, map traces, measurement calibration, and
  /// metadata (including the photo-numbering counter) -- those all belong
  /// to one specific inspection visit and must start clean. Freehand
  /// strokes are treated the same way (as markup, not structure) and are
  /// also excluded.
  ///
  /// The new document gets its own fresh id (via [newGraphId]) and its own
  /// fresh createdAt/updatedAt ("now"); [source] itself and anything
  /// already saved under its id/key are left completely untouched -- this
  /// is a pure duplication, never an in-place overwrite of the original.
  factory GraphDocument.duplicateStructureFrom(GraphDocument source) {
    return GraphDocument(
      customer: source.customer,
      wallSegments: source.wallSegments,
      shapes: source.shapes,
    );
  }

  /// "Save As New" recovery (items 10 and 11 of the production pass):
  /// produces a full, independent copy of [source] -- every graph object,
  /// attachment, trace, calibration, and metadata entry -- but with a
  /// fresh id/createdAt/updatedAt, so it can be saved to Ops Brain as a
  /// brand new file without disturbing whatever [source] was previously
  /// saved as (which may have been edited concurrently, renamed, or
  /// deleted out from under this session).
  factory GraphDocument.withNewIdentity(GraphDocument source) {
    return GraphDocument(
      customer: source.customer,
      wallSegments: source.wallSegments,
      annotations: source.annotations,
      shapes: source.shapes,
      freehandStrokes: source.freehandStrokes,
      layers: source.layers,
      attachments: source.attachments,
      traces: source.traces,
      measurementCalibration: source.measurementCalibration,
      metadata: source.metadata,
      extraProperties: source.extraProperties,
    ).._serializationSource = (jsonDecode(jsonEncode(source.toJson())) as Map).cast<String, Object?>();
  }

  /// Reads both the document format and the original flat graph payload.
  factory GraphDocument.fromJson(Map<String, Object?> json) {
    final graphObjects = _map(json['graphObjects']);
    final job = _map(json['job']);
    final customerJson = _map(json['customer']);
    final objectSource = graphObjects.isEmpty ? json : graphObjects;

    return GraphDocument(
      id: _string(json['id']).isEmpty ? null : _string(json['id']),
      customer: GraphCustomerInfo.fromJson(
        customerJson.isNotEmpty ? customerJson : job,
      ),
      wallSegments: _list(objectSource['wallSegments'])
          .map((value) => _wallSegmentFromJson(_map(value)))
          .toList(),
      annotations: _list(objectSource['annotations'])
          .map((value) => _annotationFromJson(_map(value)))
          .toList(),
      shapes: _list(objectSource['shapes'])
          .map((value) => _shapeFromJson(_map(value)))
          .toList(),
      freehandStrokes: _list(objectSource['freehandStrokes'])
          .map((value) => _freehandFromJson(_map(value)))
          .toList(),
      layers: _migrateLayers(_map(json['layers'])).map(
        (key, value) => MapEntry(
          key,
          GraphLayerState.fromJson(_map(value)),
        ),
      ),
      attachments: _list(json['attachments'])
          .map((value) => GraphAttachment.fromJson(_map(value)))
          .toList(),
      traces: _list(json['traces'])
          .map((value) => TraceGeometry.fromJson(_map(value)))
          .toList(),
      measurementCalibration: _map(json['measurementCalibration']).isEmpty
          ? MeasurementCalibration.legacy()
          : MeasurementCalibration.fromJson(
              _map(json['measurementCalibration']),
            ),
      metadata: _map(json['metadata']),
      extraProperties: _unknownFields(json, const {
        'schemaVersion',
        'id',
        'customer',
        'job',
        'graphObjects',
        'wallSegments',
        'annotations',
        'shapes',
        'freehandStrokes',
        'layers',
        'attachments',
        'traces',
        'measurementCalibration',
        'metadata',
        'createdAt',
        'updatedAt',
      }),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    )
      .._serializationSource = (jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>()
      ..markClean();
  }

  static const int schemaVersion = 5;

  static const Map<String, GraphLayerState> defaultLayers = {
    'structure': GraphLayerState(),
    'shapes': GraphLayerState(),
    'inspections': GraphLayerState(),
    'treatment': GraphLayerState(),
    'photos': GraphLayerState(),
    'trace': GraphLayerState(visible: false),
  };

  final String id;
  GraphCustomerInfo customer;
  DateTime createdAt;
  DateTime updatedAt;

  List<WallSegment> _wallSegments;
  List<GraphAnnotation> _annotations;
  List<GraphShape> _shapes;
  List<FreehandStroke> _freehandStrokes;
  Map<String, GraphLayerState> _layers;
  List<GraphAttachment> _attachments;
  List<TraceGeometry> _traces;
  MeasurementCalibration _measurementCalibration;
  Map<String, Object?> _metadata;
  Map<String, Object?> _extraProperties;
  Map<String, Object?> _serializationSource = {};
  Map<String, Object?> get serializationState => (jsonDecode(jsonEncode(_serializationSource)) as Map).cast<String, Object?>();
  void restoreSerializationState(Map<String, Object?> snapshot) {
    _serializationSource = (jsonDecode(jsonEncode(snapshot)) as Map).cast<String, Object?>();
  }
  bool _isDirty = false;
  int _revision = 0;

  UnmodifiableListView<WallSegment> get wallSegments =>
      UnmodifiableListView(_wallSegments);
  UnmodifiableListView<GraphAnnotation> get annotations =>
      UnmodifiableListView(_annotations);
  UnmodifiableListView<GraphShape> get shapes => UnmodifiableListView(_shapes);
  UnmodifiableListView<FreehandStroke> get freehandStrokes =>
      UnmodifiableListView(_freehandStrokes);
  UnmodifiableMapView<String, GraphLayerState> get layers =>
      UnmodifiableMapView(_layers);
  UnmodifiableListView<GraphAttachment> get attachments =>
      UnmodifiableListView(_attachments);
  UnmodifiableListView<TraceGeometry> get traces =>
      UnmodifiableListView(_traces);
  MeasurementCalibration get measurementCalibration => _measurementCalibration;
  UnmodifiableMapView<String, Object?> get metadata =>
      UnmodifiableMapView(_metadata);
  UnmodifiableMapView<String, Object?> get extraProperties =>
      UnmodifiableMapView(_extraProperties);

  List<GraphAnnotation> get photos => _annotations
      .where((item) => item.kind == GraphAnnotationKind.photo)
      .toList(growable: false);
  List<GraphAnnotation> get notes => _annotations
      .where((item) => item.note.trim().isNotEmpty)
      .toList(growable: false);

  bool get isDirty => _isDirty;
  int get revision => _revision;

  int get nextPhotoNumber {
    final persisted = _metadata['nextPhotoNumber'];
    if (persisted is num && persisted.toInt() > 0) {
      return persisted.toInt();
    }
    var highest = 0;
    for (final annotation in photos) {
      final match = RegExp(r'\d+').firstMatch(annotation.label);
      final value = int.tryParse(match?.group(0) ?? '');
      if (value != null && value > highest) highest = value;
    }
    return highest + 1;
  }

  int reservePhotoNumber() {
    final value = nextPhotoNumber;
    _metadata = <String, Object?>{
      ..._metadata,
      'nextPhotoNumber': value + 1,
    };
    _changed();
    return value;
  }

  GraphLayerState layer(String id) => _layers[id] ?? const GraphLayerState();

  // Dirty-state no-op guards (item 16 of the production pass): none of the
  // domain model classes here (WallSegment, GraphAnnotation, GraphShape,
  // etc.) implement value equality, so a naive `value == current` check
  // would only catch identical object references. For the low-frequency,
  // dialog/action-driven mutators below we compare the existing
  // already-defined toJson() representations for deep, real-value equality
  // -- a call that hands back content identical to what's already stored
  // (e.g. a settings dialog cancelled without changes, or view-metadata
  // paths) is a genuine no-op and must not dirty the document, bump the
  // revision, or touch updatedAt.
  //
  // The structural mutators (replaceWallSegments/replaceAnnotations/
  // replaceShapes/replaceFreehandStrokes/replaceTraces) deliberately do NOT
  // get this deep-equality check: they're invoked on every pointer-move
  // frame while dragging an endpoint, annotation, or shape (see
  // _moveActiveTarget in graph_canvas_screen.dart), and a full JSON
  // encode-and-compare of a large structural list on every frame is a real
  // interactive-editing performance regression (benchmarked at over 1ms per
  // call for a few hundred elements) for a case that almost never actually
  // no-ops mid-drag. Those call sites are already gated by real user
  // gestures (drag/add/delete/undo-redo), not by cancel/view paths, so the
  // no-op risk there is negligible next to the perf cost.
  bool _sameJson(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

  void _remapSerializationRows<T>(String key, List<T> previous, List<T> next) {
    final objects = _serializationSource['graphObjects'];
    final source = objects is Map ? objects[key] : null;
    if (objects is Map && source is List) {
      final indexes = Map<T, int>.identity();
      for (var i = 0; i < previous.length; i++) { indexes[previous[i]] = i; }
      objects[key] = [for (var i = 0; i < next.length; i++)
        _serializationRow(source, indexes[next[i]] ?? (next.length == previous.length ? i : -1))];
    }
  }

  void replaceWallSegments(Iterable<WallSegment> value) {
    final next = List<WallSegment>.of(value);
    _remapSerializationRows('wallSegments', _wallSegments, next);
    _wallSegments = next;
    _changed();
  }

  void replaceAnnotations(Iterable<GraphAnnotation> value) {
    _annotations = List<GraphAnnotation>.of(value);
    _changed();
  }

  void replaceShapes(Iterable<GraphShape> value) {
    final next = List<GraphShape>.of(value);
    _remapSerializationRows('shapes', _shapes, next);
    _shapes = next;
    _changed();
  }

  void replaceFreehandStrokes(Iterable<FreehandStroke> value) {
    final next = List<FreehandStroke>.of(value);
    _remapSerializationRows('freehandStrokes', _freehandStrokes, next);
    _freehandStrokes = next;
    _changed();
  }

  void setLayer(String id, GraphLayerState value) {
    final current = _layers[id];
    if (current != null &&
        current.visible == value.visible &&
        current.locked == value.locked) {
      return;
    }
    _layers = <String, GraphLayerState>{..._layers, id: value};
    _changed();
  }

  void replaceAttachments(Iterable<GraphAttachment> value) {
    final next = List<GraphAttachment>.of(value);
    if (_sameJson(
      _attachments.map((item) => item.toJson()).toList(),
      next.map((item) => item.toJson()).toList(),
    )) {
      return;
    }
    _attachments = next;
    _changed();
  }

  void replaceTraces(Iterable<TraceGeometry> value) {
    // No deep-equality no-op guard here either, for the same interactive
    // per-frame-drag performance reason as the structural mutators above
    // (map-trace vertex dragging calls this on every pointer move).
    _traces = List<TraceGeometry>.of(value);
    _changed();
  }

  void setMeasurementCalibration(MeasurementCalibration value) {
    if (_sameJson(_measurementCalibration.toJson(), value.toJson())) {
      return;
    }
    _measurementCalibration = value;
    _changed();
  }

  void replaceMetadata(Map<String, Object?> value) {
    final next = Map<String, Object?>.of(value);
    if (_sameJson(_metadata, next)) {
      return;
    }
    _metadata = next;
    _changed();
  }

  void updateCustomer(GraphCustomerInfo value) {
    if (_sameJson(customer.toJson(), value.toJson())) {
      return;
    }
    customer = value;
    _changed();
  }

  void updateJob(Job job) {
    // Creation Date integrity (item 10 of the production pass): the
    // document's createdAt is set exactly once, at document creation, and
    // must never change afterward -- including when the underlying Job's
    // own date field is edited later (e.g. via the "edit job" flow in
    // home_screen.dart, which lets a user pick a different job date).
    // Previously this method unconditionally overwrote createdAt with
    // job.createdDate on every edit, silently rewriting the graph's real
    // Creation Date. Only customer/job identity fields are synced here now.
    final next = GraphCustomerInfo.fromJob(job);
    if (_sameJson(customer.toJson(), next.toJson())) {
      return;
    }
    customer = next;
    _changed();
  }

  void markClean() {
    _isDirty = false;
    notifyListeners();
  }

  Map<String, Object?> toJson() {
    final result = <String, Object?>{
        ..._extraProperties,
        'id': id,
        'schemaVersion': schemaVersion,
        'customer': customer.toJson(),
        'graphObjects': <String, Object?>{
          'wallSegments': _wallSegments.map(_wallSegmentToJson).toList(),
          'annotations': _annotations.map(_annotationToJson).toList(),
          'shapes': _shapes.map(_shapeToJson).toList(),
          'freehandStrokes': _freehandStrokes.map(_freehandToJson).toList(),
        },
        'layers': _layers.map((key, value) => MapEntry(key, value.toJson())),
        'attachments': _attachments.map((item) => item.toJson()).toList(),
        'traces': _traces.map((item) => item.toJson()).toList(),
        'measurementCalibration': _measurementCalibration.toJson(),
        'metadata': _metadata,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
    for (final key in ['customer', 'attachments', 'graphObjects', 'layers', 'traces', 'measurementCalibration']) {
      result[key] = _preserveNestedFields(_serializationSource[key], result[key]);
    }
    return result;
  }

  void _changed() {
    _isDirty = true;
    _revision += 1;
    updatedAt = DateTime.now();
    notifyListeners();
  }
}

class GraphCustomerInfo {
  const GraphCustomerInfo({
    required this.name,
    required this.serviceAddress,
    required this.pestPacLocationNumber,
    required this.pestPacBillToNumber,
    required this.serviceType,
    required this.createdBy,
    this.intakeDetails = const {},
  });

  factory GraphCustomerInfo.fromJob(Job job) => GraphCustomerInfo(
        name: job.customerName,
        serviceAddress: job.serviceAddress,
        pestPacLocationNumber: job.pestPacLocationNumber,
        pestPacBillToNumber: job.pestPacBillToNumber,
        serviceType: job.serviceType,
        createdBy: job.createdBy,
        intakeDetails: Map<String, String>.of(job.intakeDetails),
      );

  factory GraphCustomerInfo.fromJson(Map<String, Object?> json) {
    final legacyAccountNumber = _string(json['pestPacAccountNumber']);

    return GraphCustomerInfo(
      name: _string(json['name'] ?? json['customerName']),
      serviceAddress: _string(json['serviceAddress']),
      pestPacLocationNumber: json.containsKey('pestPacLocationNumber')
          ? _string(json['pestPacLocationNumber'])
          : legacyAccountNumber,
      pestPacBillToNumber: _string(json['pestPacBillToNumber']),
      serviceType: _string(json['serviceType']),
      createdBy: _string(json['createdBy']),
      intakeDetails: (json['intakeDetails'] is Map)
          ? (json['intakeDetails'] as Map).map(
              (key, value) => MapEntry(key.toString(), value?.toString() ?? ''))
          : const {},
    );
  }

  final String name;
  final String serviceAddress;
  final String pestPacLocationNumber;
  final String pestPacBillToNumber;
  final String serviceType;
  final String createdBy;
  final Map<String, String> intakeDetails;

  String get displayName => name.trim().isEmpty ? 'Untitled Job' : name;

  Map<String, Object?> toJson() => {
        'name': name,
        'serviceAddress': serviceAddress,
        'pestPacLocationNumber': pestPacLocationNumber,
        'pestPacBillToNumber': pestPacBillToNumber,
        'pestPacAccountNumber': pestPacLocationNumber,
        'serviceType': serviceType,
        'createdBy': createdBy,
        'intakeDetails': intakeDetails,
      };
}

class GraphLayerState {
  const GraphLayerState({this.visible = true, this.locked = false});

  factory GraphLayerState.fromJson(Map<String, Object?> json) =>
      GraphLayerState(
        visible: json['visible'] as bool? ?? true,
        locked: json['locked'] as bool? ?? false,
      );

  final bool visible;
  final bool locked;

  GraphLayerState copyWith({bool? visible, bool? locked}) => GraphLayerState(
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
      );

  Map<String, Object?> toJson() => {'visible': visible, 'locked': locked};
}

class GraphAttachment {
  const GraphAttachment({
    required this.id,
    required this.name,
    this.annotationId = '',
    this.referenceLabel = '',
    this.mimeType = '',
    this.byteSize = 0,
    this.width = 0,
    this.height = 0,
    this.blobKey = '',
    this.thumbnailKey = '',
    this.uri,
  });

  factory GraphAttachment.fromJson(Map<String, Object?> json) =>
      GraphAttachment(
        id: _string(json['id']),
        name: _string(json['name']),
        annotationId: _string(json['annotationId']),
        referenceLabel: _string(json['referenceLabel']),
        mimeType: _string(json['mimeType']),
        byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        blobKey: _string(json['blobKey']).isEmpty
            ? _string(json['id'])
            : _string(json['blobKey']),
        thumbnailKey: json.containsKey('thumbnailKey')
            ? _string(json['thumbnailKey'])
            : '${_string(json['id'])}-thumb',
        uri: json['uri'] as String?,
      );

  final String id;
  final String name;
  final String annotationId;
  final String referenceLabel;
  final String mimeType;
  final int byteSize;
  final int width;
  final int height;
  final String blobKey;
  final String thumbnailKey;
  final String? uri;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'annotationId': annotationId,
        'referenceLabel': referenceLabel,
        'mimeType': mimeType,
        'byteSize': byteSize,
        'width': width,
        'height': height,
        'blobKey': blobKey,
        'thumbnailKey': thumbnailKey,
        'uri': uri,
      };
}

/// The three storable file "kinds" for a graph (item 9 of the production
/// pass): the editable `.bgraph` JSON document, and the two read-only
/// rendered export formats. Each carries its own filename suffix and
/// extension so [buildGraphFileName] can produce the exact same name for a
/// given kind regardless of whether it's being saved to Ops Brain or
/// exported locally.
enum GraphFileKind {
  bgraph('BGRAPH', 'bgraph'),
  pdfExport('PDFEXPORT', 'pdf'),
  pngExport('PNGEXPORT', 'png');

  const GraphFileKind(this.suffix, this.extension);

  final String suffix;
  final String extension;
}

/// Mirrors holloman-ops-brain's server-side `bugManGraphFileName()` /
/// `sanitizeBugManFileSegment()` / `formatBugManFileDate()` (see
/// functions/api/[[path]].js) exactly, so a graph filename is identical
/// whether it's built here on the client (for local exports) or recomputed
/// on the server when saving/uploading. Do not change this format without
/// updating the server-side implementation to match.
///
/// Uses [createdAt] -- the graph's original Creation Date, never
/// last-modified -- per item 9 of the production pass.
String buildGraphFileName(
  GraphCustomerInfo customer,
  DateTime createdAt,
  GraphFileKind kind,
) {
  final datePart = _formatBugManFileDate(createdAt);
  final segments = <String>[
    datePart,
    _sanitizeBugManFileSegment(customer.pestPacBillToNumber),
    _sanitizeBugManFileSegment(customer.name),
    _sanitizeBugManFileSegment(customer.serviceType),
    _sanitizeBugManFileSegment(customer.createdBy),
  ].where((segment) => segment.isNotEmpty).toList();
  segments.add(kind.suffix);
  return _safeFileName('${segments.join('-')}.${kind.extension}');
}

String _formatBugManFileDate(DateTime date) {
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  final yy = (date.year % 100).toString().padLeft(2, '0');
  return '$mm-$dd-$yy';
}

String _sanitizeBugManFileSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final hyphenated = trimmed.replaceAll(RegExp(r'\s+'), '-');
  final cleaned = hyphenated.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '');
  return cleaned
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

String _safeFileName(String value) {
  final trimmed = value.trim().isEmpty ? 'file' : value.trim();
  final cleaned = trimmed
      .replaceAll(RegExp(r'[\\/<>:"|?*\x00-\x1F]+'), '-')
      .replaceAll(RegExp(r'\s+'), ' ');
  final sliced = cleaned.length > 180 ? cleaned.substring(0, 180) : cleaned;
  return sliced.isEmpty ? 'file' : sliced;
}

String newGraphId() {
  final random = math.Random.secure();
  final suffix = List.generate(
    12,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
  return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
}

Map<String, Object?> _migrateLayers(Map<String, Object?> layers) {
  if (!layers.containsKey('findings')) {
    return layers;
  }
  final legacyFindings = layers['findings'];
  return <String, Object?>{
    ...layers,
    'inspections': layers['inspections'] ?? legacyFindings,
    'treatment': layers['treatment'] ?? legacyFindings,
  };
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, Object?>{};
}

Map<String, Object?> _unknownFields(
  Map<String, Object?> source,
  Set<String> knownKeys,
) =>
    Map<String, Object?>.fromEntries(
      source.entries.where((entry) => !knownKeys.contains(entry.key)),
    );

List<Object?> _list(Object? value) => value is List ? value : const [];
String _string(Object? value) => value?.toString() ?? '';
double _double(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : fallback;
int _color(Color value) => value.toARGB32();
Color _readColor(Object? value, Color fallback) =>
    value is num ? Color(value.toInt()) : fallback;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
T _enum<T extends Enum>(Iterable<T> values, Object? value, T fallback) =>
    values.cast<T?>().firstWhere(
          (item) => item?.name == value,
          orElse: () => fallback,
        ) ??
    fallback;

Map<String, Object?> _pointToJson(GraphPoint point) =>
    {'x': point.x, 'y': point.y};
GraphPoint _pointFromJson(Map<String, Object?> json) =>
    GraphPoint(x: _double(json['x']), y: _double(json['y']));

Map<String, Object?> _wallSegmentToJson(WallSegment item) => {
      'start': _pointToJson(item.start),
      'end': _pointToJson(item.end),
      'controlPoint':
          item.controlPoint == null ? null : _pointToJson(item.controlPoint!),
      'color': _color(item.color),
      'strokeWidth': item.strokeWidth,
      'pattern': item.pattern.name,
      'hasArrow': item.hasArrow,
    };
WallSegment _wallSegmentFromJson(Map<String, Object?> json) => WallSegment(
      start: _pointFromJson(_map(json['start'])),
      end: _pointFromJson(_map(json['end'])),
      controlPoint: json['controlPoint'] == null
          ? null
          : _pointFromJson(_map(json['controlPoint'])),
      color: _readColor(json['color'], const Color(0xFF214D38)),
      strokeWidth: _double(json['strokeWidth'], 5),
      pattern: _enum(LinePattern.values, json['pattern'], LinePattern.solid),
      hasArrow: json['hasArrow'] as bool? ?? false,
    );

Map<String, Object?> _annotationToJson(GraphAnnotation item) => {
      ...item.extraProperties,
      'id': item.id,
      'kind': item.kind.name,
      'point': _pointToJson(item.point),
      'label': item.label,
      'markerType': item.markerType.name,
      'color': item.color == null ? null : _color(item.color!),
      'size': item.size,
      'rotationDegrees': item.rotationDegrees,
      'note': item.note,
      'fontSize': item.fontSize,
      'bold': item.bold,
      'italic': item.italic,
      'textColor': _color(item.textColor),
      'backgroundColor': _color(item.backgroundColor),
      'borderColor': _color(item.borderColor),
      'attachmentIds': item.attachmentIds,
    };
GraphAnnotation _annotationFromJson(Map<String, Object?> json) =>
    GraphAnnotation(
      id: _string(json['id']).isEmpty ? newGraphId() : _string(json['id']),
      kind: _enum(
        GraphAnnotationKind.values,
        json['kind'],
        GraphAnnotationKind.marker,
      ),
      point: _pointFromJson(_map(json['point'])),
      label: _string(json['label']),
      markerType: _enum(
        GraphMarkerType.values,
        json['markerType'],
        GraphMarkerType.damage,
      ),
      color: json['color'] == null
          ? null
          : _readColor(json['color'], const Color(0xFFD33A2C)),
      size: _double(json['size'], 1),
      rotationDegrees: _double(json['rotationDegrees']),
      note: _string(json['note']),
      fontSize: _double(json['fontSize'], 16),
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      textColor: _readColor(json['textColor'], const Color(0xFF1C2B22)),
      backgroundColor:
          _readColor(json['backgroundColor'], const Color(0xFFFFF2B8)),
      borderColor: _readColor(json['borderColor'], const Color(0xFFC7A93C)),
      attachmentIds: _list(json['attachmentIds'])
          .map((value) => value.toString())
          .toList(),
      extraProperties: _unknownFields(json, const {
        'kind',
        'point',
        'label',
        'markerType',
        'color',
        'size',
        'rotationDegrees',
        'note',
        'fontSize',
        'bold',
        'italic',
        'textColor',
        'backgroundColor',
        'borderColor',
        'id',
        'attachmentIds',
      }),
    );

Map<String, Object?> _shapeToJson(GraphShape item) => {
      ...item.extraProperties,
      'name': item.name,
      'segmentIndexes': item.segmentIndexes,
      'fillColor': item.fillColor == null ? null : _color(item.fillColor!),
      'fillOpacity': item.fillOpacity,
      'borderColor': _color(item.borderColor),
      'borderWidth': item.borderWidth,
      'pattern': item.pattern.name,
      'closed': item.closed,
      'rotationDegrees': item.rotationDegrees,
      'preset': item.preset?.name,
      'text': item.text,
    };
GraphShape _shapeFromJson(Map<String, Object?> json) => GraphShape(
      name: _string(json['name']),
      segmentIndexes: _list(json['segmentIndexes'])
          .whereType<num>()
          .map((v) => v.toInt())
          .toList(),
      fillColor: json['fillColor'] == null
          ? null
          : _readColor(json['fillColor'], Colors.transparent),
      fillOpacity: _double(json['fillOpacity'], 0.3),
      borderColor: _readColor(json['borderColor'], const Color(0xFF214D38)),
      borderWidth: _double(json['borderWidth'], 3),
      pattern: _enum(
        GraphShapePattern.values,
        json['pattern'],
        GraphShapePattern.none,
      ),
      closed: json['closed'] as bool? ?? true,
      rotationDegrees: _double(json['rotationDegrees']),
      preset: json['preset'] == null
          ? null
          : _enum(
              GraphDrawingPreset.values,
              json['preset'],
              GraphDrawingPreset.mainStructure,
            ),
      text: _string(json['text']),
      extraProperties: _unknownFields(json, const {
        'name',
        'segmentIndexes',
        'fillColor',
        'fillOpacity',
        'borderColor',
        'borderWidth',
        'pattern',
        'closed',
        'rotationDegrees',
        'preset',
        'text',
      }),
    );

Map<String, Object?> _freehandToJson(FreehandStroke item) => {
      'points': item.points.map(_pointToJson).toList(),
      'color': _color(item.color),
      'strokeWidth': item.strokeWidth,
      'opacity': item.opacity,
    };
FreehandStroke _freehandFromJson(Map<String, Object?> json) => FreehandStroke(
      points: _list(json['points'])
          .map((value) => _pointFromJson(_map(value)))
          .toList(),
      color: _readColor(json['color'], const Color(0xFF1C2B22)),
      strokeWidth: _double(json['strokeWidth'], 4),
      opacity: _double(json['opacity'], 0.85),
    );

// Overlay modeled values while retaining future fields. Current lists determine
// membership: deleted objects are never resurrected. Stable IDs match attachments
// and annotations even after reorder; id-less geometry retains positional data.
Object? _preserveNestedFields(Object? source, Object? current) {
  if (source is Map && current is Map) {
    return <String, Object?>{
      for (final entry in source.entries) entry.key as String: entry.value,
      for (final entry in current.entries)
        entry.key as String: _preserveNestedFields(source[entry.key], entry.value),
    };
  }
  if (source is List && current is List) {
    return [for (var index = 0; index < current.length; index++)
      _preserveNestedFields(
        current[index] is Map && (current[index] as Map)['id'] != null
          ? source.whereType<Map>().where((item) => item['id'] == (current[index] as Map)['id']).firstOrNull
          : index < source.length ? source[index] : null,
        current[index])];
  }
  return current;
}

Object? _serializationRow(List source, int index) => index >= 0 && index < source.length ? source[index] : null;
