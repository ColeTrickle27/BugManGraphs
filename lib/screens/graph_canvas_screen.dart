import 'dart:math' as math;

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../editor/editor_interaction_controller.dart';
import '../models/graph_annotation.dart';
import '../models/marker_color_palette.dart';
import '../models/graph_document.dart';
import '../models/graph_marker_catalog.dart';
import '../models/freehand_stroke.dart';
import '../models/graph_point.dart';
import '../models/graph_shape.dart';
import '../models/job.dart';
import '../models/trace_geometry.dart';
import '../models/wall_segment.dart';
import 'trace_workspace_screen.dart';
import '../services/export_bounds_calculator.dart';
import '../services/bugman_portal_service_factory.dart';
import '../services/bugman_portal_service.dart';
import '../services/portal_sign_in.dart';
import '../services/graph_export_legend.dart';
import '../services/graph_image_export.dart';
import '../services/measurement_format.dart';
import '../services/measurement_service.dart';
import '../services/graph_pdf_export.dart';
import '../services/graph_photo_optimizer_factory.dart';
import '../services/graph_photo_service.dart';
import '../services/graph_photo_picker_factory.dart';
import '../services/graph_repository.dart';
import '../services/graph_repository_stub.dart';
import '../services/marker_defaults_store.dart';
import '../services/marker_defaults_store_factory.dart';
import '../services/sales_brain_bridge.dart';
import '../services/sales_brain_navigation.dart';
import '../services/trace_projection_service.dart';
import '../services/trace_workspace_defaults.dart';
import '../widgets/canvas_toolbar.dart';
import '../widgets/freehand_strokes_painter.dart';
import '../widgets/graph_annotations_painter.dart';
import '../widgets/graph_grid_painter.dart';
import '../widgets/graph_shapes_painter.dart';
import '../widgets/wall_segments_painter.dart';
import '../widgets/trace_geometry_painter.dart';

class GraphCanvasScreen extends StatefulWidget {
  const GraphCanvasScreen({
    this.job,
    this.document,
    this.repository,
    this.photoPicker,
    this.portalService,
    this.onPortalSignIn,
    this.portalKey,
    this.markerDefaultsStore,
    this.presentationMode = false,
    this.presentationMarkerIds = const <String>{},
    super.key,
  }) : assert(job != null || document != null);

  static const String routeName = '/graph-canvas';

  final Job? job;
  final GraphDocument? document;
  final GraphRepository? repository;
  final GraphPhotoPicker? photoPicker;
  final BugManPortalService? portalService;
  final ValueChanged<String>? onPortalSignIn;
  final String? portalKey;
  final MarkerDefaultsStore? markerDefaultsStore;
  final bool presentationMode;
  final Set<String> presentationMarkerIds;

  @override
  State<GraphCanvasScreen> createState() => _GraphCanvasScreenState();
}

class _GraphCanvasScreenState extends State<GraphCanvasScreen> {
  static const Size _canvasSize = Size(3600, 2600);
  static const double _endpointSnapDistance = 22;
  static const double _gridSnapSize = WallSegment.pixelsPerFoot;
  static const double _minimumWallLength = 6;
  static const double _tapMovementLimit = 10;
  static const Duration _doubleClickWindow = Duration(milliseconds: 360);
  static const double _angleSnapToleranceRadians = math.pi / 18;
  static const double _objectHitDistance = 14;
  static const double _handleHitDistance = 18;

  final FocusNode _editorFocusNode = FocusNode(debugLabel: 'Graph editor');
  bool _multiTouchPanning = false;
  final GlobalKey _canvasBoundaryKey = GlobalKey(debugLabel: 'Graph export');
  final GlobalKey _presentationBoundaryKey =
      GlobalKey(debugLabel: 'Customer graph export');
  void Function()? _stopPresentationExport;
  final GlobalKey _canvasViewportKey = GlobalKey(debugLabel: 'Graph viewport');
  final TransformationController _transformationController =
      TransformationController();
  // Not `late final`: "Save As New" recovery (items 10/11 of the
  // production pass) needs to swap in a fresh GraphDocument (via
  // GraphDocument.withNewIdentity) mid-session without tearing down and
  // rebuilding the whole editor. See _replaceDocumentWithNewIdentity().
  late GraphDocument _document;
  late final GraphRepository _repository;
  late final BugManPortalService _portalService;
  String? _portalKey;
  late final GraphPhotoPicker _photoPicker;
  final Map<String, Uint8List> _pendingPhotoBlobs = {};
  final Set<String> _deletedPhotoBlobKeys = {};
  late final EditorInteractionController _interaction;
  final List<_UndoEntry> _undoStack = <_UndoEntry>[];
  final List<_RedoEntry> _redoStack = <_RedoEntry>[];
  bool _applyingHistory = false;
  GraphPoint? _activeWallStart;
  GraphPoint? _activePathStartPoint;
  GraphPoint? _pendingCurveControlPoint;
  WallSegment? _previewSegment;
  int? _activePathStartSegmentIndex;
  _EditorSnapshot? _structureStartSnapshot;
  String _canvasStatus = 'Select selected: click an object';
  _Selection? _selection;
  bool _gridVisible = true;
  bool _snapToGrid = true;
  static const bool _snapToObjects = false;
  _SidePanelMode? _sidePanelMode;
  bool _layersCollapsed = true;
  bool _mainToolbarCollapsed = false;
  bool _quickToolbarCollapsed = false;
  List<CanvasToolbarAction> _quickToolbarActions = const [
    CanvasToolbarAction.tool(CanvasTool.select),
    CanvasToolbarAction.tool(CanvasTool.pan),
    CanvasToolbarAction.tool(CanvasTool.text),
    CanvasToolbarAction.preset(GraphDrawingPreset.mainStructure),
    CanvasToolbarAction.marker(GraphMarkerType.treatmentNote),
  ];
  String _scaleLabel = '1:1';
  Offset? _pointerDownPosition;
  _Selection? _pointerDownHitSelection;
  _Selection? _hoverSelection;
  double _pointerTravel = 0;
  int _activePointerCount = 0;
  GraphPoint? _pointerDownActiveWallStart;
  GraphPoint? _pointerDownActivePathStartPoint;
  int? _pointerDownActivePathStartSegmentIndex;
  DateTime? _lastTapTime;
  Offset? _lastTapSceneOffset;
  _DragTarget? _activeDragTarget;
  List<WallSegment>? _dragOriginalWallSegments;
  List<GraphAnnotation>? _dragOriginalAnnotations;
  List<GraphShape>? _dragOriginalShapes;
  List<FreehandStroke>? _dragOriginalFreehandStrokes;
  List<TraceGeometry>? _dragOriginalTraces;
  GraphPoint? _dragOriginalActiveWallStart;
  GraphPoint? _dragOriginalActivePathStartPoint;
  int? _dragOriginalActivePathStartSegmentIndex;
  bool _dragMoved = false;
  Offset? _shapeDrawStart;
  Offset? _shapeDrawCurrent;
  List<GraphPoint> _draftFreehandPoints = <GraphPoint>[];
  _ClipboardItem? _clipboardItem;
  bool _draggingLineTool = false;
  bool _lineDragStartedNewPath = false;
  bool _spacePanActive = false;
  GraphPoint? _treatmentCalloutTip;
  Offset? _treatmentCalloutBox;
  _CalloutKind? _activeCalloutKind;
  final TextEditingController _inlineTextController = TextEditingController();
  final FocusNode _inlineTextFocusNode = FocusNode();
  int? _inlineTextAnnotationIndex;
  GraphAnnotation? _inlineTextPreviousAnnotation;
  bool _inlineTextIsNew = false;
  bool _initialCanvasCentered = false;
  final Set<int> _shortcutPanPointers = <int>{};
  Color _selectedMarkerColor = GraphMarkerType.mudTube.defaultColor;
  double _selectedMarkerSize = 1;
  final Map<GraphDrawingPreset, _DrawingStyleDefaults> _drawingPresetDefaults =
      {
    for (final preset in GraphDrawingPreset.values)
      preset: _DrawingStyleDefaults.fromPreset(preset),
  };
  final Map<GraphMarkerType, _MarkerStyleDefaults> _markerDefaults = {
    for (final markerType in GraphMarkerType.values)
      markerType: _MarkerStyleDefaults.fromMarkerType(markerType),
  };
  late final MarkerDefaultsStore _markerDefaultsStore;
  Color? _defaultShapeFillColor = _ShapeFillChoice.lime.color;
  double _defaultShapeFillOpacity = _ShapeFillChoice.lime.opacity;
  Color _defaultShapeBorderColor = _ShapeBorderChoice.darkGreen.color;
  double _defaultShapeBorderWidth = 3;
  GraphShapePattern _defaultShapePattern = GraphShapePattern.none;
  Color _defaultLineColor = const Color(0xFF214D38);
  double _defaultLineWidth = 5;
  LinePattern _defaultLinePattern = LinePattern.solid;
  Color _defaultArrowColor = const Color(0xFF214D38);
  double _defaultArrowWidth = 5;
  LinePattern _defaultArrowPattern = LinePattern.solid;
  double _defaultTextFontSize = 20.4;
  Color _defaultTextColor = const Color(0xFFCC2000);
  Color _defaultTextBackground = const Color(0xFFFFEB00);
  Color _defaultTextBorder = Colors.black;
  bool _defaultTextBold = true;
  Color _defaultFreehandColor = const Color(0xFF214D38);
  double _defaultFreehandWidth = 4;
  double _defaultFreehandOpacity = 0.95;
  CanvasTool get _selectedTool => _interaction.primaryTool;
  GraphMarkerType get _selectedMarkerType => _interaction.markerType;
  bool get _isTreatmentNoteTool =>
      _selectedTool == CanvasTool.marker &&
      _selectedMarkerType == GraphMarkerType.treatmentNote;
  _CalloutKind? get _selectedCalloutKind {
    if (_isTreatmentNoteTool) return _CalloutKind.treatment;
    if (_selectedTool == CanvasTool.callout) return _CalloutKind.annotation;
    return null;
  }

  bool get _isInlineTextEditing => _inlineTextAnnotationIndex != null;
  GraphDrawingPreset get _selectedStructureType => _interaction.structureType;
  GraphDrawingPreset? get _selectedDrawingPreset =>
      _selectedTool == CanvasTool.structure ? _selectedStructureType : null;
  List<WallSegment> get _wallSegments => _document.wallSegments;
  set _wallSegments(List<WallSegment> value) =>
      _document.replaceWallSegments(value);

  List<GraphAnnotation> get _annotations => _document.annotations;
  set _annotations(List<GraphAnnotation> value) =>
      _document.replaceAnnotations(value);

  List<GraphShape> get _shapes => _document.shapes;
  set _shapes(List<GraphShape> value) => _document.replaceShapes(value);

  List<FreehandStroke> get _freehandStrokes => _document.freehandStrokes;
  set _freehandStrokes(List<FreehandStroke> value) =>
      _document.replaceFreehandStrokes(value);

  List<TraceGeometry> get _traces => _document.traces;

  bool get _traceLayerVisible => _document.layer('trace').visible;

  Map<_GraphLayer, _LayerSettings> get _layerSettings => {
        for (final layer in _GraphLayer.values)
          layer: _LayerSettings(
            visible: _document.layer(layer.name).visible,
            locked: _document.layer(layer.name).locked,
          ),
      };

  @override
  void initState() {
    super.initState();
    _document = widget.document ?? GraphDocument.forJob(widget.job!);
    _repository = widget.repository ?? MemoryGraphRepository();
    _photoPicker = widget.photoPicker ?? createGraphPhotoPicker();
    _portalService = widget.portalService ?? createBugManPortalService();
    _portalKey = widget.portalKey;
    _interaction = EditorInteractionController();
    _document.addListener(_handleDocumentChanged);
    _markerDefaultsStore =
        widget.markerDefaultsStore ?? createMarkerDefaultsStore();
    _loadPersistedMarkerDefaults();
    if (widget.presentationMode && _portalKey != null) {
      _stopPresentationExport = listenForPresentationExport(
        graphKey: _portalKey!,
        capture: _capturePresentationPng,
      );
    }
  }

  /// Merges any previously saved "Set as Default" marker styles into
  /// [_markerDefaults]. Runs synchronously during [initState], before the
  /// first frame, so newly-placed markers immediately reflect saved defaults.
  /// This only changes which style is pre-selected for markers placed from
  /// now on — it never touches annotations that already exist in the
  /// document, since those already carry their own baked-in color/size.
  void _loadPersistedMarkerDefaults() {
    final saved = _markerDefaultsStore.load();
    if (saved == null || saved.isEmpty) {
      return;
    }
    for (final entry in saved.entries) {
      GraphMarkerType markerType;
      try {
        markerType = GraphMarkerType.values.byName(entry.key);
      } catch (_) {
        continue; // Unknown/renamed marker type in older saved data; skip it.
      }
      final colorValue = entry.value['color'];
      final sizeValue = entry.value['size'];
      if (colorValue is! int || sizeValue is! num) {
        continue;
      }
      _markerDefaults[markerType] = _MarkerStyleDefaults(
        color: Color(colorValue),
        size: sizeValue.toDouble(),
      );
    }
  }

  /// Persists the current [_markerDefaults] map so "Set as Default" choices
  /// survive app restarts/page reloads.
  void _persistMarkerDefaults() {
    final serialized = <String, Map<String, Object?>>{
      for (final entry in _markerDefaults.entries)
        entry.key.name: {
          'color': entry.value.color.toARGB32(),
          'size': entry.value.size,
        },
    };
    _markerDefaultsStore.save(serialized);
  }

  void _handleDocumentChanged() {
    if (!_applyingHistory && _document.isDirty && _redoStack.isNotEmpty) {
      _redoStack.clear();
    }
  }

  @override
  void dispose() {
    _stopPresentationExport?.call();
    _document.removeListener(_handleDocumentChanged);
    _document.dispose();
    _interaction.dispose();
    _editorFocusNode.dispose();
    _inlineTextController.dispose();
    _inlineTextFocusNode.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _selectTool(CanvasTool tool) {
    _finishInlineTextEditing();
    if (_selectedTool == CanvasTool.structure &&
        _interaction.drawingSession == EditorDrawingSession.plottingStructure) {
      _cancelActiveStructure();
    }
    setState(() {
      _lastTapTime = null;
      _lastTapSceneOffset = null;
      _interaction.selectTool(tool);
      _canvasStatus = _toolStatus(tool);
      _previewSegment = null;
    });
    _editorFocusNode.requestFocus();
  }

  void _selectMarker(GraphMarkerType markerType) {
    if (markerType == GraphMarkerType.treatmentArea) {
      _selectDrawingPreset(GraphDrawingPreset.treatmentArea);
      return;
    }
    final markerDefault = _markerDefaultsFor(markerType);
    setState(() {
      _lastTapTime = null;
      _lastTapSceneOffset = null;
      _interaction.selectMarker(markerType);
      _selectedMarkerColor = markerDefault.color;
      _selectedMarkerSize = markerDefault.size;
      _canvasStatus = '${markerType.label}: tap to place';
      _previewSegment = null;
    });
    _editorFocusNode.requestFocus();
  }

  void _selectDrawingPreset(GraphDrawingPreset preset) {
    if (_selectedTool == CanvasTool.structure &&
        _interaction.drawingSession == EditorDrawingSession.plottingStructure) {
      _cancelActiveStructure();
    }
    setState(() {
      _lastTapTime = null;
      _lastTapSceneOffset = null;
      _interaction.selectStructure(preset);
      _activeWallStart = null;
      _activePathStartPoint = null;
      _activePathStartSegmentIndex = null;
      _pendingCurveControlPoint = null;
      _previewSegment = null;
      _canvasStatus = preset == GraphDrawingPreset.measurementLine
          ? 'Measure: place two or more points, then Finish Measure'
          : '${preset.label}: click each corner, then Close Shape';
    });
    _editorFocusNode.requestFocus();
  }

  void _activateToolbarAction(CanvasToolbarAction action) {
    switch (action.kind) {
      case CanvasToolbarActionKind.tool:
        _selectTool(action.tool!);
      case CanvasToolbarActionKind.preset:
        _selectDrawingPreset(action.preset!);
      case CanvasToolbarActionKind.marker:
        _selectMarker(action.marker!);
    }
  }

  void _inspectToolbarAction(CanvasToolbarAction action) {
    _activateToolbarAction(action);
  }

  void _addQuickToolbarAction(CanvasToolbarAction action) {
    if (_quickToolbarActions.contains(action)) {
      _showCanvasMessage('${action.label} is already in quick tools');
      return;
    }
    if (_quickToolbarActions.length >= 8) {
      _showCanvasMessage('Quick tools can hold up to 8 tools');
      return;
    }
    setState(() {
      _quickToolbarActions = [..._quickToolbarActions, action];
      _canvasStatus = '${action.label} added to quick tools';
    });
  }

  void _resetQuickToolbar() {
    setState(() {
      _quickToolbarActions = const [
        CanvasToolbarAction.tool(CanvasTool.select),
        CanvasToolbarAction.tool(CanvasTool.pan),
        CanvasToolbarAction.tool(CanvasTool.text),
        CanvasToolbarAction.preset(GraphDrawingPreset.mainStructure),
        CanvasToolbarAction.marker(GraphMarkerType.treatmentNote),
      ];
      _canvasStatus = 'Quick tools reset';
    });
  }

  _MarkerStyleDefaults _markerDefaultsFor(GraphMarkerType markerType) {
    return _markerDefaults[markerType] ??
        _MarkerStyleDefaults.fromMarkerType(markerType);
  }

  _DrawingStyleDefaults _drawingDefaultsFor(GraphDrawingPreset preset) {
    return _drawingPresetDefaults[preset] ??
        _DrawingStyleDefaults.fromPreset(preset);
  }

  _DrawingStyleDefaults? get _selectedDrawingDefaults {
    final preset = _selectedDrawingPreset;
    return preset == null ? null : _drawingDefaultsFor(preset);
  }

  Color get _currentLineColor =>
      _selectedDrawingDefaults?.lineColor ??
      (_selectedTool == CanvasTool.arrow
          ? _defaultArrowColor
          : _defaultLineColor);

  double get _currentLineWidth =>
      _selectedDrawingDefaults?.lineWidth ??
      (_selectedTool == CanvasTool.arrow
          ? _defaultArrowWidth
          : _defaultLineWidth);

  LinePattern get _currentLinePattern =>
      _selectedDrawingDefaults?.linePattern ??
      (_selectedTool == CanvasTool.arrow
          ? _defaultArrowPattern
          : _defaultLinePattern);

  Color? get _currentShapeFillColor =>
      _selectedDrawingDefaults?.fillColor ?? _defaultShapeFillColor;

  double get _currentShapeFillOpacity =>
      _selectedDrawingDefaults?.fillOpacity ?? _defaultShapeFillOpacity;

  Color get _currentShapeBorderColor =>
      _selectedDrawingDefaults?.borderColor ?? _defaultShapeBorderColor;

  double get _currentShapeBorderWidth =>
      _selectedDrawingDefaults?.borderWidth ?? _defaultShapeBorderWidth;

  GraphShapePattern get _currentShapePattern =>
      _selectedDrawingDefaults?.pattern ?? _defaultShapePattern;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext != null &&
        (focusedContext.widget is EditableText ||
            focusedContext.findAncestorWidgetOfExactType<EditableText>() !=
                null)) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.space) {
      final nextValue = event is KeyDownEvent || event is KeyRepeatEvent;
      if (_spacePanActive != nextValue) {
        setState(() => _spacePanActive = nextValue);
      }
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isControlPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final key = event.logicalKey;

    if (isControlPressed && key == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _redoLastAction();
      } else {
        _undoLastAction();
      }
      return KeyEventResult.handled;
    }

    if (isControlPressed && key == LogicalKeyboardKey.keyY) {
      _redoLastAction();
      return KeyEventResult.handled;
    }

    if (isControlPressed && key == LogicalKeyboardKey.keyD) {
      _duplicateSelection();
      return KeyEventResult.handled;
    }

    if (isControlPressed && key == LogicalKeyboardKey.keyC) {
      _copySelection();
      return KeyEventResult.handled;
    }

    if (isControlPressed && key == LogicalKeyboardKey.keyV) {
      _pasteClipboard();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _deleteSelection();
      return KeyEventResult.handled;
    }

    if (isControlPressed) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.enter &&
        _selectedTool == CanvasTool.structure) {
      _finishStructurePath();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      _cancelActiveDrawing();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyV) {
      _selectTool(CanvasTool.select);
    } else if (key == LogicalKeyboardKey.keyH) {
      _selectTool(CanvasTool.pan);
    } else if (key == LogicalKeyboardKey.keyB) {
      _selectDrawingPreset(_selectedStructureType);
    } else if (key == LogicalKeyboardKey.keyR) {
      _selectTool(CanvasTool.rectangle);
    } else if (key == LogicalKeyboardKey.keyS) {
      _selectTool(CanvasTool.square);
    } else if (key == LogicalKeyboardKey.keyC) {
      _selectTool(CanvasTool.circle);
    } else if (key == LogicalKeyboardKey.keyE) {
      _selectTool(CanvasTool.ellipse);
    } else if (key == LogicalKeyboardKey.keyG) {
      _selectTool(CanvasTool.triangle);
    } else if (key == LogicalKeyboardKey.keyL) {
      _selectTool(CanvasTool.wall);
    } else if (key == LogicalKeyboardKey.keyA) {
      _selectTool(CanvasTool.arrow);
    } else if (key == LogicalKeyboardKey.keyF) {
      _selectTool(CanvasTool.freehand);
    } else if (key == LogicalKeyboardKey.keyM) {
      _selectTool(CanvasTool.marker);
    } else if (key == LogicalKeyboardKey.keyT) {
      _selectTool(CanvasTool.text);
    } else if (key == LogicalKeyboardKey.keyP) {
      _togglePropertiesCollapsed();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _cancelActiveDrawing() {
    if (_selectedTool == CanvasTool.structure &&
        _interaction.drawingSession == EditorDrawingSession.plottingStructure) {
      _cancelActiveStructure();
      return;
    }

    setState(() {
      _shapeDrawStart = null;
      _shapeDrawCurrent = null;
      _draftFreehandPoints = <GraphPoint>[];
      _activeWallStart = null;
      _activePathStartPoint = null;
      _activePathStartSegmentIndex = null;
      _pendingCurveControlPoint = null;
      _previewSegment = null;
      _interaction.setDrawingSession(EditorDrawingSession.idle);
      _canvasStatus = 'Drawing cancelled';
    });
  }

  String _toolStatus(CanvasTool tool) {
    switch (tool) {
      case CanvasTool.select:
        return 'Select selected: click or drag objects';
      case CanvasTool.pan:
        return 'Pan selected: drag the canvas';
      case CanvasTool.structure:
        return _activeWallStart == null
            ? '${_selectedStructureType.label}: click the first corner'
            : '${_selectedStructureType.label}: click the next corner';
      case CanvasTool.rectangle:
        return 'Rectangle selected: tap or drag on the graph';
      case CanvasTool.square:
        return 'Square selected: tap or drag on the graph';
      case CanvasTool.circle:
        return 'Circle selected: tap or drag on the graph';
      case CanvasTool.ellipse:
        return 'Ellipse selected: tap or drag on the graph';
      case CanvasTool.triangle:
        return 'Triangle selected: tap or drag on the graph';
      case CanvasTool.wall:
        return _activeWallStart == null
            ? 'Line selected: tap a start point'
            : 'Line selected: tap the next point';
      case CanvasTool.arrow:
        return _activeWallStart == null
            ? 'Arrow selected: tap a start point'
            : 'Arrow selected: tap the arrow end';
      case CanvasTool.curve:
        return _activeWallStart == null
            ? 'Curve selected: tap a start point'
            : _pendingCurveControlPoint == null
                ? 'Curve selected: tap the bend point'
                : 'Curve selected: tap the curve end';
      case CanvasTool.freehand:
        return 'Freehand selected: drag to sketch';
      case CanvasTool.callout:
        return 'Callout Box selected: drag from the point you want to label';
      case CanvasTool.marker:
        return 'Marker selected: tap the graph';
      case CanvasTool.photo:
        return 'Photo selected: tap the graph';
      case CanvasTool.text:
        return 'Inspection Note selected: tap the graph';
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isInlineTextEditing) {
      return;
    }
    _editorFocusNode.requestFocus();
    if (event.buttons == kSecondaryMouseButton) {
      if (_removeLatestDraftPoint()) {
        return;
      }
      final sceneOffset =
          _transformationController.toScene(event.localPosition);
      _showContextMenu(event.position, sceneOffset);
      return;
    }

    if (_spacePanActive && event.buttons == kPrimaryMouseButton) {
      _shortcutPanPointers.add(event.pointer);
      return;
    }

    _activePointerCount += 1;

    if (_activePointerCount >= 2) {
      if (!_multiTouchPanning) {
        _multiTouchPanning = true;
        _cancelDrawingGestureForSelection();
        _resetPointerGesture();
      }
      return;
    }

    if (_activePointerCount == 1) {
      _pointerDownPosition = event.localPosition;
      _pointerTravel = 0;
      _pointerDownActiveWallStart = _activeWallStart;
      _pointerDownActivePathStartPoint = _activePathStartPoint;
      _pointerDownActivePathStartSegmentIndex = _activePathStartSegmentIndex;
      final sceneOffset =
          _transformationController.toScene(event.localPosition);
      _interaction.pointerDown(sceneOffset);
      final calloutKind = _selectedCalloutKind;
      if (calloutKind != null && _isInsideCanvas(sceneOffset)) {
        setState(() {
          _treatmentCalloutTip = GraphPoint.fromOffset(sceneOffset);
          _treatmentCalloutBox = sceneOffset;
          _activeCalloutKind = calloutKind;
          _canvasStatus = calloutKind == _CalloutKind.treatment
              ? 'Treatment Note: drag outward to place the callout'
              : 'Callout Box: drag outward to place the note';
        });
        return;
      }
      if (_shouldFinishFromDoubleClick(sceneOffset)) {
        _pointerDownHitSelection = null;
        return;
      }
      final pointerPoint = GraphPoint.fromOffset(sceneOffset);
      final currentSelection = _selection;
      final selectedTarget = currentSelection == null
          ? null
          : _dragTargetForSelection(currentSelection, pointerPoint);
      if (selectedTarget?.kind == _DragKind.wallEndpoint ||
          selectedTarget?.kind == _DragKind.traceVertex ||
          selectedTarget?.kind == _DragKind.traceRotation ||
          selectedTarget?.kind == _DragKind.shapeResize ||
          selectedTarget?.kind == _DragKind.shapeRotation) {
        _pointerDownHitSelection = currentSelection;
        _startDragForSelection(currentSelection!, pointerPoint);
        return;
      }
      _pointerDownHitSelection = _selectedTool == CanvasTool.select
          ? _selectionAt(pointerPoint)
          : null;

      final hitSelection = _pointerDownHitSelection;
      if (hitSelection != null) {
        setState(() {
          _selection = hitSelection;
          _interaction.setSelected(_interactionReference(hitSelection));
          _canvasStatus = _selectionStatus(hitSelection);
        });
        if (_isSelectionEditable(hitSelection)) {
          _startDragForSelection(
              hitSelection, GraphPoint.fromOffset(sceneOffset));
        }
        return;
      }

      if (_isPresetShapeTool(_selectedTool)) {
        _shapeDrawStart = sceneOffset;
        _shapeDrawCurrent = sceneOffset;
      } else if (_selectedTool == CanvasTool.freehand) {
        _startFreehandStroke(sceneOffset);
      } else if (_selectedTool == CanvasTool.wall ||
          _selectedTool == CanvasTool.arrow) {
        _startLineDrag(sceneOffset);
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_multiTouchPanning || _activePointerCount >= 2) {
      return;
    }

    if (_shortcutPanPointers.contains(event.pointer)) {
      return;
    }
    final start = _pointerDownPosition;
    if (start == null) {
      return;
    }

    final distance = (event.localPosition - start).distance;
    if (distance > _pointerTravel) {
      _pointerTravel = distance;
    }

    if (_activeDragTarget != null) {
      if (_pointerTravel <= _tapMovementLimit) {
        return;
      }
      _interaction.beginDrag();
      final sceneOffset =
          _transformationController.toScene(event.localPosition);
      if (_isInsideCanvas(sceneOffset)) {
        _moveActiveTarget(GraphPoint.fromOffset(sceneOffset));
      }
    } else if (_treatmentCalloutTip != null) {
      final sceneOffset =
          _transformationController.toScene(event.localPosition);
      if (_isInsideCanvas(sceneOffset)) {
        setState(() => _treatmentCalloutBox = sceneOffset);
      }
    } else if (_isPresetShapeTool(_selectedTool) &&
        _shapeDrawStart != null &&
        _pointerTravel > _tapMovementLimit) {
      final sceneOffset =
          _transformationController.toScene(event.localPosition);
      if (_isInsideCanvas(sceneOffset)) {
        setState(() {
          _shapeDrawCurrent = sceneOffset;
        });
      }
    } else if (_selectedTool == CanvasTool.freehand &&
        _draftFreehandPoints.isNotEmpty) {
      final sceneOffset =
          _transformationController.toScene(event.localPosition);
      if (_isInsideCanvas(sceneOffset)) {
        _appendFreehandPoint(sceneOffset);
      }
    } else {
      final sceneOffset =
          _transformationController.toScene(event.localPosition);
      if (_isInsideCanvas(sceneOffset)) {
        _updatePreviewSegment(sceneOffset);
      }
    }
  }

  void _handlePointerHover(PointerHoverEvent event) {
    final sceneOffset = _transformationController.toScene(event.localPosition);
    if (_isInsideCanvas(sceneOffset)) {
      if (_selectedTool != CanvasTool.select) {
        if (_hoverSelection != null) {
          setState(() {
            _hoverSelection = null;
            _interaction.setHovered(null);
          });
        }
        _updatePreviewSegment(sceneOffset);
        return;
      }
      final nextHover = _selectionAt(GraphPoint.fromOffset(sceneOffset));
      if (nextHover != _hoverSelection) {
        setState(() {
          _hoverSelection = nextHover;
          _interaction.setHovered(
            nextHover == null ? null : _interactionReference(nextHover),
          );
        });
      }
      if (nextHover != null) {
        if (_previewSegment != null) {
          setState(() => _previewSegment = null);
        }
        return;
      }
      _updatePreviewSegment(sceneOffset);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_isInlineTextEditing) {
      return;
    }
    if (_shortcutPanPointers.remove(event.pointer)) {
      return;
    }
    final start = _pointerDownPosition;
    final wasSinglePointerTap = _activePointerCount == 1 &&
        start != null &&
        _pointerTravel <= _tapMovementLimit &&
        (event.localPosition - start).distance <= _tapMovementLimit;

    if (_activePointerCount > 0) {
      _activePointerCount -= 1;
    }

    final sceneOffset = _transformationController.toScene(event.localPosition);

    final treatmentCalloutTip = _treatmentCalloutTip;
    if (treatmentCalloutTip != null) {
      final calloutKind = _activeCalloutKind ?? _CalloutKind.treatment;
      setState(() {
        _treatmentCalloutTip = null;
        _treatmentCalloutBox = null;
        _activeCalloutKind = null;
      });
      if (_isInsideCanvas(sceneOffset) && _pointerTravel > _tapMovementLimit) {
        _completeCallout(treatmentCalloutTip, sceneOffset, calloutKind);
      } else {
        _showCanvasMessage(calloutKind == _CalloutKind.treatment
            ? 'Drag outward to place a Treatment Note callout'
            : 'Drag outward to place a Callout Box');
      }
      if (_activePointerCount == 0) {
        _multiTouchPanning = false;
        _resetPointerGesture();
      }
      return;
    }

    if (_pointerDownHitSelection != null) {
      if (wasSinglePointerTap && _isDoubleClickNearLastTap(sceneOffset)) {
        final hitSelection = _pointerDownHitSelection!;
        if (hitSelection.kind == _SelectionKind.annotation) {
          final annotation = _annotations[hitSelection.index];
          if (annotation.kind == GraphAnnotationKind.photo) {
            _showPhotoGallery(annotation);
            _resetPointerGesture();
            _rememberTap(sceneOffset);
            return;
          }
        }
        if (hitSelection.kind == _SelectionKind.trace) {
          _openTraceWorkspace(editIndex: hitSelection.index);
          _resetPointerGesture();
          _rememberTap(sceneOffset);
          return;
        }
        if (_selectionOpensPropertiesOnDoubleClick(hitSelection)) {
          setState(() {
            _sidePanelMode = _SidePanelMode.properties;
            _canvasStatus =
                '${_selectionStatus(hitSelection)} • Properties shown';
          });
          _resetPointerGesture();
          _rememberTap(sceneOffset);
          return;
        }
        if (_editSelectedObjectText()) {
          _resetPointerGesture();
          _rememberTap(sceneOffset);
          return;
        }
      }
      if (_dragMoved) {
        _finishActiveDrag();
      }
      _cancelDrawingGestureForSelection();
      _resetPointerGesture();
      _rememberTap(sceneOffset);
      return;
    }

    if (_isPresetShapeTool(_selectedTool) && _shapeDrawStart != null) {
      if (_isInsideCanvas(sceneOffset) && !wasSinglePointerTap) {
        _finishPresetShape(sceneOffset);
      }
      _shapeDrawStart = null;
      _shapeDrawCurrent = null;
      _pointerDownPosition = null;
      _pointerTravel = 0;
      _rememberTap(sceneOffset);
      return;
    }

    if (_selectedTool == CanvasTool.freehand &&
        _draftFreehandPoints.isNotEmpty) {
      _finishFreehandStroke();
      _pointerDownPosition = null;
      _pointerTravel = 0;
      _rememberTap(sceneOffset);
      return;
    }

    if (_draggingLineTool &&
        (_selectedTool == CanvasTool.wall ||
            _selectedTool == CanvasTool.arrow)) {
      if (_isInsideCanvas(sceneOffset) && _pointerTravel > _tapMovementLimit) {
        _finishDraggedLine(sceneOffset);
        _pointerDownPosition = null;
        _pointerTravel = 0;
        _draggingLineTool = false;
        _lineDragStartedNewPath = false;
        _rememberTap(sceneOffset);
        return;
      }
      final shouldHandleTap = !_lineDragStartedNewPath;
      _draggingLineTool = false;
      _lineDragStartedNewPath = false;
      if (shouldHandleTap &&
          _isInsideCanvas(sceneOffset) &&
          _shouldFinishFromDoubleClick(sceneOffset)) {
        _finishWallPath(closeShapeDefault: true, autoFinish: true);
        _rememberTap(sceneOffset);
        return;
      }
      if (shouldHandleTap && _isInsideCanvas(sceneOffset)) {
        _handleCanvasTap(sceneOffset);
      }
      _rememberTap(sceneOffset);
      return;
    }

    if (wasSinglePointerTap) {
      if (_isInsideCanvas(sceneOffset)) {
        if (_selectedTool == CanvasTool.select &&
            _isDoubleClickNearLastTap(sceneOffset) &&
            _editTextAt(sceneOffset)) {
          _rememberTap(sceneOffset);
          return;
        }

        if (_shouldFinishFromDoubleClick(sceneOffset)) {
          _finishWallPath(closeShapeDefault: true, autoFinish: true);
          _rememberTap(sceneOffset);
          return;
        }

        _handleCanvasTap(sceneOffset);
        _rememberTap(sceneOffset);
      }
    }

    if (_activePointerCount == 0) {
      _multiTouchPanning = false;
      _resetPointerGesture();
    }
  }

  void _resetPointerGesture() {
    _pointerDownPosition = null;
    _pointerDownHitSelection = null;
    _pointerTravel = 0;
    _activeDragTarget = null;
    _dragOriginalWallSegments = null;
    _dragOriginalAnnotations = null;
    _dragOriginalShapes = null;
    _dragOriginalFreehandStrokes = null;
    _dragOriginalTraces = null;
    _dragOriginalActiveWallStart = null;
    _dragOriginalActivePathStartPoint = null;
    _dragOriginalActivePathStartSegmentIndex = null;
    _dragMoved = false;
    _interaction.pointerUp();
  }

  void _rememberTap(Offset sceneOffset) {
    _lastTapTime = DateTime.now();
    _lastTapSceneOffset = sceneOffset;
  }

  bool _shouldFinishFromDoubleClick(Offset sceneOffset) {
    if (_activeWallStart == null ||
        (_selectedTool != CanvasTool.structure &&
            _selectedTool != CanvasTool.wall &&
            _selectedTool != CanvasTool.arrow &&
            _selectedTool != CanvasTool.curve)) {
      return false;
    }

    return _isDoubleClickNearLastTap(sceneOffset);
  }

  bool _isDoubleClickNearLastTap(Offset sceneOffset) {
    final lastTapTime = _lastTapTime;
    final lastTapSceneOffset = _lastTapSceneOffset;
    if (lastTapTime == null || lastTapSceneOffset == null) {
      return false;
    }

    final withinTime =
        DateTime.now().difference(lastTapTime) <= _doubleClickWindow;
    final nearLastTap = (sceneOffset - lastTapSceneOffset).distance <= 18;

    return withinTime && nearLastTap;
  }

  bool _editTextAt(Offset sceneOffset) {
    final textIndex = _findTextAnnotationIndex(sceneOffset);
    if (textIndex == null) {
      return false;
    }

    if (_isLayerLocked(_GraphLayer.inspections)) {
      _showCanvasMessage('Inspections layer is locked');
      return true;
    }

    _editTextAnnotation(textIndex);
    return true;
  }

  bool _selectionOpensPropertiesOnDoubleClick(_Selection selection) {
    if (selection.kind == _SelectionKind.shape ||
        selection.kind == _SelectionKind.segment ||
        selection.kind == _SelectionKind.freehand ||
        selection.kind == _SelectionKind.trace) {
      return true;
    }
    if (selection.kind != _SelectionKind.annotation) {
      return false;
    }
    final annotation = _annotations[selection.index];
    return annotation.kind == GraphAnnotationKind.marker &&
        annotation.markerType != GraphMarkerType.treatmentNote;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_shortcutPanPointers.remove(event.pointer)) {
      return;
    }
    if (_activePointerCount > 0) {
      _activePointerCount -= 1;
    }

    if (_activePointerCount == 0) {
      _multiTouchPanning = false;
      _cancelDrawingGestureForSelection();
      _resetPointerGesture();
    }
  }

  void _cancelDrawingGestureForSelection() {
    setState(() {
      _shapeDrawStart = null;
      _shapeDrawCurrent = null;
      _draftFreehandPoints = <GraphPoint>[];
      _draggingLineTool = false;
      _lineDragStartedNewPath = false;
      _activeWallStart = _pointerDownActiveWallStart;
      _activePathStartPoint = _pointerDownActivePathStartPoint;
      _activePathStartSegmentIndex = _pointerDownActivePathStartSegmentIndex;
      _previewSegment = null;
    });
  }

  bool _isInsideCanvas(Offset sceneOffset) {
    return sceneOffset.dx >= 0 &&
        sceneOffset.dy >= 0 &&
        sceneOffset.dx <= _canvasSize.width &&
        sceneOffset.dy <= _canvasSize.height;
  }

  bool _removeLatestDraftPoint() {
    final startIndex = _activePathStartSegmentIndex;
    if (_activeWallStart == null || startIndex == null) {
      return false;
    }

    if (_selectedTool != CanvasTool.structure &&
        _selectedTool != CanvasTool.wall &&
        _selectedTool != CanvasTool.arrow &&
        _selectedTool != CanvasTool.curve) {
      return false;
    }

    if (_pendingCurveControlPoint != null) {
      setState(() {
        _pendingCurveControlPoint = null;
        _previewSegment = null;
        _canvasStatus = 'Latest plotted point removed';
      });
      return true;
    }

    if (_wallSegments.length > startIndex) {
      final removed = _wallSegments.last;
      setState(() {
        _wallSegments = _wallSegments.sublist(0, _wallSegments.length - 1);
        _activeWallStart = removed.start;
        _pendingCurveControlPoint = null;
        _previewSegment = null;
        if (_undoStack.isNotEmpty &&
            _undoStack.last.kind == _UndoKind.wallSegment) {
          _undoStack.removeLast();
        }
        _canvasStatus = 'Latest plotted point removed';
      });
      return true;
    }

    setState(() {
      if (_selectedTool == CanvasTool.structure &&
          _structureStartSnapshot != null) {
        _applyingHistory = true;
        _structureStartSnapshot!.restore(this);
        _applyingHistory = false;
        _structureStartSnapshot = null;
        _interaction.setDrawingSession(EditorDrawingSession.idle);
      } else {
        _activeWallStart = null;
        _activePathStartPoint = null;
        _activePathStartSegmentIndex = null;
        _pendingCurveControlPoint = null;
        if (_undoStack.isNotEmpty &&
            _undoStack.last.kind == _UndoKind.wallStart) {
          _undoStack.removeLast();
        }
      }
      _previewSegment = null;
      _canvasStatus = 'First plotted point removed';
    });
    return true;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      _translateViewport(dx: -event.scrollDelta.dy);
    } else if (keyboard.isShiftPressed) {
      _translateViewport(dy: -event.scrollDelta.dy);
    } else {
      final factor = math.exp(-event.scrollDelta.dy / 500);
      _zoomAt(event.localPosition, factor);
    }
  }

  void _zoomAt(Offset viewportPoint, double factor) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(0.25, 10.0);
    final scenePoint = _transformationController.toScene(viewportPoint);
    final next = Matrix4.identity();
    next.setEntry(0, 0, nextScale);
    next.setEntry(1, 1, nextScale);
    next.setEntry(2, 2, nextScale);
    next.setEntry(0, 3, viewportPoint.dx - (scenePoint.dx * nextScale));
    next.setEntry(1, 3, viewportPoint.dy - (scenePoint.dy * nextScale));
    _transformationController.value = next;
  }

  void _translateViewport({double dx = 0, double dy = 0}) {
    final next = _transformationController.value.clone();
    next.setEntry(0, 3, next.entry(0, 3) + dx);
    next.setEntry(1, 3, next.entry(1, 3) + dy);
    _transformationController.value = next;
  }

  void _centerCanvasInViewport(Size viewportSize) {
    if (_initialCanvasCentered ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return;
    }
    _initialCanvasCentered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_traceLayerVisible && _traces.isNotEmpty) {
        _fitTraceInViewport(_traces.last, viewportSize: viewportSize);
        return;
      }
      final centered = Matrix4.identity();
      centered.setEntry(0, 3, (viewportSize.width - _canvasSize.width) / 2);
      centered.setEntry(1, 3, (viewportSize.height - _canvasSize.height) / 2);
      _transformationController.value = centered;
    });
  }

  bool _isLayerVisible(_GraphLayer layer) {
    if (layer == _GraphLayer.trace) {
      return _traceLayerVisible;
    }

    return _layerSettings[layer]?.visible ?? true;
  }

  bool _isLayerLocked(_GraphLayer layer) {
    return _layerSettings[layer]?.locked ?? false;
  }

  bool _isAnnotationVisible(GraphAnnotation annotation) {
    return _isLayerVisible(_layerForAnnotation(annotation));
  }

  bool _isAnnotationLocked(GraphAnnotation annotation) {
    return _isLayerLocked(_layerForAnnotation(annotation));
  }

  _GraphLayer _layerForAnnotation(GraphAnnotation annotation) {
    return annotation.kind == GraphAnnotationKind.photo
        ? _GraphLayer.photos
        : annotation.kind == GraphAnnotationKind.marker &&
                isTreatmentMarker(annotation.markerType)
            ? _GraphLayer.treatment
            : annotation.kind == GraphAnnotationKind.marker &&
                    utilityMarkerTypes.contains(annotation.markerType)
                ? _GraphLayer.structure
                : _GraphLayer.inspections;
  }

  _GraphLayer _layerForSelection(_Selection selection) {
    return switch (selection.kind) {
      _SelectionKind.annotation => _layerForAnnotation(
          _annotations[selection.index],
        ),
      _SelectionKind.segment => _GraphLayer.structure,
      _SelectionKind.shape => _isTreatmentShape(_shapes[selection.index])
          ? _GraphLayer.treatment
          : _GraphLayer.structure,
      _SelectionKind.freehand => _GraphLayer.structure,
      _SelectionKind.trace => _GraphLayer.trace,
    };
  }

  bool _isSelectionEditable(_Selection selection) {
    if (selection.kind == _SelectionKind.annotation &&
        (selection.index < 0 || selection.index >= _annotations.length)) {
      return false;
    }

    if (selection.kind == _SelectionKind.shape) {
      if (_isTreatmentShape(_shapes[selection.index])) {
        return !_isLayerLocked(_GraphLayer.treatment);
      }
      return !_isLayerLocked(_GraphLayer.shapes) &&
          !_isLayerLocked(_GraphLayer.structure);
    }

    if (selection.kind == _SelectionKind.trace &&
        (selection.index < 0 || selection.index >= _traces.length)) {
      return false;
    }

    return !_isLayerLocked(_layerForSelection(selection));
  }

  bool _isTreatmentShape(GraphShape shape) =>
      shape.preset == GraphDrawingPreset.treatmentArea;

  void _updatePreviewSegment(Offset sceneOffset) {
    final activeStart = _activeWallStart;
    if (activeStart == null ||
        (_selectedTool != CanvasTool.structure &&
            _selectedTool != CanvasTool.wall &&
            _selectedTool != CanvasTool.arrow &&
            _selectedTool != CanvasTool.curve)) {
      if (_previewSegment != null) {
        setState(() {
          _previewSegment = null;
        });
      }
      return;
    }

    final rawPoint = GraphPoint.fromOffset(sceneOffset);
    final endpointSnap = _findNearbyEndpoint(rawPoint);
    final previewEnd = _selectedTool == CanvasTool.structure ||
            _selectedTool == CanvasTool.wall ||
            _selectedTool == CanvasTool.arrow
        ? endpointSnap ?? _snapWallPoint(rawPoint, activeStart)
        : endpointSnap ?? (_snapToGrid ? _snapPointToGrid(rawPoint) : rawPoint);
    final previewSegment =
        _selectedTool == CanvasTool.curve && _pendingCurveControlPoint != null
            ? WallSegment(
                start: activeStart,
                end: previewEnd,
                controlPoint: _pendingCurveControlPoint,
                color: _currentLineColor,
                strokeWidth: _currentLineWidth,
                pattern: _currentLinePattern,
              )
            : WallSegment(
                start: activeStart,
                end: previewEnd,
                color: _currentLineColor,
                strokeWidth: _currentLineWidth,
                pattern: _currentLinePattern,
                hasArrow: _selectedTool == CanvasTool.arrow,
              );

    setState(() {
      _previewSegment = previewSegment;
    });
  }

  void _handleCanvasTap(Offset sceneOffset) {
    if (_selectedTool == CanvasTool.select) {
      _selectObjectAt(sceneOffset);
      return;
    }

    if (_selectedTool == CanvasTool.pan) {
      _showCanvasMessage('Pan selected: drag to move around canvas');
      return;
    }

    if (_selectedTool == CanvasTool.structure) {
      _addStructurePoint(sceneOffset);
      return;
    }

    if (_selectedTool == CanvasTool.wall) {
      _addWallPoint(sceneOffset);
      return;
    }

    if (_selectedTool == CanvasTool.arrow) {
      _addArrowPoint(sceneOffset);
      return;
    }

    if (_selectedTool == CanvasTool.curve) {
      _addCurvePoint(sceneOffset);
      return;
    }

    if (_selectedTool == CanvasTool.text) {
      _handleTextTap(sceneOffset);
      return;
    }

    if (_selectedTool == CanvasTool.callout) {
      _showCanvasMessage('Drag outward to place a Callout Box');
      return;
    }

    _addPlaceholderAnnotation(sceneOffset);
  }

  Future<void> _showContextMenu(
      Offset globalPosition, Offset sceneOffset) async {
    _selectObjectAt(sceneOffset);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selectedAction = await showMenu<_ContextAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: _ContextAction.copy, child: Text('Copy')),
        PopupMenuItem(value: _ContextAction.paste, child: Text('Paste')),
        PopupMenuItem(
            value: _ContextAction.duplicate, child: Text('Duplicate')),
        PopupMenuItem(value: _ContextAction.delete, child: Text('Delete')),
        PopupMenuDivider(),
        PopupMenuItem(
            value: _ContextAction.bringForward, child: Text('Bring Forward')),
        PopupMenuItem(
            value: _ContextAction.sendBackward, child: Text('Send Backward')),
        PopupMenuItem(
            value: _ContextAction.bringToFront, child: Text('Bring to Front')),
        PopupMenuItem(
            value: _ContextAction.sendToBack, child: Text('Send to Back')),
        PopupMenuDivider(),
        PopupMenuItem(value: _ContextAction.lock, child: Text('Lock Layer')),
        PopupMenuItem(
            value: _ContextAction.unlock, child: Text('Unlock Layer')),
        PopupMenuItem(value: _ContextAction.group, child: Text('Group')),
        PopupMenuItem(value: _ContextAction.ungroup, child: Text('Ungroup')),
        PopupMenuItem(
            value: _ContextAction.properties, child: Text('Properties')),
      ],
    );

    if (selectedAction == null || !mounted) {
      return;
    }

    _runContextAction(selectedAction);
  }

  void _runContextAction(_ContextAction action) {
    switch (action) {
      case _ContextAction.copy:
        _copySelection();
        return;
      case _ContextAction.paste:
        _pasteClipboard();
        return;
      case _ContextAction.duplicate:
        _duplicateSelection();
        return;
      case _ContextAction.delete:
        _deleteSelection();
        return;
      case _ContextAction.bringForward:
        _reorderSelection(_ReorderDirection.forward);
        return;
      case _ContextAction.sendBackward:
        _reorderSelection(_ReorderDirection.backward);
        return;
      case _ContextAction.bringToFront:
        _reorderSelection(_ReorderDirection.front);
        return;
      case _ContextAction.sendToBack:
        _reorderSelection(_ReorderDirection.back);
        return;
      case _ContextAction.lock:
        _setSelectedLayerLocked(true);
        return;
      case _ContextAction.unlock:
        _setSelectedLayerLocked(false);
        return;
      case _ContextAction.group:
      case _ContextAction.ungroup:
        _showCanvasMessage(
            'Grouping will apply to multi-select in the next pass');
        return;
      case _ContextAction.properties:
        setState(() {
          _sidePanelMode = _SidePanelMode.properties;
          _canvasStatus = 'Properties shown';
        });
        return;
    }
  }

  bool _isPresetShapeTool(CanvasTool tool) {
    return switch (tool) {
      CanvasTool.rectangle ||
      CanvasTool.square ||
      CanvasTool.circle ||
      CanvasTool.ellipse ||
      CanvasTool.triangle =>
        true,
      _ => false,
    };
  }

  void _finishPresetShape(Offset endOffset) {
    final start = _shapeDrawStart ?? endOffset;
    final distance = (endOffset - start).distance;
    if (distance <= _tapMovementLimit) {
      _showCanvasMessage('Drag to create a shape');
      return;
    }

    final rect = _rectFromDrag(
      start,
      endOffset,
      forceSquare: _selectedTool == CanvasTool.square ||
          _selectedTool == CanvasTool.circle,
    );

    _addPresetShape(rect);
  }

  Rect _rectFromDrag(
    Offset start,
    Offset end, {
    required bool forceSquare,
  }) {
    final normalized = Rect.fromPoints(start, end);
    if (!forceSquare) {
      return normalized;
    }

    final size = math.max(normalized.width, normalized.height);
    final dx = end.dx >= start.dx ? size : -size;
    final dy = end.dy >= start.dy ? size : -size;
    return Rect.fromPoints(start, Offset(start.dx + dx, start.dy + dy));
  }

  void _addPresetShape(Rect rawRect) {
    if (_isLayerLocked(_GraphLayer.structure) ||
        _isLayerLocked(_GraphLayer.shapes)) {
      _showCanvasMessage('Unlock Structure and Shapes to add shapes');
      return;
    }

    final rect = _normalizeMinimumRect(rawRect);
    final newSegments = _segmentsForPresetShapeTool(_selectedTool, rect);

    if (newSegments.isEmpty) {
      return;
    }

    final startIndex = _wallSegments.length;
    final shape = GraphShape(
      name: _defaultShapeName(_selectedTool),
      segmentIndexes: [
        for (var i = 0; i < newSegments.length; i += 1) startIndex + i,
      ],
      fillColor: _currentShapeFillColor,
      fillOpacity: _currentShapeFillOpacity,
      borderColor: _currentShapeBorderColor,
      borderWidth: _currentShapeBorderWidth,
      pattern: _currentShapePattern,
      closed: true,
      rotationDegrees: 0,
      preset: _selectedDrawingPreset,
      extraProperties: <String, Object?>{'basicShapeKind': _selectedTool.name},
    );

    setState(() {
      _wallSegments = <WallSegment>[..._wallSegments, ...newSegments];
      _shapes = <GraphShape>[..._shapes, shape];
      _selection = _Selection.shape(_shapes.length - 1);
      _undoStack.add(
        _UndoEntry(
          _UndoKind.shapeFinish,
          shapeIndex: _shapes.length - 1,
          addedSegmentCount: newSegments.length,
        ),
      );
      _canvasStatus = '${shape.name} added';
    });
  }

  Rect _normalizeMinimumRect(Rect rect) {
    final normalized = Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );

    return Rect.fromCenter(
      center: normalized.center,
      width: math.max(normalized.width, 48),
      height: math.max(normalized.height, 48),
    );
  }

  String _defaultShapeName(CanvasTool tool) {
    final preset = _selectedDrawingPreset;
    if (preset != null && preset.kind == GraphDrawingPresetKind.area) {
      final samePresetCount =
          _shapes.where((shape) => shape.preset == preset).length;
      return samePresetCount == 0
          ? preset.label
          : '${preset.label} ${samePresetCount + 1}';
    }

    return switch (tool) {
      CanvasTool.rectangle => 'Rectangle ${_shapes.length + 1}',
      CanvasTool.square => 'Square ${_shapes.length + 1}',
      CanvasTool.circle => 'Circle ${_shapes.length + 1}',
      CanvasTool.ellipse => 'Ellipse ${_shapes.length + 1}',
      CanvasTool.triangle => 'Triangle ${_shapes.length + 1}',
      _ => 'Shape ${_shapes.length + 1}',
    };
  }

  List<WallSegment> _segmentsForPresetShapeTool(CanvasTool tool, Rect rect) {
    return switch (tool) {
      CanvasTool.rectangle || CanvasTool.square => _rectangleSegments(rect),
      CanvasTool.circle || CanvasTool.ellipse => _ellipseSegments(rect),
      CanvasTool.triangle => _triangleSegments(rect),
      _ => <WallSegment>[],
    };
  }

  List<WallSegment> _rectangleSegments(Rect rect) {
    final topLeft = GraphPoint.fromOffset(rect.topLeft);
    final topRight = GraphPoint.fromOffset(rect.topRight);
    final bottomRight = GraphPoint.fromOffset(rect.bottomRight);
    final bottomLeft = GraphPoint.fromOffset(rect.bottomLeft);

    return [
      WallSegment(start: topLeft, end: topRight),
      WallSegment(start: topRight, end: bottomRight),
      WallSegment(start: bottomRight, end: bottomLeft),
      WallSegment(start: bottomLeft, end: topLeft),
    ];
  }

  List<WallSegment> _triangleSegments(Rect rect) {
    final top = GraphPoint.fromOffset(rect.topCenter);
    final bottomRight = GraphPoint.fromOffset(rect.bottomRight);
    final bottomLeft = GraphPoint.fromOffset(rect.bottomLeft);

    return [
      WallSegment(start: top, end: bottomRight),
      WallSegment(start: bottomRight, end: bottomLeft),
      WallSegment(start: bottomLeft, end: top),
    ];
  }

  List<WallSegment> _ellipseSegments(Rect rect) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    const segmentCount = 8;
    const startAngle = -math.pi / 2;
    const step = (math.pi * 2) / segmentCount;
    final controlScale = 1 / math.cos(step / 2);

    return [
      for (var i = 0; i < segmentCount; i += 1)
        WallSegment(
          start: GraphPoint(
            x: cx + (rx * math.cos(startAngle + (step * i))),
            y: cy + (ry * math.sin(startAngle + (step * i))),
          ),
          end: GraphPoint(
            x: cx + (rx * math.cos(startAngle + (step * (i + 1)))),
            y: cy + (ry * math.sin(startAngle + (step * (i + 1)))),
          ),
          controlPoint: GraphPoint(
            x: cx +
                (rx * controlScale * math.cos(startAngle + (step * (i + 0.5)))),
            y: cy +
                (ry * controlScale * math.sin(startAngle + (step * (i + 0.5)))),
          ),
        ),
    ];
  }

  bool _editSelectedObjectText() {
    final selection = _selection;
    if (selection == null) {
      return false;
    }
    if (selection.kind == _SelectionKind.shape) {
      final shape = _shapes[selection.index];
      if (shape.isStructure) {
        return false;
      }
      _editShapeText(selection.index);
      return true;
    }
    if (selection.kind == _SelectionKind.annotation &&
        _annotations[selection.index].kind == GraphAnnotationKind.text) {
      _editTextAnnotation(selection.index);
      return true;
    }
    if (selection.kind == _SelectionKind.annotation &&
        _annotations[selection.index].markerType ==
            GraphMarkerType.treatmentNote) {
      _editTreatmentCallout(selection.index);
      return true;
    }
    return false;
  }

  void _addStructurePoint(Offset canvasOffset) {
    final isTreatmentArea =
        _selectedStructureType == GraphDrawingPreset.treatmentArea;
    if ((isTreatmentArea && _isLayerLocked(_GraphLayer.treatment)) ||
        (!isTreatmentArea &&
            (_isLayerLocked(_GraphLayer.structure) ||
                _isLayerLocked(_GraphLayer.shapes)))) {
      _showCanvasMessage(
        isTreatmentArea
            ? 'Unlock Treatment to draw a treatment area'
            : 'Unlock Building Structure to draw a structure',
      );
      return;
    }

    final tappedPoint = GraphPoint.fromOffset(canvasOffset);
    final activeStart = _activeWallStart;
    final endpointSnap = _findNearbyEndpoint(tappedPoint);
    final nextPoint = endpointSnap ?? _snapWallPoint(tappedPoint, activeStart);

    if (activeStart == null) {
      setState(() {
        _structureStartSnapshot = _EditorSnapshot.capture(this);
        _activeWallStart = nextPoint;
        _activePathStartPoint = nextPoint;
        _activePathStartSegmentIndex = _wallSegments.length;
        _interaction.setDrawingSession(EditorDrawingSession.plottingStructure);
        _canvasStatus = '${_selectedStructureType.label}: first corner placed';
      });
      return;
    }

    if (activeStart.distanceTo(nextPoint) < _minimumWallLength) {
      _showCanvasMessage('Place the next corner farther away');
      return;
    }

    final segment = WallSegment(
      start: activeStart,
      end: nextPoint,
      color: _currentShapeBorderColor,
      strokeWidth: _currentShapeBorderWidth,
      pattern: _currentLinePattern,
    );

    setState(() {
      _wallSegments = <WallSegment>[..._wallSegments, segment];
      _activeWallStart = nextPoint;
      _canvasStatus =
          _selectedStructureType == GraphDrawingPreset.measurementLine
              ? 'Measure: point placed • Finish Measure, Enter, or double-click'
              : '${_selectedStructureType.label}: corner placed • '
                  'Close Shape, Enter, or double-click';
    });
  }

  void _cancelActiveStructure() {
    final snapshot = _structureStartSnapshot;
    setState(() {
      if (snapshot != null) {
        _applyingHistory = true;
        snapshot.restore(this);
        _applyingHistory = false;
      } else {
        _activeWallStart = null;
        _activePathStartPoint = null;
        _activePathStartSegmentIndex = null;
        _previewSegment = null;
      }
      _structureStartSnapshot = null;
      _interaction.setDrawingSession(EditorDrawingSession.idle);
      _canvasStatus = 'Unfinished structure cancelled';
    });
  }

  void _finishStructurePath() {
    final preset = _selectedStructureType;
    final startIndex = _activePathStartSegmentIndex;
    final pathStart = _activePathStartPoint;
    final pathEnd = _activeWallStart;
    final before = _structureStartSnapshot;
    if (startIndex == null ||
        pathStart == null ||
        pathEnd == null ||
        before == null) {
      _showCanvasMessage(preset == GraphDrawingPreset.measurementLine
          ? 'Place two measurement points before finishing'
          : 'Place the first structure point before finishing');
      return;
    }

    final segmentCount = _wallSegments.length - startIndex;
    // Preserve old saved area measurements; new measurements are open paths.
    final isArea = preset.kind == GraphDrawingPresetKind.area &&
        preset != GraphDrawingPreset.measurementLine;
    final closesShape = isArea || preset == GraphDrawingPreset.propertyLine;
    if (segmentCount < (closesShape ? 2 : 1)) {
      _showCanvasMessage(
        isArea
            ? 'A structure needs at least three plotted corners'
            : 'Plot at least two points before finishing',
      );
      return;
    }

    setState(() {
      final segmentIndexes = <int>[
        for (var i = startIndex; i < _wallSegments.length; i += 1) i,
      ];
      if (closesShape && pathEnd.distanceTo(pathStart) > _minimumWallLength) {
        segmentIndexes.add(_wallSegments.length);
        _wallSegments = <WallSegment>[
          ..._wallSegments,
          WallSegment(
            start: pathEnd,
            end: pathStart,
            color: _currentShapeBorderColor,
            strokeWidth: _currentShapeBorderWidth,
            pattern: _currentLinePattern,
          ),
        ];
      }

      final defaults = _drawingDefaultsFor(preset);
      final shape = GraphShape(
        name: preset.label,
        segmentIndexes: segmentIndexes,
        fillColor: isArea ? defaults.fillColor : null,
        fillOpacity: isArea ? defaults.fillOpacity : 0,
        borderColor: defaults.borderColor,
        borderWidth: defaults.borderWidth,
        pattern: isArea ? defaults.pattern : GraphShapePattern.none,
        closed: closesShape,
        rotationDegrees: 0,
        preset: preset,
      );
      _shapes = <GraphShape>[..._shapes, shape];
      _selection = _Selection.shape(_shapes.length - 1);
      _interaction.setSelected(_interactionReference(_selection!));
      _undoStack.add(
        _UndoEntry(_UndoKind.snapshot, previousSnapshot: before),
      );
      _activeWallStart = null;
      _activePathStartPoint = null;
      _activePathStartSegmentIndex = null;
      _previewSegment = null;
      _structureStartSnapshot = null;
      _interaction.setDrawingSession(EditorDrawingSession.idle);
      _canvasStatus = '${preset.label} finished';
    });
  }

  void _addWallPoint(Offset canvasOffset) {
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    final tappedPoint = GraphPoint.fromOffset(canvasOffset);
    final activeStart = _activeWallStart;
    final endpointSnap = _findNearbyEndpoint(tappedPoint);
    final nextPoint = endpointSnap ?? _snapWallPoint(tappedPoint, activeStart);

    if (activeStart == null) {
      setState(() {
        _activeWallStart = nextPoint;
        _activePathStartPoint = nextPoint;
        _activePathStartSegmentIndex = _wallSegments.length;
        _undoStack.add(const _UndoEntry(_UndoKind.wallStart));
        _canvasStatus = endpointSnap == null
            ? 'Wall start set on grid'
            : 'Wall start snapped to endpoint';
      });
      return;
    }

    if (activeStart.distanceTo(nextPoint) < _minimumWallLength) {
      _showCanvasMessage('Tap farther away to create a wall');
      return;
    }

    final segment = WallSegment(
      start: activeStart,
      end: nextPoint,
      color: _currentLineColor,
      strokeWidth: _currentLineWidth,
      pattern: _currentLinePattern,
    );

    setState(() {
      _wallSegments = <WallSegment>[..._wallSegments, segment];
      _activeWallStart = nextPoint;
      _undoStack.add(const _UndoEntry(_UndoKind.wallSegment));
      _canvasStatus = endpointSnap == null
          ? 'Wall added with angle snap: ${segment.measurementLabel}'
          : 'Wall added and snapped: ${segment.measurementLabel}';
    });
  }

  void _startLineDrag(Offset sceneOffset) {
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    final point = GraphPoint.fromOffset(sceneOffset);
    final startPoint =
        _findNearbyEndpoint(point) ?? _snapWallPoint(point, null);

    setState(() {
      _draggingLineTool = true;
      _lineDragStartedNewPath = _activeWallStart == null;
      _activeWallStart ??= startPoint;
      _activePathStartPoint ??= _activeWallStart;
      _activePathStartSegmentIndex ??= _wallSegments.length;
      _canvasStatus =
          '${_selectedTool == CanvasTool.arrow ? 'Arrow' : 'Line'} preview';
    });
  }

  void _finishDraggedLine(Offset sceneOffset) {
    final activeStart = _activeWallStart;
    if (activeStart == null) {
      return;
    }

    final rawPoint = GraphPoint.fromOffset(sceneOffset);
    final endpointSnap = _findNearbyEndpoint(rawPoint);
    final nextPoint = endpointSnap ?? _snapWallPoint(rawPoint, activeStart);

    if (activeStart.distanceTo(nextPoint) < _minimumWallLength) {
      _showCanvasMessage('Drag farther to create a line');
      return;
    }

    final isArrow = _selectedTool == CanvasTool.arrow;
    final segment = WallSegment(
      start: activeStart,
      end: nextPoint,
      color: _currentLineColor,
      strokeWidth: _currentLineWidth,
      pattern: _currentLinePattern,
      hasArrow: isArrow,
    );

    setState(() {
      _wallSegments = <WallSegment>[..._wallSegments, segment];
      _previewSegment = null;
      _pendingCurveControlPoint = null;
      _activeWallStart = isArrow ? null : nextPoint;
      _activePathStartPoint = isArrow ? null : _activePathStartPoint;
      _activePathStartSegmentIndex =
          isArrow ? null : _activePathStartSegmentIndex;
      _undoStack.add(const _UndoEntry(_UndoKind.wallSegment));
      _canvasStatus =
          isArrow ? 'Arrow added' : 'Line added: ${segment.measurementLabel}';
    });
  }

  void _addArrowPoint(Offset canvasOffset) {
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    final tappedPoint = GraphPoint.fromOffset(canvasOffset);
    final activeStart = _activeWallStart;
    final endpointSnap = _findNearbyEndpoint(tappedPoint);
    final nextPoint = endpointSnap ?? _snapWallPoint(tappedPoint, activeStart);

    if (activeStart == null) {
      setState(() {
        _activeWallStart = nextPoint;
        _activePathStartPoint = nextPoint;
        _activePathStartSegmentIndex = _wallSegments.length;
        _undoStack.add(const _UndoEntry(_UndoKind.wallStart));
        _canvasStatus = 'Arrow start set';
      });
      return;
    }

    if (activeStart.distanceTo(nextPoint) < _minimumWallLength) {
      _showCanvasMessage('Tap farther away to create an arrow');
      return;
    }

    final segment = WallSegment(
      start: activeStart,
      end: nextPoint,
      hasArrow: true,
      color: _currentLineColor,
      strokeWidth: _currentLineWidth,
      pattern: _currentLinePattern,
    );

    setState(() {
      _wallSegments = <WallSegment>[..._wallSegments, segment];
      _activeWallStart = null;
      _activePathStartPoint = null;
      _activePathStartSegmentIndex = null;
      _undoStack.add(const _UndoEntry(_UndoKind.wallSegment));
      _canvasStatus = 'Arrow added';
    });
  }

  void _addCurvePoint(Offset canvasOffset) {
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    final tappedPoint = GraphPoint.fromOffset(canvasOffset);
    final activeStart = _activeWallStart;
    final endpointSnap = _findNearbyEndpoint(tappedPoint);
    final nextPoint = endpointSnap ??
        (_snapToGrid ? _snapPointToGrid(tappedPoint) : tappedPoint);

    if (activeStart == null) {
      setState(() {
        _activeWallStart = nextPoint;
        _activePathStartPoint = nextPoint;
        _activePathStartSegmentIndex = _wallSegments.length;
        _pendingCurveControlPoint = null;
        _undoStack.add(const _UndoEntry(_UndoKind.wallStart));
        _canvasStatus = endpointSnap == null
            ? 'Curve start set'
            : 'Curve start snapped to endpoint';
      });
      return;
    }

    if (_pendingCurveControlPoint == null) {
      final controlPoint =
          _snapToGrid ? _snapPointToGrid(tappedPoint) : tappedPoint;

      setState(() {
        _pendingCurveControlPoint = controlPoint;
        _canvasStatus = 'Curve bend set: tap the end point';
      });
      return;
    }

    if (activeStart.distanceTo(nextPoint) < _minimumWallLength) {
      _showCanvasMessage('Tap farther away to create a curve');
      return;
    }

    final segment = WallSegment(
      start: activeStart,
      end: nextPoint,
      controlPoint: _pendingCurveControlPoint,
      color: _currentLineColor,
      strokeWidth: _currentLineWidth,
      pattern: _currentLinePattern,
    );

    setState(() {
      _wallSegments = <WallSegment>[..._wallSegments, segment];
      _activeWallStart = nextPoint;
      _pendingCurveControlPoint = null;
      _undoStack.add(const _UndoEntry(_UndoKind.wallSegment));
      _canvasStatus = 'Curve added: ${segment.measurementLabel}';
    });
  }

  void _startFreehandStroke(Offset sceneOffset) {
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    setState(() {
      _draftFreehandPoints = [GraphPoint.fromOffset(sceneOffset)];
      _canvasStatus = 'Sketching freehand';
    });
  }

  void _appendFreehandPoint(Offset sceneOffset) {
    final point = GraphPoint.fromOffset(sceneOffset);
    if (_draftFreehandPoints.isNotEmpty &&
        _draftFreehandPoints.last.distanceTo(point) < 4) {
      return;
    }

    setState(() {
      _draftFreehandPoints = <GraphPoint>[..._draftFreehandPoints, point];
    });
  }

  void _finishFreehandStroke() {
    if (_draftFreehandPoints.length < 2) {
      setState(() {
        _draftFreehandPoints = <GraphPoint>[];
        _canvasStatus = 'Freehand stroke cancelled';
      });
      return;
    }

    final stroke = FreehandStroke(
      points: _draftFreehandPoints,
      color: _defaultFreehandColor,
      strokeWidth: _defaultFreehandWidth,
      opacity: _defaultFreehandOpacity,
    );

    setState(() {
      _freehandStrokes = <FreehandStroke>[..._freehandStrokes, stroke];
      _draftFreehandPoints = <GraphPoint>[];
      _undoStack.add(const _UndoEntry(_UndoKind.freehand));
      _selection = _Selection.freehand(_freehandStrokes.length - 1);
      _canvasStatus = 'Freehand stroke added';
    });
  }

  GraphPoint _snapWallPoint(GraphPoint point, GraphPoint? activeStart) {
    final gridPoint = _snapToGrid ? _snapPointToGrid(point) : point;

    if (activeStart == null || !_snapToObjects) {
      return gridPoint;
    }

    return _snapPointToAngle(activeStart, gridPoint);
  }

  GraphPoint _snapPointToGrid(GraphPoint point) {
    return GraphPoint(
      x: (point.x / _gridSnapSize).round() * _gridSnapSize,
      y: (point.y / _gridSnapSize).round() * _gridSnapSize,
    );
  }

  GraphPoint _snapPointToAngle(GraphPoint start, GraphPoint rawEnd) {
    final dx = rawEnd.x - start.x;
    final dy = rawEnd.y - start.y;
    final absDx = dx.abs();
    final absDy = dy.abs();
    final longestDelta = math.max(absDx, absDy);

    if (longestDelta < _minimumWallLength) {
      return rawEnd;
    }

    final angle = math.atan2(dy, dx);
    const snapStep = math.pi / 4;
    final snappedAngle = (angle / snapStep).round() * snapStep;
    final angleDifference = _smallestAngleDifference(angle, snappedAngle);

    if (angleDifference > _angleSnapToleranceRadians) {
      return rawEnd;
    }

    final sector = (snappedAngle / snapStep).round() % 8;

    switch (sector) {
      case 0:
        return GraphPoint(x: start.x + absDx, y: start.y);
      case 1:
        return GraphPoint(
          x: start.x + longestDelta,
          y: start.y + longestDelta,
        );
      case 2:
        return GraphPoint(x: start.x, y: start.y + absDy);
      case 3:
        return GraphPoint(
          x: start.x - longestDelta,
          y: start.y + longestDelta,
        );
      case 4:
        return GraphPoint(x: start.x - absDx, y: start.y);
      case 5:
        return GraphPoint(
          x: start.x - longestDelta,
          y: start.y - longestDelta,
        );
      case 6:
        return GraphPoint(x: start.x, y: start.y - absDy);
      case 7:
        return GraphPoint(
          x: start.x + longestDelta,
          y: start.y - longestDelta,
        );
    }

    return rawEnd;
  }

  double _smallestAngleDifference(double a, double b) {
    final difference = (a - b).abs() % (math.pi * 2);
    return difference > math.pi ? (math.pi * 2) - difference : difference;
  }

  GraphPoint? _findNearbyEndpoint(GraphPoint point) {
    if (!_snapToObjects) {
      return null;
    }

    GraphPoint? nearestEndpoint;
    var nearestDistance = _endpointSnapDistance;

    for (final endpoint in _existingEndpoints) {
      final distance = point.distanceTo(endpoint);

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestEndpoint = endpoint;
      }
    }

    return nearestEndpoint;
  }

  Iterable<GraphPoint> get _existingEndpoints sync* {
    for (final segment in _wallSegments) {
      yield segment.start;
      yield segment.end;
    }
  }

  Set<int> get _shapeSegmentIndexSet {
    return {
      for (final shape in _shapes)
        for (final index in shape.segmentIndexes)
          if (index >= 0 && index < _wallSegments.length) index,
    };
  }

  bool _selectExistingObjectAt(Offset canvasOffset) {
    final point = GraphPoint.fromOffset(canvasOffset);
    final selection = _selectionAt(point);
    if (selection == null) {
      return false;
    }

    setState(() {
      _selection = selection;
      _interaction.setSelected(_interactionReference(selection));
      _canvasStatus = _selectionStatus(selection);
    });
    return true;
  }

  void _selectObjectAt(Offset canvasOffset) {
    if (_selectExistingObjectAt(canvasOffset)) {
      return;
    }

    setState(() {
      _selection = null;
      _interaction.setSelected(null);
      _canvasStatus = 'Selection cleared';
    });
  }

  String _selectionStatus(_Selection selection) => switch (selection.kind) {
        _SelectionKind.annotation =>
          '${_annotations[selection.index].label} selected',
        _SelectionKind.shape => '${_shapes[selection.index].name} selected',
        _SelectionKind.freehand => 'Freehand stroke selected',
        _SelectionKind.segment => 'Line or arrow selected',
        _SelectionKind.trace => '${_traces[selection.index].label} selected',
      };

  EditorObjectReference _interactionReference(_Selection selection) =>
      EditorObjectReference(
        switch (selection.kind) {
          _SelectionKind.annotation => EditorObjectKind.annotation,
          _SelectionKind.shape => EditorObjectKind.shape,
          _SelectionKind.freehand => EditorObjectKind.freehand,
          _SelectionKind.segment => EditorObjectKind.segment,
          _SelectionKind.trace => EditorObjectKind.trace,
        },
        selection.index,
      );

  _Selection? _selectionAt(GraphPoint point) {
    final annotationIndex = _nearestAnnotationIndex(point);
    if (annotationIndex != null) {
      return _Selection.annotation(annotationIndex);
    }

    final traceIndex = _traceIndexAt(point);
    if (traceIndex != null) {
      return _Selection.trace(traceIndex);
    }

    final shapeIndex = _shapeIndexAt(point);
    if (shapeIndex != null) {
      return _Selection.shape(shapeIndex);
    }

    final freehandIndex = _nearestFreehandIndex(point);
    if (freehandIndex != null) {
      return _Selection.freehand(freehandIndex);
    }

    final segmentIndex = _nearestSegmentIndex(point);
    return segmentIndex == null ? null : _Selection.segment(segmentIndex);
  }

  int? _traceIndexAt(GraphPoint point) {
    if (!_traceLayerVisible) return null;
    for (var i = _traces.length - 1; i >= 0; i -= 1) {
      final trace = _traces[i];
      if (trace.canvasPoints.isEmpty) continue;
      for (final vertex in trace.canvasPoints) {
        if (vertex.distanceTo(point) <= _handleHitDistance) return i;
      }
      for (var p = 1; p < trace.canvasPoints.length; p += 1) {
        if (_distanceToLinePoints(
              point,
              trace.canvasPoints[p - 1],
              trace.canvasPoints[p],
            ) <=
            _objectHitDistance) {
          return i;
        }
      }
      if (trace.closed && trace.canvasPoints.length > 2) {
        if (_distanceToLinePoints(
              point,
              trace.canvasPoints.last,
              trace.canvasPoints.first,
            ) <=
            _objectHitDistance) {
          return i;
        }
        final path = Path()
          ..moveTo(trace.canvasPoints.first.x, trace.canvasPoints.first.y);
        for (final vertex in trace.canvasPoints.skip(1)) {
          path.lineTo(vertex.x, vertex.y);
        }
        path.close();
        if (path.contains(point.offset)) return i;
      }
    }
    return null;
  }

  int? _nearestAnnotationIndex(GraphPoint point) {
    for (var i = _annotations.length - 1; i >= 0; i -= 1) {
      if (!_isAnnotationVisible(_annotations[i])) {
        continue;
      }

      final distance = _annotations[i].point.distanceTo(point);
      final annotation = _annotations[i];
      final hitRadius = annotation.kind == GraphAnnotationKind.marker
          ? math.max(_objectHitDistance, 19 * annotation.size)
          : _objectHitDistance + 4;
      if (distance <= hitRadius) {
        return i;
      }
    }

    return null;
  }

  int? _nearestSegmentIndex(GraphPoint point) {
    if (!_isLayerVisible(_GraphLayer.structure)) {
      return null;
    }

    final shapeSegmentIndexes = _shapeSegmentIndexSet;
    final draftStart =
        _interaction.drawingSession == EditorDrawingSession.plottingStructure
            ? _activePathStartSegmentIndex
            : null;

    for (var i = _wallSegments.length - 1; i >= 0; i -= 1) {
      if (shapeSegmentIndexes.contains(i) ||
          (draftStart != null && i >= draftStart)) {
        continue;
      }

      final segment = _wallSegments[i];
      final distance = _distanceToSegment(point, segment);

      if (distance <=
          math.max(_objectHitDistance, (segment.strokeWidth / 2) + 7)) {
        return i;
      }
    }

    return null;
  }

  double _distanceToSegment(GraphPoint point, WallSegment segment) {
    final a = segment.start.offset;
    final b = segment.end.offset;
    final p = point.offset;
    final ab = b - a;
    final ap = p - a;
    final abLengthSquared = (ab.dx * ab.dx) + (ab.dy * ab.dy);

    if (abLengthSquared == 0) {
      return (p - a).distance;
    }

    final t =
        (((ap.dx * ab.dx) + (ap.dy * ab.dy)) / abLengthSquared).clamp(0.0, 1.0);
    final projection = Offset(a.dx + (ab.dx * t), a.dy + (ab.dy * t));

    return (p - projection).distance;
  }

  int? _nearestFreehandIndex(GraphPoint point) {
    if (!_isLayerVisible(_GraphLayer.structure)) {
      return null;
    }

    for (var i = _freehandStrokes.length - 1; i >= 0; i -= 1) {
      final stroke = _freehandStrokes[i];
      for (var p = 1; p < stroke.points.length; p += 1) {
        final distance = _distanceToLinePoints(
          point,
          stroke.points[p - 1],
          stroke.points[p],
        );
        if (distance <=
            math.max(_objectHitDistance, (stroke.strokeWidth / 2) + 7)) {
          return i;
        }
      }
    }

    return null;
  }

  double _distanceToLinePoints(
      GraphPoint point, GraphPoint start, GraphPoint end) {
    return _distanceToSegment(point, WallSegment(start: start, end: end));
  }

  int? _shapeIndexAt(GraphPoint point) {
    if (!_isLayerVisible(_GraphLayer.shapes) &&
        !_isLayerVisible(_GraphLayer.treatment)) {
      return null;
    }

    for (var i = _shapes.length - 1; i >= 0; i -= 1) {
      final shape = _shapes[i];
      final visible = _isTreatmentShape(shape)
          ? _isLayerVisible(_GraphLayer.treatment)
          : _isLayerVisible(_GraphLayer.structure) &&
              _isLayerVisible(_GraphLayer.shapes);
      if (!visible) continue;
      final path = _shapePath(shape);
      if (path == null) {
        continue;
      }

      final hasVisibleFill =
          shape.closed && shape.fillColor != null && shape.fillOpacity > 0.01;
      final containsPoint = hasVisibleFill && path.contains(point.offset);
      final nearEdge = shape.segmentIndexes.any((segmentIndex) {
        if (segmentIndex < 0 || segmentIndex >= _wallSegments.length) {
          return false;
        }
        return _distanceToSegment(point, _wallSegments[segmentIndex]) <=
            math.max(_objectHitDistance, (shape.borderWidth / 2) + 7);
      });
      if (containsPoint || nearEdge) {
        return i;
      }
    }

    return null;
  }

  Rect? _shapeBounds(GraphShape shape) {
    final path = _shapePath(shape);
    if (path == null) {
      return null;
    }

    return path.getBounds();
  }

  Path? _shapePath(GraphShape shape) {
    final shapeSegments = <WallSegment>[];

    for (final index in shape.segmentIndexes) {
      if (index < 0 || index >= _wallSegments.length) {
        continue;
      }

      shapeSegments.add(_wallSegments[index]);
    }

    if (shapeSegments.isEmpty) {
      return null;
    }

    final path = Path()
      ..moveTo(shapeSegments.first.start.x, shapeSegments.first.start.y);

    for (final segment in shapeSegments) {
      final controlPoint = segment.controlPoint;
      if (controlPoint == null) {
        path.lineTo(segment.end.x, segment.end.y);
      } else {
        path.quadraticBezierTo(
          controlPoint.x,
          controlPoint.y,
          segment.end.x,
          segment.end.y,
        );
      }
    }

    if (shape.closed) {
      path.close();
    }

    return path;
  }

  void _startDragForSelection(_Selection selection, GraphPoint point) {
    final target = _dragTargetForSelection(selection, point);
    if (target == null) {
      return;
    }

    _activeDragTarget = target;
    _dragOriginalWallSegments = <WallSegment>[..._wallSegments];
    _dragOriginalAnnotations = <GraphAnnotation>[..._annotations];
    _dragOriginalShapes = <GraphShape>[..._shapes];
    _dragOriginalFreehandStrokes = <FreehandStroke>[..._freehandStrokes];
    _dragOriginalTraces = <TraceGeometry>[..._traces];
    _dragOriginalActiveWallStart = _activeWallStart;
    _dragOriginalActivePathStartPoint = _activePathStartPoint;
    _dragOriginalActivePathStartSegmentIndex = _activePathStartSegmentIndex;
    _dragMoved = false;
    _interaction.setDrawingSession(EditorDrawingSession.movingObject);
  }

  _DragTarget? _dragTargetForSelection(
    _Selection selection,
    GraphPoint point,
  ) {
    if (!_isSelectionEditable(selection)) {
      return null;
    }

    return switch (selection.kind) {
      _SelectionKind.annotation => _DragTarget.annotation(
          annotationIndex: selection.index,
          distance: _annotations[selection.index].point.distanceTo(point),
        ),
      _SelectionKind.shape =>
        _nearestShapeVertexTarget(selection.index, point) ??
            _nearestShapeResizeTarget(selection.index, point) ??
            _nearestShapeRotationTarget(selection.index, point) ??
            _DragTarget.shape(
              shapeIndex: selection.index,
              distance: 0,
              originalPoint: point,
            ),
      _SelectionKind.freehand => _DragTarget.freehand(
          freehandIndex: selection.index,
          distance: 0,
          originalPoint: point,
        ),
      _SelectionKind.segment => _nearestEndpointTarget(point) ??
          _DragTarget.segment(
            segmentIndex: selection.index,
            distance: _distanceToSegment(point, _wallSegments[selection.index]),
            originalPoint: point,
          ),
      _SelectionKind.trace =>
        _nearestTraceVertexTarget(selection.index, point) ??
            _nearestTraceRotationTarget(selection.index, point) ??
            _DragTarget.traceMove(
              traceIndex: selection.index,
              originalPoint: point,
            ),
    };
  }

  _DragTarget? _nearestTraceVertexTarget(int traceIndex, GraphPoint point) {
    if (traceIndex < 0 || traceIndex >= _traces.length) return null;
    final trace = _traces[traceIndex];
    var nearestDistance = _handleHitDistance;
    int? nearestVertexIndex;
    for (var i = 0; i < trace.canvasPoints.length; i += 1) {
      final distance = trace.canvasPoints[i].distanceTo(point);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestVertexIndex = i;
      }
    }
    if (nearestVertexIndex == null) return null;
    return _DragTarget.traceVertex(
      traceIndex: traceIndex,
      traceVertexIndex: nearestVertexIndex,
      originalPoint: trace.canvasPoints[nearestVertexIndex],
      distance: nearestDistance,
    );
  }

  _DragTarget? _nearestTraceRotationTarget(int traceIndex, GraphPoint point) {
    if (traceIndex < 0 || traceIndex >= _traces.length) return null;
    final trace = _traces[traceIndex];
    final handleCenter = TraceGeometryPainter.rotationHandleCenter(trace);
    final bounds = TraceGeometryPainter.canvasBounds(trace);
    if (handleCenter == null || bounds == null) return null;
    final distance = (point.offset - handleCenter).distance;
    if (distance > _handleHitDistance) return null;
    return _DragTarget.traceRotation(
      traceIndex: traceIndex,
      distance: distance,
      originalPoint: point,
      traceCenter: GraphPoint.fromOffset(bounds.center),
      initialAngleRadians: math.atan2(
        point.y - bounds.center.dy,
        point.x - bounds.center.dx,
      ),
    );
  }

  _DragTarget? _nearestShapeVertexTarget(
    int selectedShapeIndex,
    GraphPoint point,
  ) {
    if (selectedShapeIndex < 0 || selectedShapeIndex >= _shapes.length) {
      return null;
    }
    final shape = _shapes[selectedShapeIndex];
    if (!_shapeSupportsVertexEditing(shape) || !_shapeCanBeEdited(shape)) {
      return null;
    }

    GraphPoint? nearest;
    var nearestDistance = _handleHitDistance;
    for (final segmentIndex in _uniqueShapeSegmentIndexes(shape)) {
      if (segmentIndex < 0 || segmentIndex >= _wallSegments.length) continue;
      final segment = _wallSegments[segmentIndex];
      for (final candidate in [segment.start, segment.end]) {
        final distance = candidate.distanceTo(point);
        if (distance < nearestDistance) {
          nearest = candidate;
          nearestDistance = distance;
        }
      }
    }
    if (nearest == null) return null;

    final refs = <_SegmentEndpointRef>[];
    for (final segmentIndex in _uniqueShapeSegmentIndexes(shape)) {
      if (segmentIndex < 0 || segmentIndex >= _wallSegments.length) continue;
      final segment = _wallSegments[segmentIndex];
      if (_pointMatches(segment.start, nearest)) {
        refs.add(
            _SegmentEndpointRef(segmentIndex: segmentIndex, isStart: true));
      }
      if (_pointMatches(segment.end, nearest)) {
        refs.add(
            _SegmentEndpointRef(segmentIndex: segmentIndex, isStart: false));
      }
    }
    return _DragTarget.wallEndpoint(
      endpointRefs: refs,
      movesActiveWallStart: false,
      movesActivePathStart: false,
      originalPoint: nearest,
      distance: nearestDistance,
    );
  }

  _DragTarget? _nearestShapeResizeTarget(
    int selectedShapeIndex,
    GraphPoint point,
  ) {
    if (selectedShapeIndex < 0 || selectedShapeIndex >= _shapes.length) {
      return null;
    }
    if (!_shapeCanBeEdited(_shapes[selectedShapeIndex])) return null;

    final bounds = _shapeBounds(_shapes[selectedShapeIndex]);
    if (bounds == null) {
      return null;
    }

    final handles = [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ];

    for (var i = 0; i < handles.length; i += 1) {
      final distance = (point.offset - handles[i]).distance;
      if (distance <= _handleHitDistance) {
        return _DragTarget.shapeResize(
          shapeIndex: selectedShapeIndex,
          distance: distance,
          originalPoint: point,
          originalBounds: bounds,
          resizeHandleIndex: i,
        );
      }
    }

    return null;
  }

  _DragTarget? _nearestShapeRotationTarget(
    int selectedShapeIndex,
    GraphPoint point,
  ) {
    if (selectedShapeIndex < 0 || selectedShapeIndex >= _shapes.length) {
      return null;
    }
    if (!_shapeCanBeEdited(_shapes[selectedShapeIndex])) return null;

    final bounds = _shapeBounds(_shapes[selectedShapeIndex]);
    if (bounds == null) {
      return null;
    }

    final handleCenter = bounds.topCenter - const Offset(0, 28);
    final distance = (point.offset - handleCenter).distance;
    if (distance > _handleHitDistance) {
      return null;
    }

    return _DragTarget.shapeRotation(
      shapeIndex: selectedShapeIndex,
      distance: distance,
      originalPoint: point,
      shapeCenter: GraphPoint.fromOffset(bounds.center),
      initialAngleRadians: math.atan2(
        point.y - bounds.center.dy,
        point.x - bounds.center.dx,
      ),
      originalRotationDegrees: _shapes[selectedShapeIndex].rotationDegrees,
    );
  }

  bool _shapeCanBeEdited(GraphShape shape) {
    if (_isTreatmentShape(shape)) {
      return _isLayerVisible(_GraphLayer.treatment) &&
          !_isLayerLocked(_GraphLayer.treatment);
    }
    return _isLayerVisible(_GraphLayer.structure) &&
        _isLayerVisible(_GraphLayer.shapes) &&
        !_isLayerLocked(_GraphLayer.structure) &&
        !_isLayerLocked(_GraphLayer.shapes);
  }

  bool _shapeSupportsVertexEditing(GraphShape shape) {
    final kind = shape.extraProperties['basicShapeKind']?.toString();
    if (kind == CanvasTool.circle.name || kind == CanvasTool.ellipse.name) {
      return false;
    }
    final legacyName = shape.name.toLowerCase();
    return !legacyName.startsWith('circle') &&
        !legacyName.startsWith('ellipse');
  }

  _DragTarget? _nearestEndpointTarget(GraphPoint point) {
    if (!_isLayerVisible(_GraphLayer.structure)) {
      return null;
    }

    GraphPoint? nearestPoint;
    var nearestDistance = _handleHitDistance;

    for (final endpoint in _allMoveableEndpoints) {
      final distance = endpoint.distanceTo(point);

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestPoint = endpoint;
      }
    }

    if (nearestPoint == null) {
      return null;
    }

    return _DragTarget.wallEndpoint(
      endpointRefs: _endpointRefsForPoint(nearestPoint),
      movesActiveWallStart: _pointMatches(_activeWallStart, nearestPoint),
      movesActivePathStart: _pointMatches(_activePathStartPoint, nearestPoint),
      originalPoint: nearestPoint,
      distance: nearestDistance,
    );
  }

  Iterable<GraphPoint> get _allMoveableEndpoints sync* {
    final shapeSegmentIndexes = _shapeSegmentIndexSet;

    for (var i = 0; i < _wallSegments.length; i += 1) {
      if (shapeSegmentIndexes.contains(i)) {
        continue;
      }

      final segment = _wallSegments[i];
      yield segment.start;
      yield segment.end;
    }

    final activeWallStart = _activeWallStart;
    if (activeWallStart != null) {
      yield activeWallStart;
    }
  }

  List<_SegmentEndpointRef> _endpointRefsForPoint(GraphPoint point) {
    final refs = <_SegmentEndpointRef>[];
    final shapeSegmentIndexes = _shapeSegmentIndexSet;

    for (var i = 0; i < _wallSegments.length; i += 1) {
      if (shapeSegmentIndexes.contains(i)) {
        continue;
      }

      final segment = _wallSegments[i];

      if (_pointMatches(segment.start, point)) {
        refs.add(_SegmentEndpointRef(segmentIndex: i, isStart: true));
      }

      if (_pointMatches(segment.end, point)) {
        refs.add(_SegmentEndpointRef(segmentIndex: i, isStart: false));
      }
    }

    return refs;
  }

  bool _pointMatches(GraphPoint? a, GraphPoint b) {
    return a != null && a.distanceTo(b) <= 0.5;
  }

  void _moveActiveTarget(GraphPoint point) {
    final target = _activeDragTarget;
    if (target == null) {
      return;
    }

    switch (target.kind) {
      case _DragKind.annotation:
        _moveAnnotation(target, point);
        return;
      case _DragKind.wallEndpoint:
        _moveWallEndpoint(
            target, _snapToGrid ? _snapPointToGrid(point) : point);
        return;
      case _DragKind.shape:
        _moveShape(target, point);
        return;
      case _DragKind.shapeResize:
        _resizeShape(target, point);
        return;
      case _DragKind.shapeRotation:
        _rotateShape(target, point);
        return;
      case _DragKind.freehand:
        _moveFreehand(target, point);
        return;
      case _DragKind.segment:
        _moveSegment(target, point);
        return;
      case _DragKind.traceVertex:
        _moveTraceVertex(target, point);
        return;
      case _DragKind.traceMove:
        _moveTrace(target, point);
        return;
      case _DragKind.traceRotation:
        _rotateTrace(target, point);
        return;
    }
  }

  void _moveTraceVertex(_DragTarget target, GraphPoint point) {
    final traceIndex = target.traceIndex;
    final vertexIndex = target.traceVertexIndex;
    final originalPoint = target.originalPoint;
    final sourceTraces = _dragOriginalTraces ?? _traces;
    if (traceIndex == null ||
        vertexIndex == null ||
        originalPoint == null ||
        traceIndex < 0 ||
        traceIndex >= sourceTraces.length) {
      return;
    }
    final sourceTrace = sourceTraces[traceIndex];
    if (vertexIndex < 0 ||
        vertexIndex >= sourceTrace.canvasPoints.length ||
        vertexIndex >= sourceTrace.geoPoints.length) {
      return;
    }
    final metersPerCanvasUnit = sourceTrace.metersPerCanvasUnit;
    if (metersPerCanvasUnit == null || metersPerCanvasUnit <= 0) return;
    final canvasDelta = point.offset - originalPoint.offset;
    final nextCanvasPoints = <GraphPoint>[...sourceTrace.canvasPoints];
    final nextGeoPoints = <GeoPoint>[...sourceTrace.geoPoints];
    nextCanvasPoints[vertexIndex] = point;
    nextGeoPoints[vertexIndex] =
        TraceProjectionService.moveGeoPointByCanvasDelta(
      point: sourceTrace.geoPoints[vertexIndex],
      canvasDelta: canvasDelta,
      metersPerCanvasUnit: metersPerCanvasUnit,
    );
    final nextTraces = <TraceGeometry>[..._traces];
    nextTraces[traceIndex] = sourceTrace.copyWith(
      canvasPoints: nextCanvasPoints,
      geoPoints: nextGeoPoints,
    );
    setState(() {
      _document.replaceTraces(nextTraces);
      _dragMoved = true;
    });
  }

  void _moveTrace(_DragTarget target, GraphPoint point) {
    final traceIndex = target.traceIndex;
    final originalPoint = target.originalPoint;
    final sourceTraces = _dragOriginalTraces ?? _traces;
    if (traceIndex == null ||
        originalPoint == null ||
        traceIndex < 0 ||
        traceIndex >= sourceTraces.length) {
      return;
    }
    final sourceTrace = sourceTraces[traceIndex];
    final delta = point.offset - originalPoint.offset;
    final metersPerCanvasUnit = sourceTrace.metersPerCanvasUnit;
    final nextGeoPoints =
        metersPerCanvasUnit == null || metersPerCanvasUnit <= 0
            ? sourceTrace.geoPoints
            : [
                for (final geoPoint in sourceTrace.geoPoints)
                  TraceProjectionService.moveGeoPointByCanvasDelta(
                    point: geoPoint,
                    canvasDelta: delta,
                    metersPerCanvasUnit: metersPerCanvasUnit,
                  ),
              ];
    final nextTraces = <TraceGeometry>[..._traces];
    nextTraces[traceIndex] = sourceTrace.copyWith(
      canvasPoints: [
        for (final canvasPoint in sourceTrace.canvasPoints)
          GraphPoint.fromOffset(canvasPoint.offset + delta),
      ],
      geoPoints: nextGeoPoints,
    );
    setState(() {
      _document.replaceTraces(nextTraces);
      _dragMoved = true;
    });
  }

  void _rotateTrace(_DragTarget target, GraphPoint point) {
    final traceIndex = target.traceIndex;
    final traceCenter = target.traceCenter;
    final sourceTraces = _dragOriginalTraces ?? _traces;
    if (traceIndex == null ||
        traceCenter == null ||
        traceIndex < 0 ||
        traceIndex >= sourceTraces.length) {
      return;
    }
    final currentAngle = math.atan2(
      point.y - traceCenter.y,
      point.x - traceCenter.x,
    );
    final deltaRadians = currentAngle - target.initialAngleRadians;
    final sourceTrace = sourceTraces[traceIndex];
    final nextTraces = <TraceGeometry>[..._traces];
    // Rotation is a canvas presentation edit. Geographic vertices remain the
    // source of truth for the property's map-derived measurements.
    nextTraces[traceIndex] = sourceTrace.copyWith(
      canvasPoints: [
        for (final canvasPoint in sourceTrace.canvasPoints)
          GraphPoint.fromOffset(
            _rotateOffset(canvasPoint.offset, traceCenter.offset, deltaRadians),
          ),
      ],
    );
    setState(() {
      _document.replaceTraces(nextTraces);
      _dragMoved = true;
    });
  }

  void _moveSegment(_DragTarget target, GraphPoint point) {
    final index = target.segmentIndex;
    final originalPoint = target.originalPoint;
    final sourceSegments = _dragOriginalWallSegments ?? _wallSegments;
    if (index == null ||
        originalPoint == null ||
        index < 0 ||
        index >= sourceSegments.length) {
      return;
    }

    final delta = point.offset - originalPoint.offset;
    final nextSegments = <WallSegment>[..._wallSegments];
    nextSegments[index] = _translateSegment(sourceSegments[index], delta);
    setState(() {
      _wallSegments = nextSegments;
      _dragMoved = true;
    });
  }

  void _moveAnnotation(_DragTarget target, GraphPoint point) {
    final index = target.annotationIndex;
    if (index == null || index < 0 || index >= _annotations.length) {
      return;
    }

    final nextAnnotations = <GraphAnnotation>[..._annotations];
    nextAnnotations[index] = nextAnnotations[index].copyWith(point: point);

    setState(() {
      _annotations = nextAnnotations;
      _dragMoved = true;
    });
  }

  void _moveWallEndpoint(_DragTarget target, GraphPoint point) {
    final originalPoint = target.originalPoint;
    if (originalPoint == null) {
      return;
    }

    final delta = Offset(point.x - originalPoint.x, point.y - originalPoint.y);
    final sourceSegments = _dragOriginalWallSegments ?? _wallSegments;
    final nextSegments = <WallSegment>[..._wallSegments];

    for (final ref in target.endpointRefs) {
      if (ref.segmentIndex < 0 ||
          ref.segmentIndex >= nextSegments.length ||
          ref.segmentIndex >= sourceSegments.length) {
        continue;
      }

      final segment = sourceSegments[ref.segmentIndex];
      final movedControlPoint = segment.controlPoint == null
          ? null
          : GraphPoint(
              x: segment.controlPoint!.x + (delta.dx * 0.5),
              y: segment.controlPoint!.y + (delta.dy * 0.5),
            );

      nextSegments[ref.segmentIndex] = ref.isStart
          ? segment.copyWith(start: point, controlPoint: movedControlPoint)
          : segment.copyWith(end: point, controlPoint: movedControlPoint);
    }

    setState(() {
      _wallSegments = nextSegments;
      if (target.movesActiveWallStart) {
        _activeWallStart = point;
      }
      if (target.movesActivePathStart) {
        _activePathStartPoint = point;
      }
      _dragMoved = true;
    });
  }

  void _moveShape(_DragTarget target, GraphPoint point) {
    final shapeIndex = target.shapeIndex;
    final originalPoint = target.originalPoint;
    if (shapeIndex == null ||
        originalPoint == null ||
        shapeIndex < 0 ||
        shapeIndex >= _shapes.length) {
      return;
    }

    final delta = Offset(point.x - originalPoint.x, point.y - originalPoint.y);
    final sourceSegments = _dragOriginalWallSegments ?? _wallSegments;
    final nextSegments = <WallSegment>[..._wallSegments];

    for (final segmentIndex
        in _uniqueShapeSegmentIndexes(_shapes[shapeIndex])) {
      if (segmentIndex < 0 ||
          segmentIndex >= nextSegments.length ||
          segmentIndex >= sourceSegments.length) {
        continue;
      }

      nextSegments[segmentIndex] = _translateSegment(
        sourceSegments[segmentIndex],
        delta,
      );
    }

    setState(() {
      _wallSegments = nextSegments;
      _dragMoved = true;
    });
  }

  void _moveFreehand(_DragTarget target, GraphPoint point) {
    final index = target.freehandIndex;
    final originalPoint = target.originalPoint;
    if (index == null ||
        originalPoint == null ||
        index < 0 ||
        index >= _freehandStrokes.length) {
      return;
    }

    final sourceStrokes = _dragOriginalFreehandStrokes ?? _freehandStrokes;
    if (index >= sourceStrokes.length) {
      return;
    }

    final delta = Offset(point.x - originalPoint.x, point.y - originalPoint.y);
    final nextStrokes = <FreehandStroke>[..._freehandStrokes];
    final stroke = sourceStrokes[index];
    nextStrokes[index] = stroke.copyWith(
      points: [
        for (final strokePoint in stroke.points)
          GraphPoint.fromOffset(strokePoint.offset + delta),
      ],
    );

    setState(() {
      _freehandStrokes = nextStrokes;
      _dragMoved = true;
    });
  }

  void _resizeShape(_DragTarget target, GraphPoint point) {
    final shapeIndex = target.shapeIndex;
    final originalBounds = target.originalBounds;
    if (shapeIndex == null ||
        originalBounds == null ||
        shapeIndex < 0 ||
        shapeIndex >= _shapes.length) {
      return;
    }

    final nextBounds = _boundsForResizeHandle(
      originalBounds,
      target.resizeHandleIndex,
      point.offset,
    );
    if (nextBounds.width < 24 || nextBounds.height < 24) {
      return;
    }

    final sourceSegments = _dragOriginalWallSegments ?? _wallSegments;
    final sourceShapes = _dragOriginalShapes ?? _shapes;
    final nextSegments = <WallSegment>[..._wallSegments];

    for (final segmentIndex
        in _uniqueShapeSegmentIndexes(sourceShapes[shapeIndex])) {
      if (segmentIndex < 0 ||
          segmentIndex >= nextSegments.length ||
          segmentIndex >= sourceSegments.length) {
        continue;
      }

      nextSegments[segmentIndex] = _resizeSegment(
        sourceSegments[segmentIndex],
        originalBounds,
        nextBounds,
      );
    }

    setState(() {
      _wallSegments = nextSegments;
      _dragMoved = true;
    });
  }

  Rect _boundsForResizeHandle(
    Rect originalBounds,
    int handleIndex,
    Offset point,
  ) {
    return switch (handleIndex) {
      0 => Rect.fromPoints(point, originalBounds.bottomRight),
      1 => Rect.fromPoints(point, originalBounds.bottomLeft),
      2 => Rect.fromPoints(originalBounds.topLeft, point),
      3 => Rect.fromPoints(originalBounds.topRight, point),
      _ => originalBounds,
    };
  }

  WallSegment _resizeSegment(
    WallSegment segment,
    Rect from,
    Rect to,
  ) {
    return segment.copyWith(
      start: _resizePoint(segment.start, from, to),
      end: _resizePoint(segment.end, from, to),
      controlPoint: segment.controlPoint == null
          ? null
          : _resizePoint(segment.controlPoint!, from, to),
    );
  }

  GraphPoint _resizePoint(GraphPoint point, Rect from, Rect to) {
    final xRatio = from.width == 0 ? 0 : (point.x - from.left) / from.width;
    final yRatio = from.height == 0 ? 0 : (point.y - from.top) / from.height;
    return GraphPoint(
      x: to.left + (to.width * xRatio),
      y: to.top + (to.height * yRatio),
    );
  }

  void _rotateShape(_DragTarget target, GraphPoint point) {
    final shapeIndex = target.shapeIndex;
    final shapeCenter = target.shapeCenter;
    if (shapeIndex == null ||
        shapeCenter == null ||
        shapeIndex < 0 ||
        shapeIndex >= _shapes.length) {
      return;
    }

    final currentAngle = math.atan2(
      point.y - shapeCenter.y,
      point.x - shapeCenter.x,
    );
    final deltaRadians = currentAngle - target.initialAngleRadians;
    final center = shapeCenter.offset;
    final sourceSegments = _dragOriginalWallSegments ?? _wallSegments;
    final sourceShapes = _dragOriginalShapes ?? _shapes;
    final nextSegments = <WallSegment>[..._wallSegments];
    final nextShapes = <GraphShape>[..._shapes];

    for (final segmentIndex
        in _uniqueShapeSegmentIndexes(sourceShapes[shapeIndex])) {
      if (segmentIndex < 0 ||
          segmentIndex >= nextSegments.length ||
          segmentIndex >= sourceSegments.length) {
        continue;
      }

      nextSegments[segmentIndex] = _rotateSegment(
        sourceSegments[segmentIndex],
        center,
        deltaRadians,
      );
    }

    nextShapes[shapeIndex] = sourceShapes[shapeIndex].copyWith(
      rotationDegrees: _normalizeDegrees(
        target.originalRotationDegrees + _radiansToDegrees(deltaRadians),
      ),
    );

    setState(() {
      _wallSegments = nextSegments;
      _shapes = nextShapes;
      _dragMoved = true;
    });
  }

  List<int> _uniqueShapeSegmentIndexes(GraphShape shape) {
    return shape.segmentIndexes.toSet().toList();
  }

  WallSegment _translateSegment(WallSegment segment, Offset delta) {
    return segment.copyWith(
      start: GraphPoint.fromOffset(segment.start.offset + delta),
      end: GraphPoint.fromOffset(segment.end.offset + delta),
      controlPoint: segment.controlPoint == null
          ? null
          : GraphPoint.fromOffset(segment.controlPoint!.offset + delta),
    );
  }

  WallSegment _rotateSegment(
    WallSegment segment,
    Offset center,
    double radians,
  ) {
    return segment.copyWith(
      start: GraphPoint.fromOffset(
        _rotateOffset(segment.start.offset, center, radians),
      ),
      end: GraphPoint.fromOffset(
        _rotateOffset(segment.end.offset, center, radians),
      ),
      controlPoint: segment.controlPoint == null
          ? null
          : GraphPoint.fromOffset(
              _rotateOffset(segment.controlPoint!.offset, center, radians),
            ),
    );
  }

  Offset _rotateOffset(Offset point, Offset center, double radians) {
    final translated = point - center;
    final cosTheta = math.cos(radians);
    final sinTheta = math.sin(radians);

    return Offset(
          (translated.dx * cosTheta) - (translated.dy * sinTheta),
          (translated.dx * sinTheta) + (translated.dy * cosTheta),
        ) +
        center;
  }

  double _radiansToDegrees(double radians) => radians * 180 / math.pi;

  double _normalizeDegrees(double degrees) {
    final normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  void _finishActiveDrag() {
    if (!_dragMoved) {
      return;
    }

    final originalWallSegments = _dragOriginalWallSegments;
    final originalAnnotations = _dragOriginalAnnotations;
    final originalShapes = _dragOriginalShapes;
    final originalFreehandStrokes = _dragOriginalFreehandStrokes;
    final originalTraces = _dragOriginalTraces;

    if (originalWallSegments == null ||
        originalAnnotations == null ||
        originalShapes == null ||
        originalFreehandStrokes == null ||
        originalTraces == null) {
      return;
    }

    setState(() {
      _undoStack.add(
        _UndoEntry(
          _UndoKind.move,
          previousWallSegments: originalWallSegments,
          previousAnnotations: originalAnnotations,
          previousShapes: originalShapes,
          previousFreehandStrokes: originalFreehandStrokes,
          previousTraces: originalTraces,
          previousActiveWallStart: _dragOriginalActiveWallStart,
          previousActivePathStartPoint: _dragOriginalActivePathStartPoint,
          previousActivePathStartSegmentIndex:
              _dragOriginalActivePathStartSegmentIndex,
        ),
      );
      _canvasStatus = 'Move saved';
    });
  }

  Future<void> _addPlaceholderAnnotation(Offset canvasOffset) async {
    final tappedPoint = GraphPoint.fromOffset(canvasOffset);
    var annotation = _buildAnnotationForSelectedTool(tappedPoint);
    final layer = _layerForAnnotation(annotation);

    if (_isLayerLocked(layer)) {
      _showCanvasMessage(
        layer == _GraphLayer.photos
            ? 'Photos layer is locked'
            : '${_layerLabel(layer)} layer is locked',
      );
      return;
    }

    if (annotation.kind == GraphAnnotationKind.photo) {
      await _addPhotoMarker(tappedPoint);
      return;
    }

    if (annotation.kind == GraphAnnotationKind.marker &&
        annotation.markerType == GraphMarkerType.moisture) {
      final moisture = await _showTextLabelDialog(
        title: 'Moisture percentage',
        initialText: '15%',
      );
      if (!mounted || moisture == null) {
        return;
      }
      final value = double.tryParse(moisture.replaceAll('%', '').trim());
      if (value == null || value < 0) {
        _showCanvasMessage('Enter a valid moisture percentage');
        return;
      }
      final condition = value > 20
          ? 'Immediate Attention Needed'
          : value >= 10 && value <= 15
              ? 'Good'
              : 'High Moisture';
      final formatted = '${value.round()}% — $condition';
      annotation = annotation.copyWith(
        label: formatted,
        note: formatted,
        color: moistureMarkerColor(value),
      );
    } else if (annotation.kind == GraphAnnotationKind.marker &&
        annotation.markerType == GraphMarkerType.treatmentNote) {
      final note = await _showTextLabelDialog(
        title: 'Treatment note',
        initialText: 'Treatment Note',
      );
      if (!mounted || note == null) {
        return;
      }
      annotation = annotation.copyWith(label: note, note: note);
    }

    setState(() {
      _annotations = <GraphAnnotation>[..._annotations, annotation];
      _undoStack.add(const _UndoEntry(_UndoKind.annotation));
      _canvasStatus = '${annotation.label} placed';
    });
  }

  void _handleTextTap(Offset canvasOffset) {
    if (_isLayerLocked(_GraphLayer.inspections)) {
      _showCanvasMessage('Inspections layer is locked');
      return;
    }

    final existingTextIndex = _findTextAnnotationIndex(canvasOffset);

    if (existingTextIndex != null) {
      _editTextAnnotation(existingTextIndex);
      return;
    }

    _addTextAnnotation(canvasOffset);
  }

  void _addTextAnnotation(Offset canvasOffset) {
    final annotation = GraphAnnotation(
      kind: GraphAnnotationKind.text,
      point: GraphPoint.fromOffset(canvasOffset),
      label: '',
      fontSize: _defaultTextFontSize,
      bold: _defaultTextBold,
      textColor: _defaultTextColor,
      backgroundColor: _defaultTextBackground,
      borderColor: _defaultTextBorder,
    );

    setState(() {
      _annotations = <GraphAnnotation>[..._annotations, annotation];
      _selection = _Selection.annotation(_annotations.length - 1);
      _interaction.setSelected(_interactionReference(_selection!));
      _canvasStatus = 'Type the note on the graph';
    });
    _beginInlineTextEditing(_annotations.length - 1, isNew: true);
  }

  void _editTextAnnotation(int index) {
    if (index < 0 || index >= _annotations.length) {
      return;
    }
    _beginInlineTextEditing(index);
  }

  void _beginInlineTextEditing(int index, {bool isNew = false}) {
    if (index < 0 || index >= _annotations.length) return;
    final annotation = _annotations[index];
    _inlineTextController.value = TextEditingValue(
      text: isNew ? '' : annotation.label,
      selection: TextSelection.collapsed(
        offset: isNew ? 0 : annotation.label.length,
      ),
    );

    setState(() {
      _inlineTextAnnotationIndex = index;
      _inlineTextPreviousAnnotation = annotation;
      _inlineTextIsNew = isNew;
      _interaction.setTextEditing(true);
      _canvasStatus = 'Type directly on the graph, then press Enter';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isInlineTextEditing) {
        _inlineTextFocusNode.requestFocus();
      }
    });
  }

  void _finishInlineTextEditing() {
    final index = _inlineTextAnnotationIndex;
    final previous = _inlineTextPreviousAnnotation;
    if (index == null || previous == null || index >= _annotations.length) {
      return;
    }

    final text = _inlineTextController.text.trim();
    final isNew = _inlineTextIsNew;
    final nextAnnotations = <GraphAnnotation>[..._annotations];
    if (text.isEmpty && isNew) {
      nextAnnotations.removeAt(index);
      setState(() {
        _annotations = nextAnnotations;
        _selection = null;
        _interaction.setSelected(null);
        _clearInlineTextEditing();
        _canvasStatus = 'Empty note discarded';
      });
      return;
    }

    if (text.isNotEmpty && text != previous.label) {
      nextAnnotations[index] = previous.copyWith(
        label: text,
        note: previous.markerType == GraphMarkerType.treatmentNote
            ? text
            : previous.note,
      );
      setState(() {
        _annotations = nextAnnotations;
        _undoStack.add(
          isNew
              ? const _UndoEntry(_UndoKind.annotation)
              : _UndoEntry(
                  _UndoKind.textEdit,
                  annotationIndex: index,
                  previousAnnotation: previous,
                ),
        );
        _clearInlineTextEditing();
        _canvasStatus = isNew ? 'Note placed' : 'Note updated';
      });
      return;
    }

    setState(_clearInlineTextEditing);
  }

  void _clearInlineTextEditing() {
    _inlineTextAnnotationIndex = null;
    _inlineTextPreviousAnnotation = null;
    _inlineTextIsNew = false;
    _interaction.setTextEditing(false);
  }

  Future<void> _editShapeText(int index) async {
    if (index < 0 || index >= _shapes.length || _shapes[index].isStructure) {
      return;
    }
    if (_isLayerLocked(_GraphLayer.shapes)) {
      _showCanvasMessage('Shapes layer is locked');
      return;
    }

    final before = _EditorSnapshot.capture(this);
    final shape = _shapes[index];
    _interaction.setTextEditing(true);
    final text = await _showTextLabelDialog(
      title: 'Edit shape text',
      initialText: shape.text.isEmpty ? shape.name : shape.text,
    );
    _interaction.setTextEditing(false);
    if (!mounted || text == null || text == shape.text) {
      return;
    }

    final nextShapes = <GraphShape>[..._shapes];
    nextShapes[index] = shape.copyWith(text: text);
    setState(() {
      _shapes = nextShapes;
      _undoStack.add(
        _UndoEntry(_UndoKind.snapshot, previousSnapshot: before),
      );
      _canvasStatus = 'Shape text updated';
    });
  }

  Future<String?> _showTextLabelDialog({
    required String title,
    required String initialText,
  }) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _TextLabelDialog(
        title: title,
        initialText: initialText,
      ),
    );

    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }

  int? _findTextAnnotationIndex(Offset canvasOffset) {
    for (var i = _annotations.length - 1; i >= 0; i -= 1) {
      final annotation = _annotations[i];

      if (annotation.kind != GraphAnnotationKind.text) {
        continue;
      }

      if (!_isAnnotationVisible(annotation)) {
        continue;
      }

      final halfWidth =
          ((annotation.label.length * 8) + 24).clamp(56, 170).toDouble() / 2;
      const halfHeight = 24.0;
      final dx = (canvasOffset.dx - annotation.point.x).abs();
      final dy = (canvasOffset.dy - annotation.point.y).abs();

      if (dx <= halfWidth && dy <= halfHeight) {
        return i;
      }
    }

    return null;
  }

  GraphAnnotation _buildAnnotationForSelectedTool(GraphPoint point) {
    switch (_selectedTool) {
      case CanvasTool.select:
      case CanvasTool.pan:
      case CanvasTool.structure:
      case CanvasTool.rectangle:
      case CanvasTool.square:
      case CanvasTool.circle:
      case CanvasTool.ellipse:
      case CanvasTool.triangle:
      case CanvasTool.curve:
      case CanvasTool.wall:
      case CanvasTool.arrow:
      case CanvasTool.freehand:
      case CanvasTool.callout:
        throw StateError('Drawing tools are not annotations.');
      case CanvasTool.marker:
        return GraphAnnotation(
          kind: GraphAnnotationKind.marker,
          point: point,
          label: _selectedMarkerType.shortLabel,
          markerType: _selectedMarkerType,
          color: _selectedMarkerColor,
          size: _selectedMarkerSize,
        );
      case CanvasTool.photo:
        return GraphAnnotation(
          kind: GraphAnnotationKind.photo,
          point: point,
          label: 'Photo ${_photoCount + 1}',
          markerType: GraphMarkerType.camera,
          color: GraphMarkerType.camera.defaultColor,
        );
      case CanvasTool.text:
        throw StateError(
            'Text annotations are created through the text dialog.');
    }
  }

  int get _photoCount {
    return _annotations
        .where((annotation) => annotation.kind == GraphAnnotationKind.photo)
        .length;
  }

  void _finishWallPath({
    bool closeShapeDefault = false,
    bool autoFinish = false,
  }) {
    if (_selectedTool == CanvasTool.structure) {
      _finishStructurePath();
      return;
    }
    _finishWallPathAsync(
      closeShapeDefault: closeShapeDefault,
      autoFinish: autoFinish,
    );
  }

  Future<void> _finishWallPathAsync({
    bool closeShapeDefault = false,
    bool autoFinish = false,
  }) async {
    if (_activeWallStart == null) {
      _showCanvasMessage('No active wall shape to finish');
      return;
    }

    if (_isLayerLocked(_GraphLayer.shapes)) {
      _showCanvasMessage('Shapes layer is locked');
      return;
    }

    final startSegmentIndex =
        _activePathStartSegmentIndex ?? _wallSegments.length;
    final pathSegmentCount = _wallSegments.length - startSegmentIndex;

    if (pathSegmentCount <= 0) {
      setState(() {
        _activeWallStart = null;
        _activePathStartPoint = null;
        _pendingCurveControlPoint = null;
        _previewSegment = null;
        _activePathStartSegmentIndex = null;
        if (_undoStack.isNotEmpty &&
            _undoStack.last.kind == _UndoKind.wallStart) {
          _undoStack.removeLast();
        }
        _canvasStatus = 'Start point cleared';
      });
      return;
    }

    final pathStartPoint = _activePathStartPoint;
    final activeWallStart = _activeWallStart;
    final pathReturnsToStart = pathStartPoint != null &&
        activeWallStart != null &&
        pathSegmentCount >= 2 &&
        activeWallStart.distanceTo(pathStartPoint) <= _minimumWallLength;
    final canAddClosingSegment = pathStartPoint != null &&
        activeWallStart != null &&
        pathSegmentCount >= 2 &&
        activeWallStart.distanceTo(pathStartPoint) > _minimumWallLength;
    final canCloseShape = pathReturnsToStart || canAddClosingSegment;
    final defaultName = _selectedDrawingPreset?.label ??
        '${_selectedTool == CanvasTool.wall ? 'Line' : 'Shape'} ${_shapes.length + 1}';
    final result = autoFinish
        ? _FinishShapeResult(
            name: defaultName,
            closeShape: canCloseShape,
            fillColor: _currentShapeFillColor,
            fillOpacity: _currentShapeFillOpacity,
            borderColor: _currentShapeBorderColor,
            borderWidth: _currentShapeBorderWidth,
            pattern: _currentShapePattern,
          )
        : await _showFinishShapeDialog(
            canCloseShape: canCloseShape,
            closeShapeDefault:
                (closeShapeDefault || pathReturnsToStart) && canCloseShape,
            defaultName: defaultName,
          );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      final previousActiveWallStart = _activeWallStart;
      final previousActivePathStartPoint = _activePathStartPoint;
      final previousActivePathStartSegmentIndex = _activePathStartSegmentIndex;
      var addedSegmentCount = 0;
      final shapeSegmentIndexes = <int>[
        for (var i = startSegmentIndex; i < _wallSegments.length; i += 1) i,
      ];

      if (result.closeShape && canAddClosingSegment) {
        final closingSegment = WallSegment(
          start: _activeWallStart!,
          end: _activePathStartPoint!,
          color: _currentLineColor,
          strokeWidth: _currentLineWidth,
          pattern: _currentLinePattern,
        );
        shapeSegmentIndexes.add(_wallSegments.length);
        _wallSegments = <WallSegment>[..._wallSegments, closingSegment];
        addedSegmentCount = 1;
      }

      final shape = GraphShape(
        name: result.name,
        segmentIndexes: shapeSegmentIndexes,
        fillColor: result.fillColor,
        fillOpacity: result.fillOpacity,
        borderColor: result.borderColor,
        borderWidth: result.borderWidth,
        pattern: result.pattern,
        closed: result.closeShape && canCloseShape,
        rotationDegrees: 0,
        preset: _selectedDrawingPreset,
        extraProperties: {
          'sourceTool': _selectedTool.name,
        },
      );

      _shapes = <GraphShape>[..._shapes, shape];
      _selection = _Selection.shape(_shapes.length - 1);
      _interaction.setSelected(_interactionReference(_selection!));
      _activeWallStart = null;
      _activePathStartPoint = null;
      _pendingCurveControlPoint = null;
      _previewSegment = null;
      _activePathStartSegmentIndex = null;
      _undoStack.add(
        _UndoEntry(
          _UndoKind.shapeFinish,
          shapeIndex: _shapes.length - 1,
          addedSegmentCount: addedSegmentCount,
          previousActiveWallStart: previousActiveWallStart,
          previousActivePathStartPoint: previousActivePathStartPoint,
          previousActivePathStartSegmentIndex:
              previousActivePathStartSegmentIndex,
        ),
      );
      _canvasStatus = 'Shape finished: ${shape.name}';
    });
  }

  Future<_FinishShapeResult?> _showFinishShapeDialog({
    required bool canCloseShape,
    required bool closeShapeDefault,
    required String defaultName,
  }) async {
    final nameController = TextEditingController(text: defaultName);
    var closeShape = closeShapeDefault || canCloseShape;
    var fillChoice = _shapeFillChoiceForColor(_currentShapeFillColor);
    var borderChoice = _shapeBorderChoiceForColor(_currentShapeBorderColor);
    var borderWidth = _currentShapeBorderWidth;
    var pattern = _currentShapePattern;

    final result = await showDialog<_FinishShapeResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Close shape?'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Shape name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: closeShape,
                      enabled: canCloseShape,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Close shape'),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          closeShape = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<_ShapeFillChoice>(
                      initialValue: fillChoice,
                      decoration: const InputDecoration(
                        labelText: 'Transparent fill',
                        border: OutlineInputBorder(),
                      ),
                      items: _ShapeFillChoice.values
                          .map(
                            (choice) => DropdownMenuItem(
                              value: choice,
                              child: _ColorChoiceLabel(
                                label: choice.label,
                                color: choice.color,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          fillChoice = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_ShapeBorderChoice>(
                      initialValue: borderChoice,
                      decoration: const InputDecoration(
                        labelText: 'Border color',
                        border: OutlineInputBorder(),
                      ),
                      items: _ShapeBorderChoice.values
                          .map(
                            (choice) => DropdownMenuItem(
                              value: choice,
                              child: _ColorChoiceLabel(
                                label: choice.label,
                                color: choice.color,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          borderChoice = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<double>(
                      initialValue: borderWidth,
                      decoration: const InputDecoration(
                        labelText: 'Border width',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 2.0, child: Text('Thin')),
                        DropdownMenuItem(value: 3.0, child: Text('Medium')),
                        DropdownMenuItem(value: 5.0, child: Text('Heavy')),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          borderWidth = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<GraphShapePattern>(
                      initialValue: pattern,
                      decoration: const InputDecoration(
                        labelText: 'Pattern',
                        border: OutlineInputBorder(),
                      ),
                      items: GraphShapePattern.values
                          .map(
                            (pattern) => DropdownMenuItem(
                              value: pattern,
                              child: Text(_patternLabel(pattern)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          pattern = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim().isEmpty
                        ? defaultName
                        : nameController.text.trim();
                    Navigator.of(context).pop(
                      _FinishShapeResult(
                        name: name,
                        closeShape: closeShape,
                        fillColor: fillChoice.color,
                        fillOpacity: fillChoice.opacity,
                        borderColor: borderChoice.color,
                        borderWidth: borderWidth,
                        pattern: pattern,
                      ),
                    );
                  },
                  child: const Text('Close Shape'),
                ),
              ],
            );
          },
        );
      },
    );

    // The route is popped before its reverse animation releases the text
    // field. Disposing immediately can leave that field listening to a dead
    // controller for one frame.
    await Future<void>.delayed(kThemeAnimationDuration);
    nameController.dispose();

    return result;
  }

  void _undoLastAction() {
    if (_removeLatestDraftPoint()) {
      return;
    }

    if (_undoStack.isEmpty) {
      _showCanvasMessage('Nothing to undo');
      return;
    }

    final undoEntry = _undoStack.removeLast();
    final redoEntry = _RedoEntry(
      snapshot: _EditorSnapshot.capture(this),
      undoEntry: undoEntry,
    );

    _applyingHistory = true;
    setState(() {
      switch (undoEntry.kind) {
        case _UndoKind.snapshot:
          undoEntry.previousSnapshot?.restore(this);
          _selection = null;
          _interaction.setSelected(null);
          _canvasStatus = 'Action undone';
          break;
        case _UndoKind.wallStart:
          _activeWallStart = null;
          _activePathStartPoint = null;
          _pendingCurveControlPoint = null;
          _previewSegment = null;
          _activePathStartSegmentIndex = null;
          _canvasStatus = 'Wall start removed';
          break;
        case _UndoKind.wallSegment:
          _undoWallSegment();
          break;
        case _UndoKind.annotation:
          _undoAnnotation();
          break;
        case _UndoKind.freehand:
          _undoFreehand();
          break;
        case _UndoKind.textEdit:
          _undoTextEdit(undoEntry);
          break;
        case _UndoKind.move:
          _undoMove(undoEntry);
          break;
        case _UndoKind.shapeFinish:
          _undoShapeFinish(undoEntry);
          break;
      }
    });
    _applyingHistory = false;
    _redoStack.add(redoEntry);
  }

  void _redoLastAction() {
    if (_redoStack.isEmpty) {
      _showCanvasMessage('Nothing to redo');
      return;
    }

    final redoEntry = _redoStack.removeLast();
    _applyingHistory = true;
    setState(() {
      redoEntry.snapshot.restore(this);
      _undoStack.add(redoEntry.undoEntry);
      _canvasStatus = 'Action restored';
    });
    _applyingHistory = false;
  }

  void _undoWallSegment() {
    if (_wallSegments.isEmpty) {
      _canvasStatus = 'No wall segment to undo';
      return;
    }

    final removedSegment = _wallSegments.last;

    _wallSegments = _wallSegments.sublist(0, _wallSegments.length - 1);
    _activeWallStart = removedSegment.start;
    _pendingCurveControlPoint = null;
    _previewSegment = null;
    if (_activePathStartSegmentIndex != null &&
        _wallSegments.length <= _activePathStartSegmentIndex!) {
      _activePathStartPoint = removedSegment.start;
    }
    _canvasStatus = 'Last wall removed';
  }

  void _undoAnnotation() {
    if (_annotations.isEmpty) {
      _canvasStatus = 'No item to undo';
      return;
    }

    _annotations = _annotations.sublist(0, _annotations.length - 1);
    _canvasStatus = 'Last item removed';
  }

  void _undoFreehand() {
    if (_freehandStrokes.isEmpty) {
      _canvasStatus = 'No freehand stroke to undo';
      return;
    }

    _freehandStrokes = _freehandStrokes.sublist(0, _freehandStrokes.length - 1);
    _canvasStatus = 'Last freehand stroke removed';
  }

  void _undoTextEdit(_UndoEntry undoEntry) {
    final index = undoEntry.annotationIndex;
    final previousAnnotation = undoEntry.previousAnnotation;

    if (index == null ||
        previousAnnotation == null ||
        index < 0 ||
        index >= _annotations.length) {
      _canvasStatus = 'Text edit could not be undone';
      return;
    }

    final nextAnnotations = <GraphAnnotation>[..._annotations];
    nextAnnotations[index] = previousAnnotation;
    _annotations = nextAnnotations;
    _canvasStatus = 'Text edit undone';
  }

  void _undoMove(_UndoEntry undoEntry) {
    final previousWallSegments = undoEntry.previousWallSegments;
    final previousAnnotations = undoEntry.previousAnnotations;
    final previousShapes = undoEntry.previousShapes;
    final previousFreehandStrokes = undoEntry.previousFreehandStrokes;
    final previousTraces = undoEntry.previousTraces;

    if (previousWallSegments == null ||
        previousAnnotations == null ||
        previousShapes == null ||
        previousFreehandStrokes == null ||
        previousTraces == null) {
      _canvasStatus = 'Move could not be undone';
      return;
    }

    _wallSegments = previousWallSegments;
    _annotations = previousAnnotations;
    _shapes = previousShapes;
    _freehandStrokes = previousFreehandStrokes;
    _document.replaceTraces(previousTraces);
    _activeWallStart = undoEntry.previousActiveWallStart;
    _activePathStartPoint = undoEntry.previousActivePathStartPoint;
    _pendingCurveControlPoint = null;
    _previewSegment = null;
    _activePathStartSegmentIndex =
        undoEntry.previousActivePathStartSegmentIndex;
    _canvasStatus = 'Move undone';
  }

  void _undoShapeFinish(_UndoEntry undoEntry) {
    final shapeIndex = undoEntry.shapeIndex;

    if (shapeIndex != null && shapeIndex >= 0 && shapeIndex < _shapes.length) {
      final nextShapes = <GraphShape>[..._shapes]..removeAt(shapeIndex);
      _shapes = nextShapes;
    } else if (_shapes.isNotEmpty) {
      _shapes = _shapes.sublist(0, _shapes.length - 1);
    }

    if (undoEntry.addedSegmentCount > 0 &&
        undoEntry.addedSegmentCount <= _wallSegments.length) {
      _wallSegments = _wallSegments.sublist(
        0,
        _wallSegments.length - undoEntry.addedSegmentCount,
      );
    }

    _activeWallStart = undoEntry.previousActiveWallStart;
    _activePathStartPoint = undoEntry.previousActivePathStartPoint;
    _pendingCurveControlPoint = null;
    _previewSegment = null;
    _activePathStartSegmentIndex =
        undoEntry.previousActivePathStartSegmentIndex;
    _canvasStatus = 'Shape finish undone';
  }

  void _deleteSelection() {
    final currentSelection = _selection;

    if (currentSelection == null) {
      _showCanvasMessage('Nothing selected');
      return;
    }

    if (!_isSelectionEditable(currentSelection)) {
      _showCanvasMessage('Selected layer is locked');
      return;
    }

    _recordSnapshotUndo();
    setState(() {
      switch (currentSelection.kind) {
        case _SelectionKind.annotation:
          final index = currentSelection.index;
          if (index >= 0 && index < _annotations.length) {
            _annotations = <GraphAnnotation>[..._annotations]..removeAt(index);
            _canvasStatus = 'Item deleted';
          }
          break;
        case _SelectionKind.segment:
          final index = currentSelection.index;
          if (index >= 0 && index < _wallSegments.length) {
            _removeSegmentAt(index);
            _canvasStatus = 'Line deleted';
          }
          break;
        case _SelectionKind.shape:
          final index = currentSelection.index;
          if (index >= 0 && index < _shapes.length) {
            _removeShapeAt(index);
            _canvasStatus = 'Shape deleted';
          }
          break;
        case _SelectionKind.freehand:
          final index = currentSelection.index;
          if (index >= 0 && index < _freehandStrokes.length) {
            _freehandStrokes = <FreehandStroke>[..._freehandStrokes]
              ..removeAt(index);
            _canvasStatus = 'Freehand stroke deleted';
          }
          break;
        case _SelectionKind.trace:
          final index = currentSelection.index;
          if (index >= 0 && index < _traces.length) {
            final nextTraces = <TraceGeometry>[..._traces]..removeAt(index);
            _document.replaceTraces(nextTraces);
            _canvasStatus = 'Trace deleted';
          }
          break;
      }

      _selection = null;
      _interaction.setSelected(null);
    });
  }

  void _duplicateSelection() {
    final currentSelection = _selection;

    if (currentSelection == null) {
      _showCanvasMessage('Nothing selected');
      return;
    }

    if (!_isSelectionEditable(currentSelection)) {
      _showCanvasMessage('Selected layer is locked');
      return;
    }

    const duplicateOffset = Offset(36, 36);

    _recordSnapshotUndo();
    setState(() {
      switch (currentSelection.kind) {
        case _SelectionKind.annotation:
          final index = currentSelection.index;
          if (index >= 0 && index < _annotations.length) {
            final annotation = _annotations[index];
            final duplicated = annotation.copyWith(
              point: GraphPoint.fromOffset(
                  annotation.point.offset + duplicateOffset),
              label: '${annotation.label} Copy',
            );
            _annotations = <GraphAnnotation>[..._annotations, duplicated];
            _selection = _Selection.annotation(_annotations.length - 1);
            _canvasStatus = 'Item duplicated';
          }
          break;
        case _SelectionKind.segment:
          final index = currentSelection.index;
          if (index >= 0 && index < _wallSegments.length) {
            final segment = _wallSegments[index];
            final duplicated = segment.copyWith(
              start:
                  GraphPoint.fromOffset(segment.start.offset + duplicateOffset),
              end: GraphPoint.fromOffset(segment.end.offset + duplicateOffset),
              controlPoint: segment.controlPoint == null
                  ? null
                  : GraphPoint.fromOffset(
                      segment.controlPoint!.offset + duplicateOffset,
                    ),
            );
            _wallSegments = <WallSegment>[..._wallSegments, duplicated];
            _selection = _Selection.segment(_wallSegments.length - 1);
            _canvasStatus = 'Line duplicated';
          }
          break;
        case _SelectionKind.shape:
          final index = currentSelection.index;
          if (index >= 0 && index < _shapes.length) {
            _duplicateShape(index, duplicateOffset);
          }
          break;
        case _SelectionKind.freehand:
          final index = currentSelection.index;
          if (index >= 0 && index < _freehandStrokes.length) {
            final stroke = _freehandStrokes[index];
            final duplicated = stroke.copyWith(
              points: [
                for (final point in stroke.points)
                  GraphPoint.fromOffset(point.offset + duplicateOffset),
              ],
            );
            _freehandStrokes = <FreehandStroke>[
              ..._freehandStrokes,
              duplicated,
            ];
            _selection = _Selection.freehand(_freehandStrokes.length - 1);
            _canvasStatus = 'Freehand stroke duplicated';
          }
          break;
        case _SelectionKind.trace:
          _canvasStatus = 'Trace duplication is not available';
          break;
      }
    });
  }

  void _copySelection() {
    final currentSelection = _selection;
    if (currentSelection == null) {
      _showCanvasMessage('Nothing selected');
      return;
    }

    setState(() {
      _clipboardItem = _ClipboardItem(currentSelection);
      _canvasStatus = 'Copied';
    });
  }

  void _pasteClipboard() {
    final clipboardItem = _clipboardItem;
    if (clipboardItem == null) {
      _showCanvasMessage('Clipboard is empty');
      return;
    }

    _selection = clipboardItem.selection;
    _duplicateSelection();
  }

  void _reorderSelection(_ReorderDirection direction) {
    final currentSelection = _selection;
    if (currentSelection == null) {
      _showCanvasMessage('Nothing selected');
      return;
    }

    _recordSnapshotUndo();
    setState(() {
      switch (currentSelection.kind) {
        case _SelectionKind.annotation:
          _annotations = _reorderedList(
            _annotations,
            currentSelection.index,
            direction,
          );
          _selection = _Selection.annotation(
            _nextReorderIndex(
                _annotations.length, currentSelection.index, direction),
          );
          break;
        case _SelectionKind.shape:
          _shapes = _reorderedList(_shapes, currentSelection.index, direction);
          _selection = _Selection.shape(
            _nextReorderIndex(
                _shapes.length, currentSelection.index, direction),
          );
          break;
        case _SelectionKind.segment:
        case _SelectionKind.freehand:
        case _SelectionKind.trace:
          _canvasStatus = 'Layer order applies to markers and shapes';
          return;
      }
      _canvasStatus = 'Layer order updated';
    });
  }

  List<T> _reorderedList<T>(
    List<T> items,
    int index,
    _ReorderDirection direction,
  ) {
    if (index < 0 || index >= items.length || items.length < 2) {
      return items;
    }

    final nextItems = <T>[...items];
    final item = nextItems.removeAt(index);
    final nextIndex = _nextReorderIndex(items.length, index, direction);
    nextItems.insert(nextIndex, item);
    return nextItems;
  }

  int _nextReorderIndex(
    int length,
    int index,
    _ReorderDirection direction,
  ) {
    return switch (direction) {
      _ReorderDirection.forward => math.min(index + 1, length - 1),
      _ReorderDirection.backward => math.max(index - 1, 0),
      _ReorderDirection.front => length - 1,
      _ReorderDirection.back => 0,
    };
  }

  void _setSelectedLayerLocked(bool locked) {
    final currentSelection = _selection;
    if (currentSelection == null) {
      _showCanvasMessage('Nothing selected');
      return;
    }

    final layer = _layerForSelection(currentSelection);
    setState(() {
      final current = _layerSettings[layer] ?? const _LayerSettings();
      _setLayerSettings(layer, current.copyWith(locked: locked));
      _canvasStatus =
          '${_layerLabel(layer)} layer ${locked ? 'locked' : 'unlocked'}';
    });
  }

  void _removeSegmentAt(int removedIndex) {
    _wallSegments = <WallSegment>[..._wallSegments]..removeAt(removedIndex);
    final nextShapes = <GraphShape>[];

    for (final shape in _shapes) {
      final nextIndexes = <int>[];

      for (final segmentIndex in shape.segmentIndexes) {
        if (segmentIndex == removedIndex) {
          continue;
        }

        nextIndexes.add(
          segmentIndex > removedIndex ? segmentIndex - 1 : segmentIndex,
        );
      }

      if (nextIndexes.isNotEmpty) {
        nextShapes.add(shape.copyWith(segmentIndexes: nextIndexes));
      }
    }

    _shapes = nextShapes;
  }

  void _removeShapeAt(int removedShapeIndex) {
    if (removedShapeIndex < 0 || removedShapeIndex >= _shapes.length) {
      return;
    }

    final removedIndexes = _shapes[removedShapeIndex]
        .segmentIndexes
        .where((index) => index >= 0 && index < _wallSegments.length)
        .toSet();
    final oldToNewIndexes = <int, int>{};
    final nextWallSegments = <WallSegment>[];

    for (var oldIndex = 0; oldIndex < _wallSegments.length; oldIndex += 1) {
      if (removedIndexes.contains(oldIndex)) {
        continue;
      }
      oldToNewIndexes[oldIndex] = nextWallSegments.length;
      nextWallSegments.add(_wallSegments[oldIndex]);
    }

    final nextShapes = <GraphShape>[];
    for (var shapeIndex = 0; shapeIndex < _shapes.length; shapeIndex += 1) {
      if (shapeIndex == removedShapeIndex) {
        continue;
      }
      final nextIndexes = _shapes[shapeIndex]
          .segmentIndexes
          .map((index) => oldToNewIndexes[index])
          .whereType<int>()
          .toList(growable: false);
      if (nextIndexes.isNotEmpty) {
        nextShapes.add(
          _shapes[shapeIndex].copyWith(segmentIndexes: nextIndexes),
        );
      }
    }

    _wallSegments = nextWallSegments;
    _shapes = nextShapes;
  }

  void _duplicateShape(int shapeIndex, Offset duplicateOffset) {
    final shape = _shapes[shapeIndex];
    final newSegmentIndexes = <int>[];
    var nextWallSegments = <WallSegment>[..._wallSegments];

    for (final segmentIndex in shape.segmentIndexes) {
      if (segmentIndex < 0 || segmentIndex >= _wallSegments.length) {
        continue;
      }

      final segment = _wallSegments[segmentIndex];
      final duplicated = segment.copyWith(
        start: GraphPoint.fromOffset(segment.start.offset + duplicateOffset),
        end: GraphPoint.fromOffset(segment.end.offset + duplicateOffset),
        controlPoint: segment.controlPoint == null
            ? null
            : GraphPoint.fromOffset(
                segment.controlPoint!.offset + duplicateOffset),
      );

      newSegmentIndexes.add(nextWallSegments.length);
      nextWallSegments = <WallSegment>[...nextWallSegments, duplicated];
    }

    if (newSegmentIndexes.isEmpty) {
      return;
    }

    _wallSegments = nextWallSegments;
    _shapes = <GraphShape>[
      ..._shapes,
      shape.copyWith(
        name: '${shape.name} Copy',
        segmentIndexes: newSegmentIndexes,
      ),
    ];
    _selection = _Selection.shape(_shapes.length - 1);
    _canvasStatus = 'Shape duplicated';
  }

  Future<void> _confirmClearGraph() async {
    if (_wallSegments.isEmpty &&
        _annotations.isEmpty &&
        _shapes.isEmpty &&
        _freehandStrokes.isEmpty &&
        _activeWallStart == null) {
      _showCanvasMessage('Graph is already clear');
      return;
    }

    if (_hasLockedContent()) {
      _showCanvasMessage('Unlock layers before clearing graph');
      return;
    }

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear graph?'),
          content: const Text('This removes all wall segments and items.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear Graph'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldClear != true) {
      return;
    }

    setState(() {
      _wallSegments = <WallSegment>[];
      _annotations = <GraphAnnotation>[];
      _shapes = <GraphShape>[];
      _freehandStrokes = <FreehandStroke>[];
      _undoStack.clear();
      _activeWallStart = null;
      _activePathStartPoint = null;
      _pendingCurveControlPoint = null;
      _previewSegment = null;
      _activePathStartSegmentIndex = null;
      _selection = null;
      _canvasStatus = 'Graph cleared';
    });
  }

  bool _hasLockedContent() {
    final structureLocked = _isLayerLocked(_GraphLayer.structure) &&
        (_wallSegments.isNotEmpty || _freehandStrokes.isNotEmpty);
    final shapesLocked = _isLayerLocked(_GraphLayer.shapes) &&
        _shapes.any((shape) => !_isTreatmentShape(shape));
    final inspectionsLocked = _isLayerLocked(_GraphLayer.inspections) &&
        _annotations.any(
          (annotation) =>
              _layerForAnnotation(annotation) == _GraphLayer.inspections,
        );
    final treatmentLocked = _isLayerLocked(_GraphLayer.treatment) &&
        (_annotations.any(
              (annotation) =>
                  _layerForAnnotation(annotation) == _GraphLayer.treatment,
            ) ||
            _shapes.any(_isTreatmentShape));
    final photosLocked = _isLayerLocked(_GraphLayer.photos) &&
        _annotations.any(
          (annotation) => annotation.kind == GraphAnnotationKind.photo,
        );

    return structureLocked ||
        shapesLocked ||
        inspectionsLocked ||
        treatmentLocked ||
        photosLocked;
  }

  // Notification durations (item 12 of the production pass): short
  // transient hints (locked layers, nothing selected, etc.) are
  // informational; explicit success/warning/error messages get their own
  // longer, more deliberate durations so a technician has time to actually
  // read them, and warning/error toasts stay on screen long enough (and
  // offer a manual close) that a real failure never flashes by unnoticed.
  static const Duration _infoMessageDuration = Duration(seconds: 5);
  static const Duration _successMessageDuration = Duration(seconds: 4);
  static const Duration _warningMessageDuration = Duration(seconds: 7);
  static const Duration _errorMessageDuration = Duration(seconds: 8);

  void _showCanvasMessage(
    String message, {
    Duration? duration,
    _CanvasMessageSeverity severity = _CanvasMessageSeverity.info,
  }) {
    setState(() {
      _canvasStatus = message;
    });

    final resolvedDuration = duration ??
        switch (severity) {
          _CanvasMessageSeverity.info => _infoMessageDuration,
          _CanvasMessageSeverity.success => _successMessageDuration,
          _CanvasMessageSeverity.warning => _warningMessageDuration,
          _CanvasMessageSeverity.error => _errorMessageDuration,
        };
    final dismissible = severity == _CanvasMessageSeverity.warning ||
        severity == _CanvasMessageSeverity.error;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: resolvedDuration,
          showCloseIcon: dismissible,
        ),
      );
  }

  void _toggleTraceLayer() {
    setState(() {
      final traceSettings =
          _layerSettings[_GraphLayer.trace] ?? const _LayerSettings();
      final nextVisible = !traceSettings.visible;
      _setLayerSettings(
        _GraphLayer.trace,
        traceSettings.copyWith(visible: nextVisible),
      );
      _canvasStatus = nextVisible ? 'Trace layer on' : 'Trace layer off';
    });
  }

  Future<void> _openTraceWorkspace({int? editIndex}) async {
    if (_isLayerLocked(_GraphLayer.trace)) {
      _showCanvasMessage('Trace layer is locked');
      return;
    }
    if (editIndex == null && _traces.isNotEmpty) {
      editIndex = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          final jobAddress =
              traceWorkspaceAddress(_traces, _document.customer.serviceAddress);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.satellite_alt_outlined),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Satellite traces',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Start another structure or refine a saved outline.',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        key: const ValueKey('new-trace-button'),
                        icon: const Icon(Icons.add),
                        label: const Text('New Trace'),
                        onPressed: () => Navigator.pop(context, -1),
                      ),
                      if (jobAddress.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Text(
                            'Opens at $jobAddress',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const Divider(height: 28),
                      for (var index = 0; index < _traces.length; index += 1)
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            leading:
                                const Icon(Icons.edit_location_alt_outlined),
                            title: Text(_traces[index].label),
                            subtitle: Text(
                              jobAddress.isEmpty
                                  ? 'Edit saved corner points'
                                  : 'Open at the job address and edit corner points',
                            ),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () => Navigator.pop(context, index),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
      if (!mounted || editIndex == null) return;
      if (editIndex == -1) editIndex = null;
    }
    final initialTrace = editIndex == null ? null : _traces[editIndex];
    final trace = await Navigator.push<TraceGeometry>(
      context,
      MaterialPageRoute(
        builder: (context) => TraceWorkspaceScreen(
          address: traceWorkspaceAddress(
              _traces, _document.customer.serviceAddress,
              editingTrace: initialTrace),
          canvasSize: _canvasSize,
          traceLabel:
              initialTrace?.label ?? 'Property Trace ${_traces.length + 1}',
          initialTrace: initialTrace,
        ),
      ),
    );
    if (!mounted || trace == null) return;
    _recordSnapshotUndo();
    setState(() {
      final nextTraces = <TraceGeometry>[..._traces];
      if (editIndex == null) {
        nextTraces.add(trace);
      } else {
        nextTraces[editIndex] = trace;
      }
      _document.replaceTraces(nextTraces);
      _setLayerSettings(
        _GraphLayer.trace,
        const _LayerSettings(visible: true),
      );
      _document.setMeasurementCalibration(
        MeasurementCalibration(
          source: MeasurementSource.mapGeodesic,
          status: MeasurementAccuracyStatus.estimated,
          metersPerCanvasUnit: trace.metersPerCanvasUnit,
          note: 'Measurements derived from geographic trace points',
        ),
      );
      final traceIndex = editIndex ?? nextTraces.length - 1;
      _selection = _Selection.trace(traceIndex);
      _interaction.setSelected(_interactionReference(_selection!));
      _interaction.selectTool(CanvasTool.select);
      _sidePanelMode = _SidePanelMode.properties;
      _canvasStatus = 'Satellite trace added at real-world scale';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitTraceInViewport(trace);
    });
  }

  void _fitTraceInViewport(
    TraceGeometry trace, {
    Size? viewportSize,
  }) {
    if (trace.canvasPoints.isEmpty) return;
    final viewportBox =
        _canvasViewportKey.currentContext?.findRenderObject() as RenderBox?;
    final size = viewportSize ?? viewportBox?.size;
    if (size == null || size.isEmpty) return;
    final left = trace.canvasPoints.map((point) => point.x).reduce(math.min);
    final right = trace.canvasPoints.map((point) => point.x).reduce(math.max);
    final top = trace.canvasPoints.map((point) => point.y).reduce(math.min);
    final bottom = trace.canvasPoints.map((point) => point.y).reduce(math.max);
    // Keep the edge footage labels and selected trace rotation handle inside
    // the viewport when a new or existing trace is fitted to the canvas.
    final bounds = Rect.fromLTRB(left, top, right, bottom).inflate(64);
    const padding = 96.0;
    final scale = math
        .min(
          (size.width - padding).clamp(1.0, double.infinity) /
              math.max(bounds.width, 1),
          (size.height - padding).clamp(1.0, double.infinity) /
              math.max(bounds.height, 1),
        )
        .clamp(0.25, 4.0);
    final viewportCenter = size.center(Offset.zero);
    final next = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, viewportCenter.dx - (bounds.center.dx * scale))
      ..setEntry(1, 3, viewportCenter.dy - (bounds.center.dy * scale));
    _transformationController.value = next;
  }

  void _toggleLayerVisibility(_GraphLayer layer) {
    if (layer == _GraphLayer.trace) {
      _toggleTraceLayer();
      return;
    }

    setState(() {
      final current = _layerSettings[layer] ?? const _LayerSettings();
      final nextVisible = !current.visible;
      _setLayerSettings(layer, current.copyWith(visible: nextVisible));
      if (layer == _GraphLayer.structure) {
        final shapes =
            _layerSettings[_GraphLayer.shapes] ?? const _LayerSettings();
        _setLayerSettings(
          _GraphLayer.shapes,
          shapes.copyWith(visible: nextVisible),
        );
      }

      final selection = _selection;
      if (!nextVisible &&
          selection != null &&
          _selectionBelongsToLayer(selection, layer)) {
        _selection = null;
      }

      _canvasStatus =
          '${_layerLabel(layer)} layer ${nextVisible ? 'shown' : 'hidden'}';
    });
  }

  void _toggleLayerLock(_GraphLayer layer) {
    setState(() {
      final current = _layerSettings[layer] ?? const _LayerSettings();
      final nextLocked = !current.locked;
      _setLayerSettings(layer, current.copyWith(locked: nextLocked));
      if (layer == _GraphLayer.structure) {
        final shapes =
            _layerSettings[_GraphLayer.shapes] ?? const _LayerSettings();
        _setLayerSettings(
          _GraphLayer.shapes,
          shapes.copyWith(locked: nextLocked),
        );
      }
      _canvasStatus =
          '${_layerLabel(layer)} layer ${nextLocked ? 'locked' : 'unlocked'}';
    });
  }

  void _setLayerSettings(_GraphLayer layer, _LayerSettings settings) {
    _document.setLayer(
      layer.name,
      GraphLayerState(visible: settings.visible, locked: settings.locked),
    );
  }

  // Item 10 of the production pass: when a graph has already been saved
  // to Holloman Ops Brain, a subsequent Save must ask whether to
  // overwrite that existing file or save the changes as a new file,
  // rather than silently overwriting.
  Future<void> _handleGraphFileSaveTapped() async {
    if (!_document.isDirty) {
      _showCanvasMessage(
        'No changes to save',
        severity: _CanvasMessageSeverity.info,
      );
      return;
    }
    if (_portalKey != null) {
      final choice = await _confirmOverwriteOrSaveAsNew();
      if (choice == null || choice == _SaveConflictChoice.cancel) return;
      if (choice == _SaveConflictChoice.saveAsNew) {
        _replaceDocumentWithNewIdentity();
      }
    }
    await _saveDocument();
  }

  Future<_SaveConflictChoice?> _confirmOverwriteOrSaveAsNew() {
    return showDialog<_SaveConflictChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save changes'),
        content: const Text(
          'This graph was already saved to Holloman Ops Brain. Overwrite '
          'the existing file with your changes, or save these changes as '
          'a brand new file instead?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_SaveConflictChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_SaveConflictChoice.saveAsNew),
            child: const Text('Save As New'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_SaveConflictChoice.overwrite),
            child: const Text('Overwrite Existing'),
          ),
        ],
      ),
    );
  }

  // "Save As New" recovery (items 10/11 of the production pass): swaps in
  // a fresh GraphDocument.withNewIdentity() copy -- new id, new
  // created/updated timestamps -- and clears _portalKey so the next save
  // creates a brand new Ops Brain file instead of overwriting whatever is
  // (or isn't, in the renamed/missing-key recovery case) sitting at the
  // old key. The old document/listener are torn down cleanly.
  void _replaceDocumentWithNewIdentity() {
    final old = _document;
    old.removeListener(_handleDocumentChanged);
    _document = GraphDocument.withNewIdentity(old);
    _document.addListener(_handleDocumentChanged);
    old.dispose();
    _portalKey = null;
  }

  bool _isGraphNotFoundError(Object error) =>
      error.toString().contains('Saved graph not found.');

  Future<bool> _saveDocument() async {
    var savedOnDevice = false;
    try {
      final referencedAttachmentIds =
          _annotations.expand((annotation) => annotation.attachmentIds).toSet();
      final retainedAttachments = _document.attachments
          .where(
              (attachment) => referencedAttachmentIds.contains(attachment.id))
          .toList();
      for (final attachment in _document.attachments) {
        if (!referencedAttachmentIds.contains(attachment.id)) {
          _pendingPhotoBlobs.remove(attachment.blobKey);
          _pendingPhotoBlobs.remove(attachment.thumbnailKey);
          _deletedPhotoBlobKeys
            ..add(attachment.blobKey)
            ..add(attachment.thumbnailKey);
        }
      }
      if (retainedAttachments.length != _document.attachments.length) {
        _document.replaceAttachments(retainedAttachments);
      }
      final portalBlobs = _portalService.isAvailable
          ? await _collectPortalBlobs()
          : const <String, Uint8List>{};
      await _repository.saveGraph(
        _document,
        blobs: _pendingPhotoBlobs,
        deletedBlobKeys: _deletedPhotoBlobKeys,
      );
      savedOnDevice = true;
      PortalUploadResult? portalResult;
      var recoveredAsNew = false;
      if (_portalService.isAvailable) {
        try {
          portalResult = await _portalService.saveGraph(
            _document,
            portalBlobs,
            existingKey: _portalKey,
          );
        } catch (error) {
          // Item 11: the Ops Brain graph this document was previously
          // saved as may have been renamed or deleted out from under this
          // session. Recover by saving as a brand new file -- never guess
          // a renamed key by filename similarity.
          if (_portalKey != null && _isGraphNotFoundError(error)) {
            _replaceDocumentWithNewIdentity();
            portalResult = await _portalService.saveGraph(
              _document,
              portalBlobs,
              existingKey: null,
            );
            recoveredAsNew = true;
          } else {
            rethrow;
          }
        }
      }
      if (!mounted) return false;
      setState(() {
        if (portalResult != null) _portalKey = portalResult.key;
        _document.markClean();
        _pendingPhotoBlobs.clear();
        _deletedPhotoBlobKeys.clear();
        _canvasStatus = portalResult?.message ?? 'Saved on this device';
      });
      if (portalResult != null) notifySalesBrainGraphSaved(portalResult.key);
      if (recoveredAsNew) {
        _showCanvasMessage(
          'The previously saved file could not be found in Holloman Ops '
          'Brain (it may have been renamed or removed) -- saved your '
          'changes as a new file instead.',
          severity: _CanvasMessageSeverity.warning,
        );
      } else {
        _showCanvasMessage(
          portalResult?.message ?? 'Graph saved on this device',
          severity: _CanvasMessageSeverity.success,
        );
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      if (error is PortalAuthenticationException) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Sign in to save online'),
            content: Text(
              '${savedOnDevice ? 'Your graph is saved on this device. ' : ''}'
              'Sign in to Holloman Ops Brain in a separate tab, then return '
              'to this graph and choose Save again. Keep this graph tab open '
              'to preserve your current drawing and photos.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () {
                  (widget.onPortalSignIn ?? openPortalSignIn)(error.signInUrl);
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Sign in in new tab'),
              ),
            ],
          ),
        );
        return false;
      }
      _showCanvasMessage(
        'Graph could not be saved: $error',
        severity: _CanvasMessageSeverity.error,
      );
      return false;
    }
  }

  // "Save & Open Inspection Workflow" (item 14 of the production pass):
  // saves the current graph to Holloman Ops Brain (reusing the same dirty
  // guard / overwrite-or-save-as-new / 404-recovery logic as a normal
  // Save), then navigates the top-level browser to Sales Brain with the
  // saved graph's billTo/location/key so a human can review and create
  // the report there. Never generates or sends a report on its own.
  Future<void> _saveAndCreateSalesBrainReport() async {
    if (!_portalService.isAvailable) {
      _showCanvasMessage(
        'Opening the inspection workflow is available when BugManGraphs '
        'is opened through Holloman Ops Brain',
        severity: _CanvasMessageSeverity.warning,
      );
      return;
    }
    final customer = _document.customer;
    if (customer.pestPacBillToNumber.trim().isEmpty ||
        customer.pestPacLocationNumber.trim().isEmpty) {
      _showCanvasMessage(
        'This graph needs a customer with a Bill-To and Location before '
        'opening the inspection workflow',
        severity: _CanvasMessageSeverity.warning,
      );
      return;
    }
    if (_portalKey == null) {
      // Never saved to Ops Brain before -- always save regardless of the
      // dirty flag, since "no changes yet" still means "not saved yet".
      if (!await _saveDocument()) return;
    } else if (_document.isDirty) {
      final choice = await _confirmOverwriteOrSaveAsNew();
      if (choice == null || choice == _SaveConflictChoice.cancel) return;
      if (choice == _SaveConflictChoice.saveAsNew) {
        _replaceDocumentWithNewIdentity();
      }
      if (!await _saveDocument()) return;
    }
    final url = _portalService.buildSalesBrainReportUrl(
      billToNumber: customer.pestPacBillToNumber,
      locationNumber: customer.pestPacLocationNumber,
      graphKey: _portalKey!,
    );
    if (url == null) {
      _showCanvasMessage(
        'The inspection workflow is not reachable from this session',
        severity: _CanvasMessageSeverity.error,
      );
      return;
    }
    navigateToSalesBrainReport(url);
  }

  // Each export first saves the editable graph, then saves the rendered PDF
  // or PNG in the same customer BugManGraphs folder. If the graph save
  // fails, stop before creating an export without its matching graph file.
  Future<void> _exportGraphToOpsBrain(GraphFileKind kind) async {
    if (!_portalService.isAvailable) {
      _showCanvasMessage(
        'Exporting PDF/PNG files to Holloman Ops Brain is available when '
        'BugManGraphs is opened through Holloman Ops Brain',
        severity: _CanvasMessageSeverity.warning,
      );
      return;
    }
    if (!await _saveDocument()) return;
    await _saveExportToOpsBrain(kind);
  }

  // The second export step uploads the rendered file after its editable
  // graph has been safely saved by _exportGraphToOpsBrain().
  Future<void> _saveExportToOpsBrain(GraphFileKind kind) async {
    if (!_portalService.isAvailable) {
      _showCanvasMessage(
        'Saving PDF/PNG files to Holloman Ops Brain is available when '
        'BugManGraphs is opened through Holloman Ops Brain',
        severity: _CanvasMessageSeverity.warning,
      );
      return;
    }
    final kindLabel = kind == GraphFileKind.pdfExport ? 'PDF' : 'PNG';
    try {
      final bytes = await _renderExportBytes(kind);
      if (bytes == null || !mounted) return;
      final fileName = buildGraphFileName(
        _document.customer,
        _document.createdAt,
        kind,
      );
      final result = await _portalService.uploadGraphExport(
        customer: _document.customer,
        fileName: fileName,
        bytes: bytes,
        contentType:
            kind == GraphFileKind.pdfExport ? 'application/pdf' : 'image/png',
        graphCreatedAt: _document.createdAt,
      );
      if (!mounted) return;
      setState(() => _canvasStatus = result.message);
      _showCanvasMessage(
        result.message,
        severity: _CanvasMessageSeverity.success,
      );
    } catch (error) {
      if (!mounted) return;
      _showCanvasMessage(
        '$kindLabel file could not be saved to Holloman Ops Brain: $error',
        severity: _CanvasMessageSeverity.error,
      );
    }
  }

  // "Copy Structure to New Graph" (item 7 of the production pass): starts
  // a brand new, separately-saved graph that reuses only this graph's
  // structural wall/shape geometry. Nothing about the currently open
  // document -- in memory or already saved to Ops Brain -- is modified.
  Future<void> _newGraphWithExistingStructure() async {
    if (_wallSegments.isEmpty && _shapes.isEmpty) {
      _showCanvasMessage(
        'Nothing to duplicate yet -- draw some structure first',
        severity: _CanvasMessageSeverity.warning,
      );
      return;
    }

    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start new graph with existing structure?'),
        content: const Text(
          'This opens a brand new graph that reuses the wall segments and '
          'shapes already drawn here. Markers, notes, photos, traces, and '
          'measurement calibration are not carried over, and this graph '
          'itself will not be changed or overwritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start New Graph'),
          ),
        ],
      ),
    );

    if (!mounted || shouldCreate != true) {
      return;
    }

    final newDocument = GraphDocument.duplicateStructureFrom(_document);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GraphCanvasScreen(
          document: newDocument,
          repository: _repository,
          photoPicker: _photoPicker,
          portalService: _portalService,
          markerDefaultsStore: _markerDefaultsStore,
        ),
      ),
    );
  }

  void _completeCallout(
    GraphPoint tip,
    Offset boxCenter,
    _CalloutKind kind,
  ) {
    final layer = kind == _CalloutKind.treatment
        ? _GraphLayer.treatment
        : _GraphLayer.inspections;
    if (_isLayerLocked(layer)) {
      _showCanvasMessage(kind == _CalloutKind.treatment
          ? 'Treatment Markers layer is locked'
          : 'Inspections layer is locked');
      return;
    }
    final isTreatment = kind == _CalloutKind.treatment;
    final annotation = GraphAnnotation(
      kind: isTreatment ? GraphAnnotationKind.marker : GraphAnnotationKind.text,
      point: GraphPoint.fromOffset(boxCenter),
      label: '',
      note: '',
      markerType:
          isTreatment ? GraphMarkerType.treatmentNote : GraphMarkerType.damage,
      color: isTreatment ? GraphMarkerType.treatmentNote.defaultColor : null,
      size: isTreatment
          ? _markerDefaultsFor(GraphMarkerType.treatmentNote).size
          : 1,
      fontSize: isTreatment ? 16 : _defaultTextFontSize,
      bold: isTreatment ? true : _defaultTextBold,
      textColor: isTreatment ? Colors.black : _defaultTextColor,
      backgroundColor:
          isTreatment ? const Color(0xFF245BDB) : _defaultTextBackground,
      borderColor: isTreatment ? Colors.black : _defaultTextBorder,
      extraProperties: {
        'calloutTipX': tip.x,
        'calloutTipY': tip.y,
      },
    );
    final index = _annotations.length;
    setState(() {
      _annotations = [..._annotations, annotation];
      _selection = _Selection.annotation(index);
      _interaction.setSelected(_interactionReference(_selection!));
      _canvasStatus = 'Type the callout on the graph';
    });
    _beginInlineTextEditing(index, isNew: true);
  }

  void _editTreatmentCallout(int index) {
    if (index < 0 || index >= _annotations.length) return;
    _beginInlineTextEditing(index);
  }

  Future<Map<String, Uint8List>> _collectPortalBlobs() async {
    final blobs = <String, Uint8List>{};
    final blobKeys = <String>{
      for (final attachment in _document.attachments)
        if (attachment.blobKey.isNotEmpty) attachment.blobKey,
      for (final attachment in _document.attachments)
        if (attachment.thumbnailKey.isNotEmpty) attachment.thumbnailKey,
    };
    for (final key in blobKeys) {
      final bytes = _pendingPhotoBlobs[key] ?? await _repository.loadBlob(key);
      if (bytes != null) blobs[key] = bytes;
    }
    return blobs;
  }

  Future<void> _addPhotoMarker(GraphPoint point) async {
    final source = await showModalBottomSheet<_PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text('Add photos'),
              subtitle: Text('Multiple images can be attached to one pin.'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose Photos or Files'),
              subtitle: const Text('Select one or more images'),
              onTap: () => Navigator.pop(context, _PhotoSource.files),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, _PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;

    try {
      late final List<PickedGraphPhoto> picked;
      if (source == _PhotoSource.files) {
        picked = await _photoPicker.chooseMultiple();
      } else {
        final captured = await _photoPicker.capture();
        picked = captured == null ? <PickedGraphPhoto>[] : [captured];
      }
      if (!mounted || picked.isEmpty) return;

      final annotationId = newGraphId();
      final photoNumber = _document.nextPhotoNumber;
      final optimized = <OptimizedGraphPhoto>[];
      for (var index = 0; index < picked.length; index += 1) {
        final photo = picked[index];
        setState(() {
          _canvasStatus = 'Optimizing photo ${index + 1} of ${picked.length}…';
        });
        optimized.add(
          await optimizeGraphPhotoAsync(
            source: photo,
            annotationId: annotationId,
            attachmentId: newGraphId(),
            referenceLabel: '$photoNumber${_photoLetter(index)}',
          ),
        );
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            optimized.length == 1
                ? 'Add this photo?'
                : 'Add ${optimized.length} photos?',
          ),
          content: SizedBox(
            width: 520,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final photo in optimized)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      photo.thumbnailBytes,
                      width: 112,
                      height: 84,
                      fit: BoxFit.cover,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add to Graph'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;

      _document.reservePhotoNumber();
      final attachments = optimized.map((item) => item.attachment).toList();
      final annotation = GraphAnnotation(
        id: annotationId,
        kind: GraphAnnotationKind.photo,
        point: point,
        label: '$photoNumber',
        markerType: GraphMarkerType.camera,
        attachmentIds: attachments.map((item) => item.id).toList(),
      );
      setState(() {
        _annotations = [..._annotations, annotation];
        _document
            .replaceAttachments([..._document.attachments, ...attachments]);
        for (final photo in optimized) {
          _pendingPhotoBlobs[photo.attachment.blobKey] = photo.bytes;
          _pendingPhotoBlobs[photo.attachment.thumbnailKey] =
              photo.thumbnailBytes;
        }
        _undoStack.add(const _UndoEntry(_UndoKind.annotation));
        _canvasStatus =
            '${optimized.length} photo(s) added at pin $photoNumber';
      });
    } catch (error) {
      if (mounted) {
        _showCanvasMessage(
          'Photos could not be added: $error',
          severity: _CanvasMessageSeverity.error,
        );
      }
    }
  }

  Future<void> _showPhotoGallery(GraphAnnotation annotation) async {
    final attachmentIds = annotation.attachmentIds.toSet();
    final attachments = _document.attachments
        .where((attachment) => attachmentIds.contains(attachment.id))
        .toList(growable: false);
    if (attachments.isEmpty) {
      _showCanvasMessage('No photos are attached to this pin');
      return;
    }

    final photos = <({GraphAttachment attachment, Uint8List? bytes})>[];
    for (final attachment in attachments) {
      final bytes = _pendingPhotoBlobs[attachment.blobKey] ??
          await _repository.loadBlob(attachment.blobKey);
      photos.add((attachment: attachment, bytes: bytes));
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        attachments.length == 1
                            ? 'Photo attachment'
                            : '${attachments.length} photo attachments',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close photos',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: photos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              photo.attachment.referenceLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                photo.attachment.name,
                                style: Theme.of(context).textTheme.titleSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (photo.bytes case final bytes?)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Padding(
                                padding: EdgeInsets.all(24),
                                child:
                                    Text('This photo could not be displayed.'),
                              ),
                            ),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('This photo is no longer available.'),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _photoLetter(int index) {
    var value = index + 1;
    final letters = <int>[];
    while (value > 0) {
      value -= 1;
      letters.add(97 + (value % 26));
      value ~/= 26;
    }
    return String.fromCharCodes(letters.reversed);
  }

  void _togglePropertiesCollapsed() {
    setState(() {
      _sidePanelMode = _sidePanelMode == _SidePanelMode.properties
          ? null
          : _SidePanelMode.properties;
      _canvasStatus =
          _sidePanelMode == null ? 'Properties collapsed' : 'Properties shown';
    });
  }

  void _toggleLayersPanel() {
    setState(() {
      _sidePanelMode = _sidePanelMode == _SidePanelMode.layers
          ? null
          : _SidePanelMode.layers;
      _canvasStatus =
          _sidePanelMode == null ? 'Layers collapsed' : 'Layers shown';
    });
  }

  void _toggleLayersCollapsed() {
    setState(() {
      _layersCollapsed = !_layersCollapsed;
      _canvasStatus = _layersCollapsed ? 'Layers collapsed' : 'Layers shown';
    });
  }

  bool _selectionBelongsToLayer(_Selection selection, _GraphLayer layer) {
    if (selection.kind == _SelectionKind.annotation &&
        (selection.index < 0 || selection.index >= _annotations.length)) {
      return false;
    }

    return _layerForSelection(selection) == layer;
  }

  String _layerLabel(_GraphLayer layer) {
    return switch (layer) {
      _GraphLayer.structure => 'Building Structure',
      _GraphLayer.shapes => 'Shapes',
      _GraphLayer.inspections => 'Inspections',
      _GraphLayer.treatment => 'Treatment',
      _GraphLayer.photos => 'Photos',
      _GraphLayer.trace => 'Trace',
    };
  }

  List<WallSegment> get _previewShapeSegments {
    final start = _shapeDrawStart;
    final current = _shapeDrawCurrent;
    if (start == null ||
        current == null ||
        !_isPresetShapeTool(_selectedTool)) {
      return const <WallSegment>[];
    }

    final rect = _normalizeMinimumRect(
      _rectFromDrag(
        start,
        current,
        forceSquare: _selectedTool == CanvasTool.square ||
            _selectedTool == CanvasTool.circle,
      ),
    );
    return _segmentsForPresetShapeTool(_selectedTool, rect);
  }

  GraphShape? get _previewShape {
    final segments = _previewShapeSegments;
    if (segments.isEmpty) {
      return null;
    }

    return GraphShape(
      name: _defaultShapeName(_selectedTool),
      segmentIndexes: [
        for (var i = 0; i < segments.length; i += 1) i,
      ],
      fillColor: _currentShapeFillColor,
      fillOpacity: _currentShapeFillOpacity,
      borderColor: _currentShapeBorderColor,
      borderWidth: _currentShapeBorderWidth,
      pattern: _currentShapePattern,
      closed: true,
      rotationDegrees: 0,
      preset: _selectedDrawingPreset,
    );
  }

  Future<void> _exportGraphPdf() =>
      _exportGraphToOpsBrain(GraphFileKind.pdfExport);

  Future<void> _exportGraphPng() =>
      _exportGraphToOpsBrain(GraphFileKind.pngExport);

  // Shared rendering for the PDF and PNG export actions. Returns null (after
  // showing its own message) when the canvas isn't ready yet; callers stop.
  Future<Uint8List?> _renderExportBytes(GraphFileKind kind) async {
    final boundary = _canvasBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      _showCanvasMessage(
        'Graph export is not ready yet',
        severity: _CanvasMessageSeverity.warning,
      );
      return null;
    }

    final bounds = ExportBoundsCalculator.forDocument(
      _document,
      canvasSize: _canvasSize,
      structureVisible: _isLayerVisible(_GraphLayer.structure),
      shapesVisible: _isLayerVisible(_GraphLayer.structure) &&
          _isLayerVisible(_GraphLayer.shapes),
      inspectionsVisible: _isLayerVisible(_GraphLayer.inspections),
      treatmentVisible: _isLayerVisible(_GraphLayer.treatment),
      photosVisible: _isLayerVisible(_GraphLayer.photos),
      traceVisible: _traceLayerVisible,
    );
    final legend = buildGraphLegend(
      _annotations,
      shapes: _shapes,
      inspectionsVisible: _isLayerVisible(_GraphLayer.inspections),
      treatmentVisible: _isLayerVisible(_GraphLayer.treatment),
    );
    final brandingLogo =
        (await rootBundle.load('assets/branding/holloman_exterminators.png'))
            .buffer
            .asUint8List();
    final isPng = kind == GraphFileKind.pngExport;
    final pngBytes = await GraphImageExport.capturePng(
      boundary,
      bounds,
      legend: isPng ? legend : const [],
      measurementSummary: isPng
          ? _buildExportMeasurementSummary()
              .map((item) => '${item.label}: ${item.measurements.join(' ')}')
              .toList(growable: false)
          : const [],
      brandingLogo: isPng ? brandingLogo : null,
    );
    if (isPng) return pngBytes;
    return GraphPdfExport.build(
      graphPng: pngBytes,
      title: _document.customer.displayName,
      legend: legend,
      measurementSummary: _buildExportMeasurementSummary(),
      brandingLogo: brandingLogo,
      // Marker-icon glyphs are intentionally NOT embedded in the PDF
      // legend: the `pdf` package (3.13.0) detects a font's Unicode
      // support by checking for a raw TrueType `glyf` table
      // signature, which MaterialIcons-Regular.otf (a CFF-flavored
      // OpenType font, signature `OTTO`) fails. That misdetection
      // makes the package try to Latin1-encode the Material Icon's
      // private-use-area codepoint and throw, which is the root
      // cause PDF export always failed while PNG export (which
      // never touches this font) worked. GraphPdfExport.build()
      // already renders a solid-color square per legend entry when
      // markerIconFontBytes is omitted, so the legend still reads
      // correctly without embedding glyphs.
      photos: _isLayerVisible(_GraphLayer.photos)
          ? await _buildPdfPhotos()
          : const [],
    );
  }

  Future<List<GraphPdfPhoto>> _buildPdfPhotos() async {
    final result = <GraphPdfPhoto>[];
    final visiblePhotoIds = _annotations
        .where((item) => item.kind == GraphAnnotationKind.photo)
        .expand((item) => item.attachmentIds)
        .toSet();
    for (final attachment in _document.attachments) {
      if (!visiblePhotoIds.contains(attachment.id)) continue;
      final bytes = _pendingPhotoBlobs[attachment.blobKey] ??
          await _repository.loadBlob(attachment.blobKey);
      if (bytes == null) continue;
      result.add(
        GraphPdfPhoto(
          referenceLabel: attachment.referenceLabel.isEmpty
              ? 'Photo'
              : attachment.referenceLabel,
          filename: attachment.name,
          bytes: bytes,
        ),
      );
    }
    return result;
  }

  List<GraphMeasurementSummary> _buildExportMeasurementSummary() {
    final summaries = <GraphMeasurementSummary>[];
    for (final shape in _shapes) {
      final segments = <WallSegment>[
        for (final index in shape.segmentIndexes)
          if (index >= 0 && index < _wallSegments.length) _wallSegments[index],
      ];
      final measurements = shapeExportMeasurements(shape, segments);
      if (measurements.isEmpty) continue;
      summaries.add(
        GraphMeasurementSummary(
          label: shape.text.trim().isEmpty ? shape.name : shape.text,
          measurements: measurements,
        ),
      );
    }
    return summaries;
  }

  void _zoomBy(double factor) {
    final currentMatrix = _transformationController.value.clone();
    currentMatrix
      ..setEntry(0, 0, currentMatrix.entry(0, 0) * factor)
      ..setEntry(1, 1, currentMatrix.entry(1, 1) * factor)
      ..setEntry(2, 2, currentMatrix.entry(2, 2) * factor);
    _transformationController.value = currentMatrix;
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
    setState(() {
      _scaleLabel = '1:1';
      _canvasStatus = 'Scale reset to 1:1';
    });
  }

  void _toggleGridVisible() {
    setState(() {
      _gridVisible = !_gridVisible;
      _canvasStatus = _gridVisible ? 'Grid visible' : 'Grid hidden';
    });
  }

  void _toggleSnapToGrid() {
    setState(() {
      _snapToGrid = !_snapToGrid;
      _canvasStatus = _snapToGrid ? 'Snap to grid on' : 'Snap to grid off';
    });
  }

  void _setScaleLabel(String value) {
    final requestedScale = double.tryParse(value.split(':').first) ?? 1.0;
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final viewportBox =
        _canvasViewportKey.currentContext?.findRenderObject() as RenderBox?;
    final viewportCenter =
        viewportBox?.size.center(Offset.zero) ?? const Offset(0, 0);
    _zoomAt(viewportCenter, requestedScale / currentScale);
    setState(() {
      _scaleLabel = value;
      _canvasStatus = 'Scale set to $value';
    });
  }

  void _updateAnnotationLabel(int index, String label) {
    if (index < 0 || index >= _annotations.length) {
      return;
    }

    if (_isAnnotationLocked(_annotations[index])) {
      _showCanvasMessage('Selected layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextAnnotations = <GraphAnnotation>[..._annotations];
    nextAnnotations[index] = nextAnnotations[index].copyWith(label: label);

    setState(() {
      _annotations = nextAnnotations;
      _canvasStatus = 'Label updated';
    });
  }

  void _updateAnnotationMarkerType(int index, GraphMarkerType markerType) {
    if (index < 0 || index >= _annotations.length) {
      return;
    }
    if (_isAnnotationLocked(_annotations[index])) {
      _showCanvasMessage('Selected layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final markerDefault = _markerDefaultsFor(markerType);
    final nextAnnotations = <GraphAnnotation>[..._annotations];
    nextAnnotations[index] = nextAnnotations[index].copyWith(
      markerType: markerType,
      color: markerDefault.color,
      size: markerDefault.size,
      label: markerType.shortLabel,
    );

    setState(() {
      _annotations = nextAnnotations;
      _canvasStatus = 'Marker type updated';
    });
  }

  void _updateAnnotationColor(int index, Color color) {
    if (index < 0 || index >= _annotations.length) {
      return;
    }
    if (_isAnnotationLocked(_annotations[index])) {
      _showCanvasMessage('Selected layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextAnnotations = <GraphAnnotation>[..._annotations];
    nextAnnotations[index] = nextAnnotations[index].copyWith(color: color);

    setState(() {
      _annotations = nextAnnotations;
      _canvasStatus = 'Marker color updated';
    });
  }

  void _updateAnnotationSize(int index, double size) {
    if (index < 0 || index >= _annotations.length) {
      return;
    }
    if (_isAnnotationLocked(_annotations[index])) {
      _showCanvasMessage('Selected layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextAnnotations = <GraphAnnotation>[..._annotations];
    nextAnnotations[index] = nextAnnotations[index].copyWith(size: size);

    setState(() {
      _annotations = nextAnnotations;
      _canvasStatus = 'Marker size updated';
    });
  }

  void _updateAnnotationRotation(int index, double rotationDegrees) {
    if (index < 0 || index >= _annotations.length) {
      return;
    }
    if (_isAnnotationLocked(_annotations[index])) {
      _showCanvasMessage('Selected layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextAnnotations = <GraphAnnotation>[..._annotations];
    nextAnnotations[index] = nextAnnotations[index].copyWith(
      rotationDegrees: rotationDegrees,
    );

    setState(() {
      _annotations = nextAnnotations;
      _canvasStatus = 'Marker rotation updated';
    });
  }

  void _updateAnnotationNote(int index, String note) {
    if (index < 0 || index >= _annotations.length) {
      return;
    }
    if (_isAnnotationLocked(_annotations[index])) {
      _showCanvasMessage('Selected layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextAnnotations = <GraphAnnotation>[..._annotations];
    nextAnnotations[index] = nextAnnotations[index].copyWith(note: note);

    setState(() {
      _annotations = nextAnnotations;
      _canvasStatus = 'Note updated';
    });
  }

  void _updateTextFontSize(int index, double fontSize) {
    _updateTextStyle(index, fontSize: fontSize, status: 'Text size updated');
  }

  void _updateTextBold(int index, bool bold) {
    _updateTextStyle(index, bold: bold, status: 'Text weight updated');
  }

  void _updateTextItalic(int index, bool italic) {
    _updateTextStyle(index, italic: italic, status: 'Text style updated');
  }

  void _updateTextColor(int index, Color color) {
    _updateTextStyle(index, textColor: color, status: 'Text color updated');
  }

  void _updateTextBackground(int index, Color color) {
    _updateTextStyle(
      index,
      backgroundColor: color,
      status: 'Text background updated',
    );
  }

  void _updateTextBorder(int index, Color color) {
    _updateTextStyle(index, borderColor: color, status: 'Text border updated');
  }

  void _updateTextStyle(
    int index, {
    double? fontSize,
    bool? bold,
    bool? italic,
    Color? textColor,
    Color? backgroundColor,
    Color? borderColor,
    required String status,
  }) {
    if (index < 0 || index >= _annotations.length) {
      return;
    }
    if (_isAnnotationLocked(_annotations[index])) {
      _showCanvasMessage('Selected layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextAnnotations = <GraphAnnotation>[..._annotations];
    nextAnnotations[index] = nextAnnotations[index].copyWith(
      fontSize: fontSize,
      bold: bold,
      italic: italic,
      textColor: textColor,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
    );

    setState(() {
      _annotations = nextAnnotations;
      _canvasStatus = status;
    });
  }

  void _setMarkerDefault(int index) {
    if (index < 0 || index >= _annotations.length) {
      return;
    }

    final annotation = _annotations[index];
    if (annotation.kind != GraphAnnotationKind.marker) {
      return;
    }

    setState(() {
      _markerDefaults[annotation.markerType] = _MarkerStyleDefaults(
        color: annotation.color ?? annotation.markerType.defaultColor,
        size: annotation.size,
      );
      _interaction.selectMarker(annotation.markerType);
      _selectedMarkerColor =
          annotation.color ?? annotation.markerType.defaultColor;
      _selectedMarkerSize = annotation.size;
      _canvasStatus =
          '${annotation.markerType.shortLabel} set as marker default';
    });
    // Persist outside setState: this only affects future marker placements,
    // never the document itself, so it must not affect dirty state.
    _persistMarkerDefaults();
  }

  void _setTextDefault(int index) {
    if (index < 0 || index >= _annotations.length) {
      return;
    }

    final annotation = _annotations[index];
    if (annotation.kind != GraphAnnotationKind.text) {
      return;
    }

    setState(() {
      _defaultTextFontSize = annotation.fontSize;
      _defaultTextBold = annotation.bold;
      _defaultTextColor = annotation.textColor;
      _defaultTextBackground = annotation.backgroundColor;
      _defaultTextBorder = annotation.borderColor;
      _canvasStatus = 'Text style set as default';
    });
  }

  void _setLineDefault(int index) {
    if (index < 0 || index >= _wallSegments.length) {
      return;
    }

    final segment = _wallSegments[index];
    setState(() {
      final preset = _selectedDrawingPreset;
      if (preset != null && preset.kind == GraphDrawingPresetKind.line) {
        final current = _drawingDefaultsFor(preset);
        _drawingPresetDefaults[preset] = current.copyWith(
          lineColor: segment.color,
          lineWidth: segment.strokeWidth,
          linePattern: segment.pattern,
        );
        _canvasStatus = '${preset.label} line style set as default';
      } else {
        if (segment.hasArrow) {
          _defaultArrowColor = segment.color;
          _defaultArrowWidth = segment.strokeWidth;
          _defaultArrowPattern = segment.pattern;
          _canvasStatus = 'Arrow style set as default';
        } else {
          _defaultLineColor = segment.color;
          _defaultLineWidth = segment.strokeWidth;
          _defaultLinePattern = segment.pattern;
          _canvasStatus = 'Line style set as default';
        }
      }
    });
  }

  void _setShapeDefault(int index) {
    if (index < 0 || index >= _shapes.length) {
      return;
    }

    final shape = _shapes[index];
    setState(() {
      final preset = shape.preset;
      if (preset != null && preset.kind == GraphDrawingPresetKind.area) {
        final current = _drawingDefaultsFor(preset);
        _drawingPresetDefaults[preset] = current.copyWith(
          fillColor: shape.fillColor,
          clearFillColor: shape.fillColor == null,
          fillOpacity: shape.fillOpacity,
          borderColor: shape.borderColor,
          borderWidth: shape.borderWidth,
          pattern: shape.pattern,
        );
        _canvasStatus = '${preset.label} style set as default';
      } else {
        _defaultShapeFillColor = shape.fillColor;
        _defaultShapeFillOpacity = shape.fillOpacity;
        _defaultShapeBorderColor = shape.borderColor;
        _defaultShapeBorderWidth = shape.borderWidth;
        _defaultShapePattern = shape.pattern;
        _canvasStatus = 'Shape style set as default';
      }
    });
  }

  void _setFreehandDefault(int index) {
    if (index < 0 || index >= _freehandStrokes.length) {
      return;
    }

    final stroke = _freehandStrokes[index];
    setState(() {
      _defaultFreehandColor = stroke.color;
      _defaultFreehandWidth = stroke.strokeWidth;
      _defaultFreehandOpacity = stroke.opacity;
      _canvasStatus = 'Freehand style set as default';
    });
  }

  void _updateSegmentColor(int index, Color color) {
    if (index < 0 || index >= _wallSegments.length) {
      return;
    }
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextSegments = <WallSegment>[..._wallSegments];
    nextSegments[index] = nextSegments[index].copyWith(color: color);
    setState(() {
      _wallSegments = nextSegments;
      _canvasStatus = 'Line color updated';
    });
  }

  void _updateSegmentPattern(int index, LinePattern pattern) {
    if (index < 0 || index >= _wallSegments.length) {
      return;
    }
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextSegments = <WallSegment>[..._wallSegments];
    nextSegments[index] = nextSegments[index].copyWith(pattern: pattern);
    setState(() {
      _wallSegments = nextSegments;
      _canvasStatus = 'Line pattern updated';
    });
  }

  void _updateSegmentWidth(int index, double strokeWidth) {
    if (index < 0 || index >= _wallSegments.length) {
      return;
    }
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextSegments = <WallSegment>[..._wallSegments];
    nextSegments[index] =
        nextSegments[index].copyWith(strokeWidth: strokeWidth);
    setState(() {
      _wallSegments = nextSegments;
      _canvasStatus = 'Line width updated';
    });
  }

  void _updateSegmentArrow(int index, bool hasArrow) {
    if (index < 0 || index >= _wallSegments.length) {
      return;
    }
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextSegments = <WallSegment>[..._wallSegments];
    nextSegments[index] = nextSegments[index].copyWith(hasArrow: hasArrow);
    setState(() {
      _wallSegments = nextSegments;
      _canvasStatus = hasArrow ? 'Arrow enabled' : 'Arrow disabled';
    });
  }

  void _updateFreehandColor(int index, Color color) {
    if (index < 0 || index >= _freehandStrokes.length) {
      return;
    }
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextStrokes = <FreehandStroke>[..._freehandStrokes];
    nextStrokes[index] = nextStrokes[index].copyWith(color: color);
    setState(() {
      _freehandStrokes = nextStrokes;
      _canvasStatus = 'Freehand color updated';
    });
  }

  void _updateFreehandWidth(int index, double strokeWidth) {
    if (index < 0 || index >= _freehandStrokes.length) {
      return;
    }
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextStrokes = <FreehandStroke>[..._freehandStrokes];
    nextStrokes[index] = nextStrokes[index].copyWith(strokeWidth: strokeWidth);
    setState(() {
      _freehandStrokes = nextStrokes;
      _canvasStatus = 'Freehand width updated';
    });
  }

  void _updateFreehandOpacity(int index, double opacity) {
    if (index < 0 || index >= _freehandStrokes.length) {
      return;
    }
    if (_isLayerLocked(_GraphLayer.structure)) {
      _showCanvasMessage('Structure layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextStrokes = <FreehandStroke>[..._freehandStrokes];
    nextStrokes[index] = nextStrokes[index].copyWith(opacity: opacity);
    setState(() {
      _freehandStrokes = nextStrokes;
      _canvasStatus = 'Freehand opacity updated';
    });
  }

  void _updateShapeName(int index, String name) {
    if (index < 0 || index >= _shapes.length) {
      return;
    }

    if (_isLayerLocked(_GraphLayer.shapes)) {
      _showCanvasMessage('Shapes layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextShapes = <GraphShape>[..._shapes];
    nextShapes[index] = nextShapes[index].copyWith(name: name);

    setState(() {
      _shapes = nextShapes;
      _canvasStatus = 'Shape name updated';
    });
  }

  void _updateTraceLabel(int index, String label) {
    if (index < 0 ||
        index >= _traces.length ||
        _isLayerLocked(_GraphLayer.trace)) {
      return;
    }
    _recordSnapshotUndo();
    final nextTraces = <TraceGeometry>[..._traces];
    nextTraces[index] = nextTraces[index].copyWith(label: label);
    setState(() {
      _document.replaceTraces(nextTraces);
      _canvasStatus = 'Trace label updated';
    });
  }

  void _updateShapeFill(int index, Color? fillColor) {
    if (index < 0 || index >= _shapes.length) {
      return;
    }

    if (_isLayerLocked(_GraphLayer.shapes)) {
      _showCanvasMessage('Shapes layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextShapes = <GraphShape>[..._shapes];
    nextShapes[index] = nextShapes[index].copyWith(
      fillColor: fillColor,
      clearFillColor: fillColor == null,
      fillOpacity: _fillOpacityForColor(fillColor),
    );

    setState(() {
      _shapes = nextShapes;
      _canvasStatus = 'Shape fill updated';
    });
  }

  double _fillOpacityForColor(Color? color) {
    for (final choice in _ShapeFillChoice.values) {
      if (choice.color == color) {
        return choice.opacity;
      }
    }

    return color == null ? 0 : 0.32;
  }

  _ShapeFillChoice _shapeFillChoiceForColor(Color? color) {
    for (final choice in _ShapeFillChoice.values) {
      if (choice.color == color) {
        return choice;
      }
    }

    return _ShapeFillChoice.none;
  }

  _ShapeBorderChoice _shapeBorderChoiceForColor(Color color) {
    for (final choice in _ShapeBorderChoice.values) {
      if (choice.color == color) {
        return choice;
      }
    }

    return _ShapeBorderChoice.darkGreen;
  }

  void _updateShapeBorderColor(int index, Color borderColor) {
    if (index < 0 || index >= _shapes.length) {
      return;
    }

    if (_isLayerLocked(_GraphLayer.shapes)) {
      _showCanvasMessage('Shapes layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextShapes = <GraphShape>[..._shapes];
    nextShapes[index] = nextShapes[index].copyWith(borderColor: borderColor);

    setState(() {
      _shapes = nextShapes;
      _canvasStatus = 'Shape border updated';
    });
  }

  void _updateShapeBorderWidth(int index, double borderWidth) {
    if (index < 0 || index >= _shapes.length) {
      return;
    }

    if (_isLayerLocked(_GraphLayer.shapes)) {
      _showCanvasMessage('Shapes layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextShapes = <GraphShape>[..._shapes];
    nextShapes[index] = nextShapes[index].copyWith(borderWidth: borderWidth);

    setState(() {
      _shapes = nextShapes;
      _canvasStatus = 'Shape border width updated';
    });
  }

  void _updateShapePattern(int index, GraphShapePattern pattern) {
    if (index < 0 || index >= _shapes.length) {
      return;
    }

    if (_isLayerLocked(_GraphLayer.shapes)) {
      _showCanvasMessage('Shapes layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextShapes = <GraphShape>[..._shapes];
    nextShapes[index] = nextShapes[index].copyWith(pattern: pattern);

    setState(() {
      _shapes = nextShapes;
      _canvasStatus = 'Shape pattern updated';
    });
  }

  void _updateShapeFoundationType(
    int index,
    StructureFoundationType foundationType,
  ) {
    if (index < 0 || index >= _shapes.length) {
      return;
    }
    if (_isLayerLocked(_GraphLayer.shapes)) {
      _showCanvasMessage('Shapes layer is locked');
      return;
    }

    _recordSnapshotUndo();
    final nextShapes = <GraphShape>[..._shapes];
    final nextProperties = <String, Object?>{
      ...nextShapes[index].extraProperties,
      'foundationType': foundationType.name,
    };
    nextShapes[index] = nextShapes[index].copyWith(
      extraProperties: nextProperties,
    );
    setState(() {
      _shapes = nextShapes;
      _canvasStatus = 'Main Structure foundation updated';
    });
  }

  void _recordSnapshotUndo() {
    if (_applyingHistory) {
      return;
    }
    _undoStack.add(
      _UndoEntry(
        _UndoKind.snapshot,
        previousSnapshot: _EditorSnapshot.capture(this),
      ),
    );
    _redoStack.clear();
  }

  String? get _latestPropertyLineMeasurementSummary {
    for (final shape in _shapes.reversed) {
      if (shape.preset != GraphDrawingPreset.propertyLine || !shape.closed) {
        continue;
      }
      final shapeSegments = <WallSegment>[
        for (final index in shape.segmentIndexes)
          if (index >= 0 && index < _wallSegments.length) _wallSegments[index],
      ];
      final summary = shapeMeasurementSummary(shape, shapeSegments);
      if (summary.isNotEmpty) {
        return summary;
      }
    }
    return null;
  }

  MouseCursor get _canvasCursor {
    final hovered = _hoverSelection;
    if (_selectedTool == CanvasTool.select && hovered != null) {
      return _isSelectionEditable(hovered)
          ? SystemMouseCursors.move
          : SystemMouseCursors.click;
    }
    if (_interaction.dragging) {
      return SystemMouseCursors.grabbing;
    }
    return switch (_selectedTool) {
      CanvasTool.pan => SystemMouseCursors.grab,
      CanvasTool.structure ||
      CanvasTool.rectangle ||
      CanvasTool.square ||
      CanvasTool.circle ||
      CanvasTool.ellipse ||
      CanvasTool.triangle ||
      CanvasTool.wall ||
      CanvasTool.arrow ||
      CanvasTool.curve ||
      CanvasTool.freehand ||
      CanvasTool.callout ||
      CanvasTool.marker ||
      CanvasTool.photo =>
        SystemMouseCursors.precise,
      CanvasTool.text => SystemMouseCursors.text,
      CanvasTool.select => SystemMouseCursors.basic,
    };
  }

  Widget? _buildInlineTextEditor() {
    final index = _inlineTextAnnotationIndex;
    if (index == null || index < 0 || index >= _annotations.length) {
      return null;
    }

    final annotation = _annotations[index];
    final textPainter = TextPainter(
      text: TextSpan(
        text: _inlineTextController.text.isEmpty
            ? 'Type note'
            : _inlineTextController.text,
        style: TextStyle(
          fontSize: annotation.fontSize,
          fontWeight: annotation.bold ? FontWeight.w800 : FontWeight.w500,
          fontStyle: annotation.italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 260);
    final width =
        math.max(132.0, math.min(280.0, textPainter.width + 32)).toDouble();
    final left = (annotation.point.x - (width / 2))
        .clamp(8.0, _canvasSize.width - width - 8)
        .toDouble();
    final top = (annotation.point.y - 28)
        .clamp(8.0, _canvasSize.height - 56)
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Material(
        color: Colors.transparent,
        child: TextField(
          key: const ValueKey('inline-canvas-text-editor'),
          controller: _inlineTextController,
          focusNode: _inlineTextFocusNode,
          autofocus: true,
          maxLines: null,
          minLines: 1,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          style: TextStyle(
            color: annotation.textColor,
            fontSize: annotation.fontSize,
            fontWeight: annotation.bold ? FontWeight.w800 : FontWeight.w500,
            fontStyle: annotation.italic ? FontStyle.italic : FontStyle.normal,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Type note',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: annotation.backgroundColor,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: annotation.borderColor, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: annotation.borderColor, width: 2),
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _finishInlineTextEditing(),
        ),
      ),
    );
  }

  Future<void> _showAboutDialog() async {
    final packageInfo = await PackageInfo.fromPlatform();

    if (!mounted) return;

    showAboutDialog(
      context: context,
      applicationName: 'BugManGraphs',
      applicationVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
      applicationLegalese: '© 2026 Holloman Exterminators',
      children: const [
        SizedBox(height: 12),
        Text('Environment: Production'),
        Text('Hosted on Cloudflare Pages'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.presentationMode) {
      return _buildPresentationView(context);
    }
    const sidePanelWidth = 268.0;
    const canvasRightInset = 12.0;
    const canvasLeftInset = 12.0;
    final canvasBottomInset = _quickToolbarCollapsed ? 12.0 : 82.0;
    final documentTitle = _document.customer.displayName;
    final propertyLineSummary = _latestPropertyLineMeasurementSummary;
    final viewportWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        title: Text(
          _document.isDirty ? '$documentTitle • Unsaved' : documentTitle,
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'about') {
                _showAboutDialog();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'about',
                child: Text('About BugManGraphs'),
              ),
            ],
          ),
        ],
      ),
      body: Focus(
        focusNode: _editorFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      left: canvasLeftInset,
                      top: 54,
                      right: canvasRightInset,
                      bottom: canvasBottomInset,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _centerCanvasInViewport(constraints.biggest);
                          return MouseRegion(
                            cursor: _canvasCursor,
                            child: Listener(
                              key: _canvasViewportKey,
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: _handlePointerDown,
                              onPointerMove: _handlePointerMove,
                              onPointerHover: _handlePointerHover,
                              onPointerUp: _handlePointerUp,
                              onPointerCancel: _handlePointerCancel,
                              onPointerSignal: _handlePointerSignal,
                              child: InteractiveViewer(
                                transformationController:
                                    _transformationController,
                                panEnabled: _selectedTool == CanvasTool.pan ||
                                    _spacePanActive,
                                scaleEnabled: true,
                                constrained: false,
                                minScale: 0.25,
                                maxScale: 10,
                                boundaryMargin: const EdgeInsets.all(1200),
                                child: RepaintBoundary(
                                  key: _canvasBoundaryKey,
                                  child: _CanvasSurface(
                                    canvasSize: _canvasSize,
                                    wallSegments: _wallSegments,
                                    annotations: _annotations,
                                    shapes: _shapes,
                                    freehandStrokes: _freehandStrokes,
                                    traces: _traces,
                                    draftFreehandPoints: _draftFreehandPoints,
                                    previewShapeSegments: _previewShapeSegments,
                                    previewShape: _previewShape,
                                    hiddenSegmentIndexes: _shapeSegmentIndexSet,
                                    gridVisible: _gridVisible,
                                    selectedSegmentIndex:
                                        _selection?.segmentIndex,
                                    selectedAnnotationIndex:
                                        _selection?.annotationIndex,
                                    selectedShapeIndex: _selection?.shapeIndex,
                                    selectedFreehandIndex:
                                        _selection?.freehandIndex,
                                    selectedTraceIndex: _selection?.traceIndex,
                                    hoveredSegmentIndex:
                                        _hoverSelection?.segmentIndex,
                                    hoveredAnnotationIndex:
                                        _hoverSelection?.annotationIndex,
                                    hoveredShapeIndex:
                                        _hoverSelection?.shapeIndex,
                                    hoveredFreehandIndex:
                                        _hoverSelection?.freehandIndex,
                                    hoveredTraceIndex:
                                        _hoverSelection?.traceIndex,
                                    activeWallStart: _activeWallStart,
                                    previewSegment: _previewSegment,
                                    treatmentCalloutTip: _treatmentCalloutTip,
                                    treatmentCalloutBox: _treatmentCalloutBox,
                                    activeCalloutKind: _activeCalloutKind,
                                    inlineTextEditor: _buildInlineTextEditor(),
                                    structureVisible:
                                        _isLayerVisible(_GraphLayer.structure),
                                    shapesVisible: _isLayerVisible(
                                            _GraphLayer.structure) &&
                                        _isLayerVisible(_GraphLayer.shapes),
                                    inspectionsVisible: _isLayerVisible(
                                        _GraphLayer.inspections),
                                    treatmentVisible:
                                        _isLayerVisible(_GraphLayer.treatment),
                                    photosVisible:
                                        _isLayerVisible(_GraphLayer.photos),
                                    traceLayerVisible: _traceLayerVisible,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (!_mainToolbarCollapsed)
                      Positioned(
                        left: 12,
                        top: 54,
                        bottom: 12,
                        width: 112,
                        child: CanvasToolbar(
                          selectedTool: _selectedTool,
                          selectedMarkerType: _selectedMarkerType,
                          selectedDrawingPreset: _selectedDrawingPreset,
                          onToolSelected: _selectTool,
                          onMarkerSelected: _selectMarker,
                          onDrawingPresetSelected: _selectDrawingPreset,
                          traceLayerVisible: _traceLayerVisible,
                          onToggleTraceLayer: () => _openTraceWorkspace(),
                          onCollapse: () => setState(
                            () => _mainToolbarCollapsed = true,
                          ),
                          onActionDoubleTapped: _inspectToolbarAction,
                        ),
                      )
                    else
                      Positioned(
                        left: 12,
                        top: 54,
                        child: Material(
                          elevation: 6,
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          child: IconButton(
                            tooltip: 'Show main toolbar',
                            onPressed: () => setState(
                              () => _mainToolbarCollapsed = false,
                            ),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ),
                      ),
                    Positioned(
                      left: canvasLeftInset,
                      right: canvasRightInset,
                      bottom: 12,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: _quickToolbarCollapsed
                            ? Material(
                                elevation: 8,
                                color: Colors.white,
                                shape: const CircleBorder(),
                                child: IconButton(
                                  key: const ValueKey(
                                    'show-canvas-quick-toolbar',
                                  ),
                                  tooltip: 'Show quick toolbar',
                                  onPressed: () => setState(
                                    () => _quickToolbarCollapsed = false,
                                  ),
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                ),
                              )
                            : CanvasQuickToolbar(
                                actions: _quickToolbarActions,
                                selectedTool: _selectedTool,
                                selectedMarkerType: _selectedMarkerType,
                                selectedDrawingPreset: _selectedDrawingPreset,
                                onActionSelected: _activateToolbarAction,
                                onActionAdded: _addQuickToolbarAction,
                                onReset: _resetQuickToolbar,
                                propertiesSelected:
                                    _sidePanelMode == _SidePanelMode.properties,
                                layersSelected:
                                    _sidePanelMode == _SidePanelMode.layers,
                                onToggleProperties: _togglePropertiesCollapsed,
                                onToggleLayers: _toggleLayersPanel,
                                onDeleteSelection: _deleteSelection,
                                onUndo: _undoLastAction,
                                onRedo: _redoLastAction,
                                onCollapse: () => setState(
                                  () => _quickToolbarCollapsed = true,
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 8,
                      child: Tooltip(
                        message: _canvasStatus,
                        child: _TopEditorToolbar(
                          onUndo: _undoLastAction,
                          onRedo: _redoLastAction,
                          onFinish: _finishWallPath,
                          finishLabel: _selectedTool == CanvasTool.structure &&
                                  _selectedStructureType ==
                                      GraphDrawingPreset.measurementLine
                              ? 'Finish Measure'
                              : 'Close Shape',
                          onClear: _confirmClearGraph,
                          onSaveGraphFile: _handleGraphFileSaveTapped,
                          onExportPdf: _exportGraphPdf,
                          onExportPng: _exportGraphPng,
                          onSaveAndCreateSalesBrainReport:
                              _saveAndCreateSalesBrainReport,
                          onNewWithExistingStructure:
                              _newGraphWithExistingStructure,
                          onZoomIn: () => _zoomBy(1.2),
                          onZoomOut: () => _zoomBy(0.85),
                          onResetZoom: _resetZoom,
                          gridVisible: _gridVisible,
                          onToggleGrid: _toggleGridVisible,
                          snapToGrid: _snapToGrid,
                          onToggleSnapToGrid: _toggleSnapToGrid,
                          scaleLabel: _scaleLabel,
                          onScaleChanged: _setScaleLabel,
                        ),
                      ),
                    ),
                    if (propertyLineSummary != null &&
                        (_sidePanelMode == null || viewportWidth >= 720))
                      Positioned(
                        key: const ValueKey(
                          'property-line-measurement-summary',
                        ),
                        top: 72,
                        right:
                            _sidePanelMode == null ? 24 : sidePanelWidth + 24,
                        child: IgnorePointer(
                          child: Card(
                            elevation: 5,
                            color: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'Property Line (acres)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(propertyLineSummary),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_sidePanelMode != null)
                      Positioned(
                        top: 54,
                        right: 12,
                        bottom: 82,
                        width: sidePanelWidth,
                        child: _PropertiesSidebar(
                          layersOnly: _sidePanelMode == _SidePanelMode.layers,
                          selection: _selection,
                          annotations: _annotations,
                          wallSegments: _wallSegments,
                          shapes: _shapes,
                          freehandStrokes: _freehandStrokes,
                          traces: _traces,
                          layerSettings: _layerSettings,
                          traceLayerVisible: _traceLayerVisible,
                          layersCollapsed: _layersCollapsed,
                          onCollapsePanel: () => setState(
                            () => _sidePanelMode = null,
                          ),
                          onToggleLayersCollapsed: _toggleLayersCollapsed,
                          onToggleLayerVisibility: _toggleLayerVisibility,
                          onToggleLayerLock: _toggleLayerLock,
                          onAnnotationLabelChanged: _updateAnnotationLabel,
                          onAnnotationMarkerTypeChanged:
                              _updateAnnotationMarkerType,
                          onAnnotationColorChanged: _updateAnnotationColor,
                          onAnnotationSizeChanged: _updateAnnotationSize,
                          onAnnotationRotationChanged:
                              _updateAnnotationRotation,
                          onAnnotationNoteChanged: _updateAnnotationNote,
                          onTextFontSizeChanged: _updateTextFontSize,
                          onTextBoldChanged: _updateTextBold,
                          onTextItalicChanged: _updateTextItalic,
                          onTextColorChanged: _updateTextColor,
                          onTextBackgroundChanged: _updateTextBackground,
                          onTextBorderChanged: _updateTextBorder,
                          onSetMarkerDefault: _setMarkerDefault,
                          onSetTextDefault: _setTextDefault,
                          onSegmentColorChanged: _updateSegmentColor,
                          onSegmentPatternChanged: _updateSegmentPattern,
                          onSegmentWidthChanged: _updateSegmentWidth,
                          onSegmentArrowChanged: _updateSegmentArrow,
                          onSetLineDefault: _setLineDefault,
                          onFreehandColorChanged: _updateFreehandColor,
                          onFreehandWidthChanged: _updateFreehandWidth,
                          onFreehandOpacityChanged: _updateFreehandOpacity,
                          onSetFreehandDefault: _setFreehandDefault,
                          onShapeNameChanged: _updateShapeName,
                          onShapeFillChanged: _updateShapeFill,
                          onShapeBorderColorChanged: _updateShapeBorderColor,
                          onShapeBorderWidthChanged: _updateShapeBorderWidth,
                          onShapePatternChanged: _updateShapePattern,
                          onShapeFoundationTypeChanged:
                              _updateShapeFoundationType,
                          onSetShapeDefault: _setShapeDefault,
                          onTraceLabelChanged: _updateTraceLabel,
                          onEditTrace: (index) =>
                              _openTraceWorkspace(editIndex: index),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _capturePresentationPng() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !widget.presentationMode) throw StateError('Unavailable');
    final boundary = _presentationBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('Not ready');
    // A separate filtered document keeps internal markup out of crop bounds too.
    final presentation = GraphDocument(
      customer: _document.customer,
      wallSegments: _wallSegments,
      shapes: _shapes,
      traces: _traces,
      annotations: _annotations
          .where((annotation) =>
              annotation.kind == GraphAnnotationKind.marker &&
              widget.presentationMarkerIds.contains(annotation.id))
          .toList(),
    );
    try {
      return await GraphImageExport.capturePng(
          boundary,
          ExportBoundsCalculator.forDocument(presentation,
              canvasSize: _canvasSize,
              treatmentVisible: false,
              photosVisible: false,
              traceVisible: true));
    } finally {
      presentation.dispose();
    }
  }

  Widget _buildPresentationView(BuildContext context) {
    final visibleAnnotations = _annotations
        .where((annotation) =>
            annotation.kind == GraphAnnotationKind.marker &&
            widget.presentationMarkerIds.contains(annotation.id))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        automaticallyImplyLeading: false,
        title: Text(_document.customer.displayName),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _centerCanvasInViewport(constraints.biggest);
            return InteractiveViewer(
              transformationController: _transformationController,
              panEnabled: true,
              scaleEnabled: true,
              constrained: false,
              minScale: 0.25,
              maxScale: 10,
              boundaryMargin: const EdgeInsets.all(1200),
              child: RepaintBoundary(
                key: _presentationBoundaryKey,
                child: _CanvasSurface(
                  canvasSize: _canvasSize,
                  wallSegments: _wallSegments,
                  annotations: visibleAnnotations,
                  shapes: _shapes,
                  freehandStrokes: const <FreehandStroke>[],
                  traces: _traces,
                  draftFreehandPoints: const <GraphPoint>[],
                  previewShapeSegments: const <WallSegment>[],
                  previewShape: null,
                  hiddenSegmentIndexes: _shapeSegmentIndexSet,
                  gridVisible: false,
                  selectedSegmentIndex: null,
                  selectedAnnotationIndex: null,
                  selectedShapeIndex: null,
                  selectedFreehandIndex: null,
                  selectedTraceIndex: null,
                  hoveredSegmentIndex: null,
                  hoveredAnnotationIndex: null,
                  hoveredShapeIndex: null,
                  hoveredFreehandIndex: null,
                  hoveredTraceIndex: null,
                  activeWallStart: null,
                  previewSegment: null,
                  treatmentCalloutTip: null,
                  treatmentCalloutBox: null,
                  activeCalloutKind: null,
                  structureVisible: true,
                  shapesVisible: true,
                  inspectionsVisible: true,
                  treatmentVisible: false,
                  photosVisible: false,
                  traceLayerVisible: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopEditorToolbar extends StatelessWidget {
  const _TopEditorToolbar({
    required this.onUndo,
    required this.onRedo,
    required this.onFinish,
    required this.finishLabel,
    required this.onClear,
    required this.onSaveGraphFile,
    required this.onExportPdf,
    required this.onExportPng,
    required this.onSaveAndCreateSalesBrainReport,
    required this.onNewWithExistingStructure,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
    required this.gridVisible,
    required this.onToggleGrid,
    required this.snapToGrid,
    required this.onToggleSnapToGrid,
    required this.scaleLabel,
    required this.onScaleChanged,
  });

  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onFinish;
  final String finishLabel;
  final VoidCallback onClear;
  final VoidCallback onSaveGraphFile;
  final VoidCallback onExportPdf;
  final VoidCallback onExportPng;
  final VoidCallback onSaveAndCreateSalesBrainReport;
  final VoidCallback onNewWithExistingStructure;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;
  final bool gridVisible;
  final VoidCallback onToggleGrid;
  final bool snapToGrid;
  final VoidCallback onToggleSnapToGrid;
  final String scaleLabel;
  final ValueChanged<String> onScaleChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
      child: SizedBox(
        height: 46,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _IconOnlyButton(
                icon: Icons.undo,
                tooltip: 'Undo',
                onPressed: onUndo,
              ),
              _IconOnlyButton(
                icon: Icons.redo,
                tooltip: 'Redo',
                onPressed: onRedo,
              ),
              const _ToolbarDivider(),
              _TopButton(
                  icon: Icons.done, label: finishLabel, onPressed: onFinish),
              _TopButton(
                icon: Icons.delete_outline,
                label: 'Clear Graph',
                onPressed: onClear,
              ),
              const _ToolbarDivider(),
              _IconOnlyButton(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onPressed: onZoomOut,
              ),
              _TopButton(
                icon: Icons.fit_screen,
                label: 'Reset',
                onPressed: onResetZoom,
              ),
              _IconOnlyButton(
                icon: Icons.add,
                tooltip: 'Zoom in',
                onPressed: onZoomIn,
              ),
              const _ToolbarDivider(),
              PopupMenuButton<_EditorOptionAction>(
                tooltip: 'Canvas options',
                onSelected: (action) {
                  switch (action) {
                    case _EditorOptionAction.grid:
                      onToggleGrid();
                    case _EditorOptionAction.snapGrid:
                      onToggleSnapToGrid();
                    case _EditorOptionAction.scale1:
                      onScaleChanged('1:1');
                    case _EditorOptionAction.scale2:
                      onScaleChanged('2:1');
                    case _EditorOptionAction.scale3:
                      onScaleChanged('3:1');
                    case _EditorOptionAction.scale4:
                      onScaleChanged('4:1');
                    case _EditorOptionAction.scale10:
                      onScaleChanged('10:1');
                  }
                },
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    value: _EditorOptionAction.grid,
                    checked: gridVisible,
                    child: const Text('Grid'),
                  ),
                  CheckedPopupMenuItem(
                    value: _EditorOptionAction.snapGrid,
                    checked: snapToGrid,
                    child: const Text('Snap to grid'),
                  ),
                  const PopupMenuDivider(),
                  for (final entry in const {
                    _EditorOptionAction.scale1: '1:1',
                    _EditorOptionAction.scale2: '2:1',
                    _EditorOptionAction.scale3: '3:1',
                    _EditorOptionAction.scale4: '4:1',
                    _EditorOptionAction.scale10: '10:1',
                  }.entries)
                    CheckedPopupMenuItem(
                      value: entry.key,
                      checked: scaleLabel == entry.value,
                      child: Text(entry.value),
                    ),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Icon(Icons.tune, size: 18),
                      SizedBox(width: 5),
                      Text('Options'),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<_EditorFileAction>(
                tooltip: 'File actions',
                onSelected: (action) => switch (action) {
                  _EditorFileAction.saveGraphFile => onSaveGraphFile(),
                  _EditorFileAction.exportPdf => onExportPdf(),
                  _EditorFileAction.exportPng => onExportPng(),
                  _EditorFileAction.saveAndCreateSalesBrainReport =>
                    onSaveAndCreateSalesBrainReport(),
                  _EditorFileAction.newWithExistingStructure =>
                    onNewWithExistingStructure(),
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    enabled: false,
                    height: 28,
                    child: Text(
                      'SAVE TO OPS BRAIN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EditorFileAction.saveGraphFile,
                    child: ListTile(
                      leading: Icon(Icons.save_outlined),
                      title: Text('Graph File'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EditorFileAction.saveAndCreateSalesBrainReport,
                    child: ListTile(
                      leading: Icon(Icons.receipt_long_outlined),
                      title: Text('Save & Open Inspection Workflow'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    enabled: false,
                    height: 28,
                    child: Text(
                      'EXPORT FILE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EditorFileAction.exportPdf,
                    child: ListTile(
                      leading: Icon(Icons.ios_share),
                      title: Text('Export PDF'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EditorFileAction.exportPng,
                    child: ListTile(
                      leading: Icon(Icons.ios_share),
                      title: Text('Export PNG'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: _EditorFileAction.newWithExistingStructure,
                    child: ListTile(
                      leading: Icon(Icons.difference_outlined),
                      title: Text('Copy Structure to New Graph'),
                    ),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 18),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

class _IconOnlyButton extends StatelessWidget {
  const _IconOnlyButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: const Color(0xFFE3E0D8),
    );
  }
}

class _PropertiesSidebar extends StatelessWidget {
  const _PropertiesSidebar({
    required this.layersOnly,
    required this.selection,
    required this.annotations,
    required this.wallSegments,
    required this.shapes,
    required this.freehandStrokes,
    required this.traces,
    required this.layerSettings,
    required this.traceLayerVisible,
    required this.layersCollapsed,
    required this.onCollapsePanel,
    required this.onToggleLayersCollapsed,
    required this.onToggleLayerVisibility,
    required this.onToggleLayerLock,
    required this.onAnnotationLabelChanged,
    required this.onAnnotationMarkerTypeChanged,
    required this.onAnnotationColorChanged,
    required this.onAnnotationSizeChanged,
    required this.onAnnotationRotationChanged,
    required this.onAnnotationNoteChanged,
    required this.onTextFontSizeChanged,
    required this.onTextBoldChanged,
    required this.onTextItalicChanged,
    required this.onTextColorChanged,
    required this.onTextBackgroundChanged,
    required this.onTextBorderChanged,
    required this.onSetMarkerDefault,
    required this.onSetTextDefault,
    required this.onSegmentColorChanged,
    required this.onSegmentPatternChanged,
    required this.onSegmentWidthChanged,
    required this.onSegmentArrowChanged,
    required this.onSetLineDefault,
    required this.onFreehandColorChanged,
    required this.onFreehandWidthChanged,
    required this.onFreehandOpacityChanged,
    required this.onSetFreehandDefault,
    required this.onShapeNameChanged,
    required this.onShapeFillChanged,
    required this.onShapeBorderColorChanged,
    required this.onShapeBorderWidthChanged,
    required this.onShapePatternChanged,
    required this.onShapeFoundationTypeChanged,
    required this.onSetShapeDefault,
    required this.onTraceLabelChanged,
    required this.onEditTrace,
  });

  final bool layersOnly;
  final _Selection? selection;
  final List<GraphAnnotation> annotations;
  final List<WallSegment> wallSegments;
  final List<GraphShape> shapes;
  final List<FreehandStroke> freehandStrokes;
  final List<TraceGeometry> traces;
  final Map<_GraphLayer, _LayerSettings> layerSettings;
  final bool traceLayerVisible;
  final bool layersCollapsed;
  final VoidCallback onCollapsePanel;
  final VoidCallback onToggleLayersCollapsed;
  final ValueChanged<_GraphLayer> onToggleLayerVisibility;
  final ValueChanged<_GraphLayer> onToggleLayerLock;
  final void Function(int index, String label) onAnnotationLabelChanged;
  final void Function(int index, GraphMarkerType markerType)
      onAnnotationMarkerTypeChanged;
  final void Function(int index, Color color) onAnnotationColorChanged;
  final void Function(int index, double size) onAnnotationSizeChanged;
  final void Function(int index, double rotationDegrees)
      onAnnotationRotationChanged;
  final void Function(int index, String note) onAnnotationNoteChanged;
  final void Function(int index, double fontSize) onTextFontSizeChanged;
  final void Function(int index, bool bold) onTextBoldChanged;
  final void Function(int index, bool italic) onTextItalicChanged;
  final void Function(int index, Color color) onTextColorChanged;
  final void Function(int index, Color color) onTextBackgroundChanged;
  final void Function(int index, Color color) onTextBorderChanged;
  final ValueChanged<int> onSetMarkerDefault;
  final ValueChanged<int> onSetTextDefault;
  final void Function(int index, Color color) onSegmentColorChanged;
  final void Function(int index, LinePattern pattern) onSegmentPatternChanged;
  final void Function(int index, double strokeWidth) onSegmentWidthChanged;
  final void Function(int index, bool hasArrow) onSegmentArrowChanged;
  final ValueChanged<int> onSetLineDefault;
  final void Function(int index, Color color) onFreehandColorChanged;
  final void Function(int index, double strokeWidth) onFreehandWidthChanged;
  final void Function(int index, double opacity) onFreehandOpacityChanged;
  final ValueChanged<int> onSetFreehandDefault;
  final void Function(int index, String name) onShapeNameChanged;
  final void Function(int index, Color? fillColor) onShapeFillChanged;
  final void Function(int index, Color borderColor) onShapeBorderColorChanged;
  final void Function(int index, double borderWidth) onShapeBorderWidthChanged;
  final void Function(int index, GraphShapePattern pattern)
      onShapePatternChanged;
  final void Function(int index, StructureFoundationType foundationType)
      onShapeFoundationTypeChanged;
  final ValueChanged<int> onSetShapeDefault;
  final void Function(int index, String label) onTraceLabelChanged;
  final ValueChanged<int> onEditTrace;

  @override
  Widget build(BuildContext context) {
    if (layersOnly) {
      return Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'Layers',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Collapse layers',
                    visualDensity: VisualDensity.compact,
                    onPressed: onCollapsePanel,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: _LayersPanel(
                    wallCount: wallSegments.length,
                    shapeCount: shapes
                        .where((shape) =>
                            shape.preset != GraphDrawingPreset.treatmentArea)
                        .length,
                    inspectionCount: annotations
                        .where((item) =>
                            item.kind != GraphAnnotationKind.photo &&
                            !(item.kind == GraphAnnotationKind.marker &&
                                (isTreatmentMarker(item.markerType) ||
                                    utilityMarkerTypes
                                        .contains(item.markerType))))
                        .length,
                    treatmentCount: annotations
                            .where((item) =>
                                item.kind == GraphAnnotationKind.marker &&
                                isTreatmentMarker(item.markerType))
                            .length +
                        shapes
                            .where((shape) =>
                                shape.preset ==
                                GraphDrawingPreset.treatmentArea)
                            .length,
                    photoCount: annotations
                        .where((item) => item.kind == GraphAnnotationKind.photo)
                        .length,
                    layerSettings: layerSettings,
                    traceLayerVisible: traceLayerVisible,
                    onCollapse: onCollapsePanel,
                    onToggleVisibility: onToggleLayerVisibility,
                    onToggleLock: onToggleLayerLock,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Properties',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Collapse properties',
                  visualDensity: VisualDensity.compact,
                  onPressed: onCollapsePanel,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(child: _buildContent(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final currentSelection = selection;

    if (currentSelection == null) {
      return _InspectorSection(
        title: 'Properties',
        children: [
          Text(
            'Select an object to edit its properties.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          const _InspectorValue(label: 'Editor', value: 'Drawings mode'),
        ],
      );
    }

    if (currentSelection.traceIndex case final index?
        when index < traces.length) {
      final trace = traces[index];
      final measurement = MeasurementService.measureTrace(
        trace,
        status: MeasurementAccuracyStatus.estimated,
      );
      final traceLocked = _isLayerLocked(_GraphLayer.trace);
      return _InspectorSection(
        title: 'Trace Properties',
        children: [
          TextFormField(
            key: ValueKey('trace-$index'),
            initialValue: trace.label,
            decoration: const InputDecoration(labelText: 'Label'),
            enabled: !traceLocked,
            onChanged: traceLocked
                ? null
                : (value) => onTraceLabelChanged(index, value),
          ),
          const SizedBox(height: 10),
          _InspectorValue(
            label: 'Corners',
            value: trace.canvasPoints.length.toString(),
          ),
          const SizedBox(height: 8),
          _InspectorValue(
            label: 'Perimeter',
            value: MeasurementFormat.linearFeet(measurement.linearFeet),
          ),
          const SizedBox(height: 8),
          _InspectorValue(
            label: 'Area',
            value: MeasurementFormat.squareFeet(measurement.squareFeet),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: traceLocked ? null : () => onEditTrace(index),
            icon: const Icon(Icons.edit_location_alt_outlined),
            label: const Text('Edit Map Points'),
          ),
          const SizedBox(height: 8),
          Text(
            traceLocked
                ? 'Unlock the Trace layer to edit this outline.'
                : 'Drag the blue corner handles on the canvas, or edit the '
                    'original points on the map.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    if (currentSelection.annotationIndex case final index?
        when index < annotations.length) {
      final annotation = annotations[index];
      final annotationLocked = _isLayerLocked(_layerForAnnotation(annotation));
      return _InspectorSection(
        title: 'Item Properties',
        children: [
          _InspectorValue(label: 'Type', value: annotation.kind.name),
          const SizedBox(height: 10),
          if (annotation.kind == GraphAnnotationKind.marker) ...[
            DropdownButtonFormField<GraphMarkerType>(
              initialValue: annotation.markerType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Marker type'),
              items: GraphMarkerType.values
                  .where((type) =>
                      type.availableForNewPlacement ||
                      type == annotation.markerType)
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(
                        type.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: annotationLocked
                  ? null
                  : (value) {
                      if (value != null) {
                        onAnnotationMarkerTypeChanged(index, value);
                      }
                    },
            ),
            const SizedBox(height: 10),
            _MarkerColorPickerField(
              color: annotation.color ?? annotation.markerType.defaultColor,
              enabled: !annotationLocked,
              onColorChanged: (color) => onAnnotationColorChanged(index, color),
            ),
            const SizedBox(height: 10),
            _LabeledSlider(
              label: 'Size',
              value: annotation.size,
              min: 0.7,
              max: 1.8,
              enabled: !annotationLocked,
              onChanged: (value) => onAnnotationSizeChanged(index, value),
            ),
            _LabeledSlider(
              label: 'Rotation',
              value: annotation.rotationDegrees,
              min: 0,
              max: 360,
              enabled: !annotationLocked,
              onChanged: (value) => onAnnotationRotationChanged(index, value),
            ),
          ],
          if (annotation.kind == GraphAnnotationKind.text) ...[
            _LabeledSlider(
              label: 'Font',
              value: annotation.fontSize,
              min: 10,
              max: 32,
              enabled: !annotationLocked,
              onChanged: (value) => onTextFontSizeChanged(index, value),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Bold'),
                  selected: annotation.bold,
                  onSelected: annotationLocked
                      ? null
                      : (value) => onTextBoldChanged(index, value),
                ),
                FilterChip(
                  label: const Text('Italic'),
                  selected: annotation.italic,
                  onSelected: annotationLocked
                      ? null
                      : (value) => onTextItalicChanged(index, value),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<_MarkerColorChoice>(
              initialValue: _markerColorChoiceForColor(annotation.textColor),
              decoration: const InputDecoration(labelText: 'Text color'),
              items: _MarkerColorChoice.values
                  .map(
                    (choice) => DropdownMenuItem(
                      value: choice,
                      child: _ColorChoiceLabel(
                        label: choice.label,
                        color: choice.color,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: annotationLocked
                  ? null
                  : (choice) {
                      if (choice != null) {
                        onTextColorChanged(index, choice.color);
                      }
                    },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<_ShapeFillChoice>(
              initialValue: _fillChoiceForColor(annotation.backgroundColor),
              decoration: const InputDecoration(labelText: 'Background'),
              items: _ShapeFillChoice.values
                  .where((choice) => choice.color != null)
                  .map(
                    (choice) => DropdownMenuItem(
                      value: choice,
                      child: _ColorChoiceLabel(
                        label: choice.label,
                        color: choice.color,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: annotationLocked
                  ? null
                  : (choice) {
                      if (choice?.color != null) {
                        onTextBackgroundChanged(index, choice!.color!);
                      }
                    },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<_MarkerColorChoice>(
              initialValue: _markerColorChoiceForColor(annotation.borderColor),
              decoration: const InputDecoration(labelText: 'Border'),
              items: _MarkerColorChoice.values
                  .map(
                    (choice) => DropdownMenuItem(
                      value: choice,
                      child: _ColorChoiceLabel(
                        label: choice.label,
                        color: choice.color,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: annotationLocked
                  ? null
                  : (choice) {
                      if (choice != null) {
                        onTextBorderChanged(index, choice.color);
                      }
                    },
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed:
                  annotationLocked ? null : () => onSetTextDefault(index),
              child: const Text('Set as Default'),
            ),
            const SizedBox(height: 10),
          ],
          TextFormField(
            key: ValueKey('annotation-$index'),
            initialValue: annotation.label,
            decoration: const InputDecoration(labelText: 'Label'),
            enabled: !annotationLocked,
            onChanged: annotationLocked
                ? null
                : (value) => onAnnotationLabelChanged(index, value),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('annotation-note-$index'),
            initialValue: annotation.note,
            decoration: const InputDecoration(labelText: 'Notes'),
            enabled: !annotationLocked,
            maxLines: 2,
            onChanged: annotationLocked
                ? null
                : (value) => onAnnotationNoteChanged(index, value),
          ),
          if (annotation.kind == GraphAnnotationKind.marker) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed:
                  annotationLocked ? null : () => onSetMarkerDefault(index),
              child: const Text('Set as Default'),
            ),
          ],
          const SizedBox(height: 10),
          _InspectorValue(
            label: 'Position',
            value:
                '${annotation.point.x.round()}, ${annotation.point.y.round()}',
          ),
        ],
      );
    }

    if (currentSelection.segmentIndex case final index?
        when index < wallSegments.length) {
      final segment = wallSegments[index];
      final structureLocked = _isLayerLocked(_GraphLayer.structure);
      return _InspectorSection(
        title: 'Line Properties',
        children: [
          _InspectorValue(
            label: 'Type',
            value: segment.hasArrow
                ? 'Arrow'
                : segment.isCurve
                    ? 'Curve'
                    : 'Straight line',
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<_MarkerColorChoice>(
            initialValue: _markerColorChoiceForColor(segment.color),
            decoration: const InputDecoration(labelText: 'Color'),
            items: _MarkerColorChoice.values
                .map(
                  (choice) => DropdownMenuItem(
                    value: choice,
                    child: _ColorChoiceLabel(
                      label: choice.label,
                      color: choice.color,
                    ),
                  ),
                )
                .toList(),
            onChanged: structureLocked
                ? null
                : (choice) {
                    if (choice != null) {
                      onSegmentColorChanged(index, choice.color);
                    }
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<LinePattern>(
            initialValue: segment.pattern,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Line style'),
            items: LinePattern.values
                .map(
                  (pattern) => DropdownMenuItem(
                    value: pattern,
                    child: Text(pattern.label),
                  ),
                )
                .toList(),
            onChanged: structureLocked
                ? null
                : (pattern) {
                    if (pattern != null) {
                      onSegmentPatternChanged(index, pattern);
                    }
                  },
          ),
          _LabeledSlider(
            label: 'Width',
            value: segment.strokeWidth,
            min: 2,
            max: 10,
            enabled: !structureLocked,
            onChanged: (value) => onSegmentWidthChanged(index, value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Arrow head'),
            value: segment.hasArrow,
            onChanged: structureLocked
                ? null
                : (value) => onSegmentArrowChanged(index, value),
          ),
          OutlinedButton(
            onPressed: structureLocked ? null : () => onSetLineDefault(index),
            child: const Text('Set as Default'),
          ),
          if (!segment.hasArrow) ...[
            const SizedBox(height: 8),
            _InspectorValue(label: 'Length', value: segment.measurementLabel),
          ],
          const SizedBox(height: 8),
          _InspectorValue(
            label: 'Start',
            value: '${segment.start.x.round()}, ${segment.start.y.round()}',
          ),
          const SizedBox(height: 8),
          _InspectorValue(
            label: 'End',
            value: '${segment.end.x.round()}, ${segment.end.y.round()}',
          ),
        ],
      );
    }

    if (currentSelection.shapeIndex case final index?
        when index < shapes.length) {
      final shape = shapes[index];
      final shapeLocked = _isLayerLocked(_GraphLayer.shapes);
      return _InspectorSection(
        title: 'Shape Properties',
        children: [
          _InspectorValue(
            label: 'Preset',
            value: shape.preset?.label ?? 'Custom',
          ),
          const SizedBox(height: 10),
          if (shape.preset == GraphDrawingPreset.mainStructure) ...[
            DropdownButtonFormField<StructureFoundationType>(
              initialValue: shape.foundationType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Foundation'),
              hint: const Text('Select foundation'),
              items: StructureFoundationType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    ),
                  )
                  .toList(),
              onChanged: shapeLocked
                  ? null
                  : (type) {
                      if (type != null) {
                        onShapeFoundationTypeChanged(index, type);
                      }
                    },
            ),
            const SizedBox(height: 10),
          ],
          TextFormField(
            key: ValueKey('shape-$index'),
            initialValue: shape.name,
            decoration: const InputDecoration(labelText: 'Name'),
            enabled: !shapeLocked,
            onChanged: shapeLocked
                ? null
                : (value) => onShapeNameChanged(index, value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<_ShapeFillChoice>(
            initialValue: _fillChoiceForColor(shape.fillColor),
            decoration: const InputDecoration(labelText: 'Fill'),
            items: _ShapeFillChoice.values
                .map(
                  (choice) => DropdownMenuItem(
                    value: choice,
                    child: _ColorChoiceLabel(
                      label: choice.label,
                      color: choice.color,
                    ),
                  ),
                )
                .toList(),
            onChanged: shapeLocked
                ? null
                : (choice) {
                    if (choice != null) {
                      onShapeFillChanged(index, choice.color);
                    }
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<_ShapeBorderChoice>(
            initialValue: _borderChoiceForColor(shape.borderColor),
            decoration: const InputDecoration(labelText: 'Border'),
            items: _ShapeBorderChoice.values
                .map(
                  (choice) => DropdownMenuItem(
                    value: choice,
                    child: _ColorChoiceLabel(
                      label: choice.label,
                      color: choice.color,
                    ),
                  ),
                )
                .toList(),
            onChanged: shapeLocked
                ? null
                : (choice) {
                    if (choice != null) {
                      onShapeBorderColorChanged(index, choice.color);
                    }
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<double>(
            initialValue: shape.borderWidth,
            decoration: const InputDecoration(labelText: 'Border width'),
            items: const [
              DropdownMenuItem(value: 2.0, child: Text('Thin')),
              DropdownMenuItem(value: 3.0, child: Text('Medium')),
              DropdownMenuItem(value: 5.0, child: Text('Heavy')),
            ],
            onChanged: shapeLocked
                ? null
                : (value) {
                    if (value != null) {
                      onShapeBorderWidthChanged(index, value);
                    }
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<GraphShapePattern>(
            initialValue: shape.pattern,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Pattern'),
            items: GraphShapePattern.values
                .map(
                  (pattern) => DropdownMenuItem(
                    value: pattern,
                    child: Text(_patternLabel(pattern)),
                  ),
                )
                .toList(),
            onChanged: shapeLocked
                ? null
                : (pattern) {
                    if (pattern != null) {
                      onShapePatternChanged(index, pattern);
                    }
                  },
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: shapeLocked ? null : () => onSetShapeDefault(index),
            child: const Text('Set as Default'),
          ),
          const SizedBox(height: 10),
          _InspectorValue(
            label: 'Linear ft',
            value: MeasurementFormat.linearFeet(
              _shapeLinearFeet(shape),
              includeUnit: false,
            ),
          ),
          const SizedBox(height: 8),
          _InspectorValue(
            label: 'Square ft',
            value: MeasurementFormat.squareFeet(
              _shapeSquareFeet(shape),
              includeUnit: false,
            ),
          ),
        ],
      );
    }

    if (currentSelection.freehandIndex case final index?
        when index < freehandStrokes.length) {
      final stroke = freehandStrokes[index];
      final structureLocked = _isLayerLocked(_GraphLayer.structure);
      return _InspectorSection(
        title: 'Freehand Properties',
        children: [
          DropdownButtonFormField<_MarkerColorChoice>(
            initialValue: _markerColorChoiceForColor(stroke.color),
            decoration: const InputDecoration(labelText: 'Color'),
            items: _MarkerColorChoice.values
                .map(
                  (choice) => DropdownMenuItem(
                    value: choice,
                    child: _ColorChoiceLabel(
                      label: choice.label,
                      color: choice.color,
                    ),
                  ),
                )
                .toList(),
            onChanged: structureLocked
                ? null
                : (choice) {
                    if (choice != null) {
                      onFreehandColorChanged(index, choice.color);
                    }
                  },
          ),
          _LabeledSlider(
            label: 'Width',
            value: stroke.strokeWidth,
            min: 2,
            max: 12,
            enabled: !structureLocked,
            onChanged: (value) => onFreehandWidthChanged(index, value),
          ),
          _LabeledSlider(
            label: 'Opacity',
            value: stroke.opacity,
            min: 0.15,
            max: 1,
            enabled: !structureLocked,
            onChanged: (value) => onFreehandOpacityChanged(index, value),
          ),
          OutlinedButton(
            onPressed:
                structureLocked ? null : () => onSetFreehandDefault(index),
            child: const Text('Set as Default'),
          ),
          const SizedBox(height: 8),
          _InspectorValue(
            label: 'Points',
            value: stroke.points.length.toString(),
          ),
        ],
      );
    }

    return const _InspectorSection(
      title: 'Properties',
      children: [
        Text('Selected object is no longer available.'),
      ],
    );
  }

  _ShapeFillChoice _fillChoiceForColor(Color? color) {
    for (final choice in _ShapeFillChoice.values) {
      if (choice.color == color) {
        return choice;
      }
    }

    return _ShapeFillChoice.none;
  }

  _MarkerColorChoice _markerColorChoiceForColor(Color color) {
    for (final choice in _MarkerColorChoice.values) {
      if (choice.color == color) {
        return choice;
      }
    }

    return _MarkerColorChoice.red;
  }

  _ShapeBorderChoice _borderChoiceForColor(Color color) {
    for (final choice in _ShapeBorderChoice.values) {
      if (choice.color == color) {
        return choice;
      }
    }

    return _ShapeBorderChoice.darkGreen;
  }

  bool _isLayerLocked(_GraphLayer layer) {
    return layerSettings[layer]?.locked ?? false;
  }

  _GraphLayer _layerForAnnotation(GraphAnnotation annotation) {
    return annotation.kind == GraphAnnotationKind.photo
        ? _GraphLayer.photos
        : annotation.kind == GraphAnnotationKind.marker &&
                isTreatmentMarker(annotation.markerType)
            ? _GraphLayer.treatment
            : annotation.kind == GraphAnnotationKind.marker &&
                    utilityMarkerTypes.contains(annotation.markerType)
                ? _GraphLayer.structure
                : _GraphLayer.inspections;
  }

  double _shapeLinearFeet(GraphShape shape) {
    var total = 0.0;

    for (final index in shape.segmentIndexes) {
      if (index >= 0 && index < wallSegments.length) {
        total += wallSegments[index].lengthFeet;
      }
    }

    return total;
  }

  double _shapeSquareFeet(GraphShape shape) {
    if (!shape.closed || shape.segmentIndexes.length < 3) {
      return 0;
    }

    final points = <GraphPoint>[];

    for (final index in shape.segmentIndexes) {
      if (index >= 0 && index < wallSegments.length) {
        points.add(wallSegments[index].start);
      }
    }

    if (points.length < 3) {
      return 0;
    }

    var areaPixels = 0.0;

    for (var i = 0; i < points.length; i += 1) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      areaPixels += (current.x * next.y) - (next.x * current.y);
    }

    return areaPixels.abs() /
        2 /
        (WallSegment.pixelsPerFoot * WallSegment.pixelsPerFoot);
  }
}

class _InspectorSection extends StatelessWidget {
  const _InspectorSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _InspectorValue extends StatelessWidget {
  const _InspectorValue({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF666B62),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    );
  }
}

class _ColorChoiceLabel extends StatelessWidget {
  const _ColorChoiceLabel({
    required this.label,
    required this.color,
  });

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final swatchColor = color ?? Colors.transparent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: swatchColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF9B9F96)),
          ),
          child: color == null
              ? const Icon(Icons.block, size: 13, color: Color(0xFF666B62))
              : null,
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

/// Marker fill-color field. Restricted to the fixed 8-color marker palette
/// (see [markerColorPalette]) via `flex_color_picker`'s custom-swatch picker
/// - no Material primary/accent/wheel colors are offered here, since markers
/// must only ever use the approved palette. Existing marker colors saved
/// from before this palette existed (i.e. not one of the 8 swatches) are
/// preserved and simply shown with a "Custom" label instead of being reset.
class _MarkerColorPickerField extends StatelessWidget {
  const _MarkerColorPickerField({
    required this.color,
    required this.enabled,
    required this.onColorChanged,
  });

  final Color color;
  final bool enabled;
  final ValueChanged<Color> onColorChanged;

  String get _label {
    for (final entry in markerColorPalette.entries) {
      if (entry.value.toARGB32() == color.toARGB32()) {
        return entry.key;
      }
    }
    return 'Custom';
  }

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showColorPickerDialog(
      context,
      color,
      title: Text(
        'Marker color',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: false,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: false,
        ColorPickerType.custom: true,
        ColorPickerType.wheel: false,
      },
      customColorSwatchesAndNames: markerColorSwatchesAndNames,
      enableShadesSelection: false,
      showColorName: true,
      constraints: const BoxConstraints(
        minHeight: 320,
        minWidth: 300,
        maxWidth: 320,
      ),
    );
    // showColorPickerDialog resolves with the starting color when the
    // dialog is dismissed without a selection. Only report a change when
    // the color actually differs, so opening-then-cancelling this dialog
    // never marks the document dirty (see dirty-state tracking rules).
    if (selected.toARGB32() != color.toARGB32()) {
      onColorChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Color'),
      child: InkWell(
        onTap: enabled ? () => _openPicker(context) : null,
        child: _ColorChoiceLabel(label: _label, color: color),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label ${value.toStringAsFixed(label == 'Rotation' ? 0 : 1)}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

class _LayersPanel extends StatelessWidget {
  const _LayersPanel({
    required this.wallCount,
    required this.shapeCount,
    required this.inspectionCount,
    required this.treatmentCount,
    required this.photoCount,
    required this.layerSettings,
    required this.traceLayerVisible,
    required this.onCollapse,
    required this.onToggleVisibility,
    required this.onToggleLock,
  });

  final int wallCount;
  final int shapeCount;
  final int inspectionCount;
  final int treatmentCount;
  final int photoCount;
  final Map<_GraphLayer, _LayerSettings> layerSettings;
  final bool traceLayerVisible;
  final VoidCallback onCollapse;
  final ValueChanged<_GraphLayer> onToggleVisibility;
  final ValueChanged<_GraphLayer> onToggleLock;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Layers',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Collapse layers',
                visualDensity: VisualDensity.compact,
                onPressed: onCollapse,
                icon: const Icon(Icons.expand_more, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                _LayerRow(
                  icon: Icons.foundation_outlined,
                  name: 'Building Structure',
                  detail: '$wallCount lines • $shapeCount shapes',
                  visible: _isVisible(_GraphLayer.structure) &&
                      _isVisible(_GraphLayer.shapes),
                  locked: _isLocked(_GraphLayer.structure) ||
                      _isLocked(_GraphLayer.shapes),
                  onToggleVisibility: () =>
                      onToggleVisibility(_GraphLayer.structure),
                  onToggleLock: () => onToggleLock(_GraphLayer.structure),
                ),
                _LayerRow(
                  icon: Icons.place_outlined,
                  name: 'Inspections',
                  detail: '$inspectionCount markers',
                  visible: _isVisible(_GraphLayer.inspections),
                  locked: _isLocked(_GraphLayer.inspections),
                  onToggleVisibility: () =>
                      onToggleVisibility(_GraphLayer.inspections),
                  onToggleLock: () => onToggleLock(_GraphLayer.inspections),
                ),
                _LayerRow(
                  icon: Icons.medical_services_outlined,
                  name: 'Treatment',
                  detail: '$treatmentCount markers',
                  visible: _isVisible(_GraphLayer.treatment),
                  locked: _isLocked(_GraphLayer.treatment),
                  onToggleVisibility: () =>
                      onToggleVisibility(_GraphLayer.treatment),
                  onToggleLock: () => onToggleLock(_GraphLayer.treatment),
                ),
                _LayerRow(
                  icon: Icons.photo_camera_outlined,
                  name: 'Photos',
                  detail: '$photoCount pins',
                  visible: _isVisible(_GraphLayer.photos),
                  locked: _isLocked(_GraphLayer.photos),
                  onToggleVisibility: () =>
                      onToggleVisibility(_GraphLayer.photos),
                  onToggleLock: () => onToggleLock(_GraphLayer.photos),
                ),
                _LayerRow(
                  icon: Icons.layers_outlined,
                  name: 'Trace Layer',
                  detail:
                      traceLayerVisible ? 'address trace visible' : 'hidden',
                  visible: traceLayerVisible,
                  locked: _isLocked(_GraphLayer.trace),
                  onToggleVisibility: () =>
                      onToggleVisibility(_GraphLayer.trace),
                  onToggleLock: () => onToggleLock(_GraphLayer.trace),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isVisible(_GraphLayer layer) {
    if (layer == _GraphLayer.trace) {
      return traceLayerVisible;
    }

    return layerSettings[layer]?.visible ?? true;
  }

  bool _isLocked(_GraphLayer layer) {
    return layerSettings[layer]?.locked ?? false;
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.icon,
    required this.name,
    required this.detail,
    required this.visible,
    required this.locked,
    required this.onToggleVisibility,
    required this.onToggleLock,
  });

  final IconData icon;
  final String name;
  final String detail;
  final bool visible;
  final bool locked;
  final VoidCallback onToggleVisibility;
  final VoidCallback onToggleLock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF666B62),
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: visible ? 'Hide layer' : 'Show layer',
            visualDensity: VisualDensity.compact,
            onPressed: onToggleVisibility,
            icon: Icon(
              visible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 17,
            ),
          ),
          IconButton(
            tooltip: locked ? 'Unlock layer' : 'Lock layer',
            visualDensity: VisualDensity.compact,
            onPressed: onToggleLock,
            icon: Icon(
              locked ? Icons.lock_outline : Icons.lock_open_outlined,
              size: 17,
            ),
          ),
        ],
      ),
    );
  }
}

class _CanvasSurface extends StatelessWidget {
  const _CanvasSurface({
    required this.canvasSize,
    required this.wallSegments,
    required this.annotations,
    required this.shapes,
    required this.freehandStrokes,
    required this.traces,
    required this.draftFreehandPoints,
    required this.previewShapeSegments,
    required this.previewShape,
    required this.hiddenSegmentIndexes,
    required this.gridVisible,
    required this.selectedSegmentIndex,
    required this.selectedAnnotationIndex,
    required this.selectedShapeIndex,
    required this.selectedFreehandIndex,
    required this.selectedTraceIndex,
    required this.hoveredSegmentIndex,
    required this.hoveredAnnotationIndex,
    required this.hoveredShapeIndex,
    required this.hoveredFreehandIndex,
    required this.hoveredTraceIndex,
    required this.activeWallStart,
    required this.previewSegment,
    required this.treatmentCalloutTip,
    required this.treatmentCalloutBox,
    required this.activeCalloutKind,
    this.inlineTextEditor,
    required this.structureVisible,
    required this.shapesVisible,
    required this.inspectionsVisible,
    required this.treatmentVisible,
    required this.photosVisible,
    required this.traceLayerVisible,
  });

  final Size canvasSize;
  final List<WallSegment> wallSegments;
  final List<GraphAnnotation> annotations;
  final List<GraphShape> shapes;
  final List<FreehandStroke> freehandStrokes;
  final List<TraceGeometry> traces;
  final List<GraphPoint> draftFreehandPoints;
  final List<WallSegment> previewShapeSegments;
  final GraphShape? previewShape;
  final Set<int> hiddenSegmentIndexes;
  final bool gridVisible;
  final int? selectedSegmentIndex;
  final int? selectedAnnotationIndex;
  final int? selectedShapeIndex;
  final int? selectedFreehandIndex;
  final int? selectedTraceIndex;
  final int? hoveredSegmentIndex;
  final int? hoveredAnnotationIndex;
  final int? hoveredShapeIndex;
  final int? hoveredFreehandIndex;
  final int? hoveredTraceIndex;
  final GraphPoint? activeWallStart;
  final WallSegment? previewSegment;
  final GraphPoint? treatmentCalloutTip;
  final Offset? treatmentCalloutBox;
  final _CalloutKind? activeCalloutKind;
  final Widget? inlineTextEditor;
  final bool structureVisible;
  final bool shapesVisible;
  final bool inspectionsVisible;
  final bool treatmentVisible;
  final bool photosVisible;
  final bool traceLayerVisible;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: canvasSize.width,
      height: canvasSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            key: const ValueKey('graph-canvas-paint'),
            size: canvasSize,
            painter: GraphGridPainter(visible: gridVisible),
            foregroundPainter: _GraphOverlayPainter(
              wallSegments: wallSegments,
              annotations: annotations,
              shapes: shapes,
              freehandStrokes: freehandStrokes,
              draftFreehandPoints: draftFreehandPoints,
              previewShapeSegments: previewShapeSegments,
              previewShape: previewShape,
              hiddenSegmentIndexes: hiddenSegmentIndexes,
              selectedSegmentIndex: selectedSegmentIndex,
              selectedAnnotationIndex: selectedAnnotationIndex,
              selectedShapeIndex: selectedShapeIndex,
              selectedFreehandIndex: selectedFreehandIndex,
              hoveredSegmentIndex: hoveredSegmentIndex,
              hoveredAnnotationIndex: hoveredAnnotationIndex,
              hoveredShapeIndex: hoveredShapeIndex,
              hoveredFreehandIndex: hoveredFreehandIndex,
              activeWallStart: activeWallStart,
              previewSegment: previewSegment,
              treatmentCalloutTip: treatmentCalloutTip,
              treatmentCalloutBox: treatmentCalloutBox,
              activeCalloutKind: activeCalloutKind,
              structureVisible: structureVisible,
              shapesVisible: shapesVisible,
              inspectionsVisible: inspectionsVisible,
              treatmentVisible: treatmentVisible,
              photosVisible: photosVisible,
            ),
            child: SizedBox(
              width: canvasSize.width,
              height: canvasSize.height,
              child: traceLayerVisible
                  ? _TraceLayer(
                      traces: traces,
                      selectedTraceIndex: selectedTraceIndex,
                      hoveredTraceIndex: hoveredTraceIndex,
                    )
                  : null,
            ),
          ),
          if (inlineTextEditor != null) inlineTextEditor!,
        ],
      ),
    );
  }
}

class _GraphOverlayPainter extends CustomPainter {
  const _GraphOverlayPainter({
    required this.wallSegments,
    required this.annotations,
    required this.shapes,
    required this.freehandStrokes,
    required this.draftFreehandPoints,
    required this.previewShapeSegments,
    required this.previewShape,
    required this.hiddenSegmentIndexes,
    required this.selectedSegmentIndex,
    required this.selectedAnnotationIndex,
    required this.selectedShapeIndex,
    required this.selectedFreehandIndex,
    required this.hoveredSegmentIndex,
    required this.hoveredAnnotationIndex,
    required this.hoveredShapeIndex,
    required this.hoveredFreehandIndex,
    required this.activeWallStart,
    required this.previewSegment,
    required this.treatmentCalloutTip,
    required this.treatmentCalloutBox,
    required this.activeCalloutKind,
    required this.structureVisible,
    required this.shapesVisible,
    required this.inspectionsVisible,
    required this.treatmentVisible,
    required this.photosVisible,
  });

  final List<WallSegment> wallSegments;
  final List<GraphAnnotation> annotations;
  final List<GraphShape> shapes;
  final List<FreehandStroke> freehandStrokes;
  final List<GraphPoint> draftFreehandPoints;
  final List<WallSegment> previewShapeSegments;
  final GraphShape? previewShape;
  final Set<int> hiddenSegmentIndexes;
  final int? selectedSegmentIndex;
  final int? selectedAnnotationIndex;
  final int? selectedShapeIndex;
  final int? selectedFreehandIndex;
  final int? hoveredSegmentIndex;
  final int? hoveredAnnotationIndex;
  final int? hoveredShapeIndex;
  final int? hoveredFreehandIndex;
  final GraphPoint? activeWallStart;
  final WallSegment? previewSegment;
  final GraphPoint? treatmentCalloutTip;
  final Offset? treatmentCalloutBox;
  final _CalloutKind? activeCalloutKind;
  final bool structureVisible;
  final bool shapesVisible;
  final bool inspectionsVisible;
  final bool treatmentVisible;
  final bool photosVisible;

  @override
  void paint(Canvas canvas, Size size) {
    if (shapesVisible) {
      GraphShapesPainter(
        shapes: shapes,
        segments: wallSegments,
        selectedShapeIndex: selectedShapeIndex,
        hoveredShapeIndex: hoveredShapeIndex,
        structureVisible: shapesVisible,
        treatmentVisible: treatmentVisible,
      ).paint(
        canvas,
        size,
      );
    }
    if (structureVisible) {
      WallSegmentsPainter(
        segments: wallSegments,
        selectedSegmentIndex: selectedSegmentIndex,
        hoveredSegmentIndex: hoveredSegmentIndex,
        activeWallStart: activeWallStart,
        previewSegment: previewSegment,
        hiddenSegmentIndexes: hiddenSegmentIndexes,
      ).paint(canvas, size);
      final shapePreview = previewShape;
      if (shapePreview != null && previewShapeSegments.isNotEmpty) {
        GraphShapesPainter(
          shapes: [shapePreview],
          segments: previewShapeSegments,
          selectedShapeIndex: null,
          hoveredShapeIndex: null,
        ).paint(canvas, size);
      }
      FreehandStrokesPainter(
        strokes: freehandStrokes,
        draftPoints: draftFreehandPoints,
        selectedStrokeIndex: selectedFreehandIndex,
        hoveredStrokeIndex: hoveredFreehandIndex,
      ).paint(canvas, size);
    }
    final calloutKind = activeCalloutKind;
    final previewAnnotations = treatmentCalloutTip == null ||
            treatmentCalloutBox == null ||
            calloutKind == null
        ? annotations
        : [
            ...annotations,
            GraphAnnotation(
              kind: calloutKind == _CalloutKind.treatment
                  ? GraphAnnotationKind.marker
                  : GraphAnnotationKind.text,
              point: GraphPoint.fromOffset(treatmentCalloutBox!),
              label: calloutKind == _CalloutKind.treatment
                  ? 'Treatment Note'
                  : 'Callout Box',
              markerType: calloutKind == _CalloutKind.treatment
                  ? GraphMarkerType.treatmentNote
                  : GraphMarkerType.damage,
              textColor: calloutKind == _CalloutKind.treatment
                  ? Colors.black
                  : const Color(0xFFCC2000),
              backgroundColor: calloutKind == _CalloutKind.treatment
                  ? const Color(0xFF245BDB)
                  : const Color(0xFFFFEB00),
              borderColor: Colors.black,
              extraProperties: {
                'calloutTipX': treatmentCalloutTip!.x,
                'calloutTipY': treatmentCalloutTip!.y,
              },
            ),
          ];
    GraphAnnotationsPainter(
      annotations: previewAnnotations,
      selectedAnnotationIndex: selectedAnnotationIndex,
      hoveredAnnotationIndex: hoveredAnnotationIndex,
      inspectionsVisible: inspectionsVisible,
      treatmentVisible: treatmentVisible,
      structureVisible: structureVisible,
      photosVisible: photosVisible,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _GraphOverlayPainter oldDelegate) {
    return oldDelegate.wallSegments != wallSegments ||
        oldDelegate.annotations != annotations ||
        oldDelegate.shapes != shapes ||
        oldDelegate.freehandStrokes != freehandStrokes ||
        oldDelegate.draftFreehandPoints != draftFreehandPoints ||
        oldDelegate.previewShapeSegments != previewShapeSegments ||
        oldDelegate.previewShape != previewShape ||
        oldDelegate.hiddenSegmentIndexes != hiddenSegmentIndexes ||
        oldDelegate.selectedSegmentIndex != selectedSegmentIndex ||
        oldDelegate.selectedAnnotationIndex != selectedAnnotationIndex ||
        oldDelegate.selectedShapeIndex != selectedShapeIndex ||
        oldDelegate.selectedFreehandIndex != selectedFreehandIndex ||
        oldDelegate.hoveredSegmentIndex != hoveredSegmentIndex ||
        oldDelegate.hoveredAnnotationIndex != hoveredAnnotationIndex ||
        oldDelegate.hoveredShapeIndex != hoveredShapeIndex ||
        oldDelegate.hoveredFreehandIndex != hoveredFreehandIndex ||
        oldDelegate.activeWallStart != activeWallStart ||
        oldDelegate.previewSegment != previewSegment ||
        oldDelegate.treatmentCalloutTip != treatmentCalloutTip ||
        oldDelegate.treatmentCalloutBox != treatmentCalloutBox ||
        oldDelegate.activeCalloutKind != activeCalloutKind ||
        oldDelegate.structureVisible != structureVisible ||
        oldDelegate.shapesVisible != shapesVisible ||
        oldDelegate.inspectionsVisible != inspectionsVisible ||
        oldDelegate.treatmentVisible != treatmentVisible ||
        oldDelegate.photosVisible != photosVisible;
  }
}

class _TraceLayer extends StatelessWidget {
  const _TraceLayer({
    required this.traces,
    required this.selectedTraceIndex,
    required this.hoveredTraceIndex,
  });

  final List<TraceGeometry> traces;
  final int? selectedTraceIndex;
  final int? hoveredTraceIndex;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: const Size(double.infinity, double.infinity),
        painter: TraceGeometryPainter(
          traces: traces,
          selectedTraceIndex: selectedTraceIndex,
          hoveredTraceIndex: hoveredTraceIndex,
        ),
      ),
    );
  }
}

enum _UndoKind {
  snapshot,
  wallStart,
  wallSegment,
  annotation,
  freehand,
  textEdit,
  move,
  shapeFinish,
}

enum _SelectionKind {
  annotation,
  segment,
  shape,
  freehand,
  trace,
}

enum _ContextAction {
  copy,
  paste,
  duplicate,
  delete,
  bringForward,
  sendBackward,
  bringToFront,
  sendToBack,
  group,
  ungroup,
  lock,
  unlock,
  properties,
}

enum _ReorderDirection {
  forward,
  backward,
  front,
  back,
}

class _ClipboardItem {
  const _ClipboardItem(this.selection);

  final _Selection selection;
}

enum _GraphLayer {
  structure,
  shapes,
  inspections,
  treatment,
  photos,
  trace,
}

class _LayerSettings {
  const _LayerSettings({
    this.visible = true,
    this.locked = false,
  });

  final bool visible;
  final bool locked;

  _LayerSettings copyWith({
    bool? visible,
    bool? locked,
  }) {
    return _LayerSettings(
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
    );
  }
}

class _MarkerStyleDefaults {
  const _MarkerStyleDefaults({
    required this.color,
    required this.size,
  });

  factory _MarkerStyleDefaults.fromMarkerType(GraphMarkerType markerType) {
    return _MarkerStyleDefaults(
      color: markerType.defaultColor,
      size: utilityMarkerTypes.contains(markerType) ? 1.0 : 1.2,
    );
  }

  final Color color;
  final double size;
}

class _DrawingStyleDefaults {
  const _DrawingStyleDefaults({
    required this.fillColor,
    required this.fillOpacity,
    required this.borderColor,
    required this.borderWidth,
    required this.pattern,
    required this.lineColor,
    required this.lineWidth,
    required this.linePattern,
  });

  factory _DrawingStyleDefaults.fromPreset(GraphDrawingPreset preset) {
    return _DrawingStyleDefaults(
      fillColor: preset.defaultFillColor,
      fillOpacity: preset.defaultFillOpacity,
      borderColor: preset.defaultBorderColor,
      borderWidth: preset.defaultBorderWidth,
      pattern: preset.defaultPattern,
      lineColor: preset.defaultLineColor,
      lineWidth: preset.defaultLineWidth,
      linePattern: _linePatternFromPresetValue(preset.defaultLinePattern),
    );
  }

  final Color? fillColor;
  final double fillOpacity;
  final Color borderColor;
  final double borderWidth;
  final GraphShapePattern pattern;
  final Color lineColor;
  final double lineWidth;
  final LinePattern linePattern;

  _DrawingStyleDefaults copyWith({
    Color? fillColor,
    bool clearFillColor = false,
    double? fillOpacity,
    Color? borderColor,
    double? borderWidth,
    GraphShapePattern? pattern,
    Color? lineColor,
    double? lineWidth,
    LinePattern? linePattern,
  }) {
    return _DrawingStyleDefaults(
      fillColor: clearFillColor ? null : fillColor ?? this.fillColor,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      pattern: pattern ?? this.pattern,
      lineColor: lineColor ?? this.lineColor,
      lineWidth: lineWidth ?? this.lineWidth,
      linePattern: linePattern ?? this.linePattern,
    );
  }
}

LinePattern _linePatternFromPresetValue(LinePatternValue value) {
  return switch (value) {
    LinePatternValue.solid => LinePattern.solid,
    LinePatternValue.dashed => LinePattern.dashed,
    LinePatternValue.xMarks => LinePattern.xMarks,
    LinePatternValue.dottedSmall => LinePattern.dottedSmall,
    LinePatternValue.dottedLarge => LinePattern.dottedLarge,
    LinePatternValue.diamonds => LinePattern.diamonds,
  };
}

class _Selection {
  const _Selection._({
    required this.kind,
    required this.index,
  });

  factory _Selection.annotation(int index) {
    return _Selection._(kind: _SelectionKind.annotation, index: index);
  }

  factory _Selection.segment(int index) {
    return _Selection._(kind: _SelectionKind.segment, index: index);
  }

  factory _Selection.shape(int index) {
    return _Selection._(kind: _SelectionKind.shape, index: index);
  }

  factory _Selection.freehand(int index) {
    return _Selection._(kind: _SelectionKind.freehand, index: index);
  }

  factory _Selection.trace(int index) {
    return _Selection._(kind: _SelectionKind.trace, index: index);
  }

  final _SelectionKind kind;
  final int index;

  int? get annotationIndex => kind == _SelectionKind.annotation ? index : null;

  int? get segmentIndex => kind == _SelectionKind.segment ? index : null;

  int? get shapeIndex => kind == _SelectionKind.shape ? index : null;

  int? get freehandIndex => kind == _SelectionKind.freehand ? index : null;

  int? get traceIndex => kind == _SelectionKind.trace ? index : null;

  @override
  bool operator ==(Object other) =>
      other is _Selection && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.wallSegments,
    required this.annotations,
    required this.shapes,
    required this.freehandStrokes,
    required this.traces,
    required this.measurementCalibration,
    required this.activeWallStart,
    required this.activePathStartPoint,
    required this.pendingCurveControlPoint,
    required this.activePathStartSegmentIndex,
  });

  factory _EditorSnapshot.capture(_GraphCanvasScreenState state) =>
      _EditorSnapshot(
        wallSegments: List<WallSegment>.of(state._wallSegments),
        annotations: List<GraphAnnotation>.of(state._annotations),
        shapes: List<GraphShape>.of(state._shapes),
        freehandStrokes: List<FreehandStroke>.of(state._freehandStrokes),
        traces: List<TraceGeometry>.of(state._traces),
        measurementCalibration: state._document.measurementCalibration,
        activeWallStart: state._activeWallStart,
        activePathStartPoint: state._activePathStartPoint,
        pendingCurveControlPoint: state._pendingCurveControlPoint,
        activePathStartSegmentIndex: state._activePathStartSegmentIndex,
      );

  final List<WallSegment> wallSegments;
  final List<GraphAnnotation> annotations;
  final List<GraphShape> shapes;
  final List<FreehandStroke> freehandStrokes;
  final List<TraceGeometry> traces;
  final MeasurementCalibration measurementCalibration;
  final GraphPoint? activeWallStart;
  final GraphPoint? activePathStartPoint;
  final GraphPoint? pendingCurveControlPoint;
  final int? activePathStartSegmentIndex;

  void restore(_GraphCanvasScreenState state) {
    state._wallSegments = wallSegments;
    state._annotations = annotations;
    state._shapes = shapes;
    state._freehandStrokes = freehandStrokes;
    state._document.replaceTraces(traces);
    state._document.setMeasurementCalibration(measurementCalibration);
    state._activeWallStart = activeWallStart;
    state._activePathStartPoint = activePathStartPoint;
    state._pendingCurveControlPoint = pendingCurveControlPoint;
    state._activePathStartSegmentIndex = activePathStartSegmentIndex;
    state._previewSegment = null;
  }
}

class _RedoEntry {
  const _RedoEntry({required this.snapshot, required this.undoEntry});

  final _EditorSnapshot snapshot;
  final _UndoEntry undoEntry;
}

class _UndoEntry {
  const _UndoEntry(
    this.kind, {
    this.previousSnapshot,
    this.annotationIndex,
    this.previousAnnotation,
    this.previousWallSegments,
    this.previousAnnotations,
    this.previousShapes,
    this.previousFreehandStrokes,
    this.previousTraces,
    this.previousActiveWallStart,
    this.previousActivePathStartPoint,
    this.previousActivePathStartSegmentIndex,
    this.shapeIndex,
    this.addedSegmentCount = 0,
  });

  final _UndoKind kind;
  final _EditorSnapshot? previousSnapshot;
  final int? annotationIndex;
  final GraphAnnotation? previousAnnotation;
  final List<WallSegment>? previousWallSegments;
  final List<GraphAnnotation>? previousAnnotations;
  final List<GraphShape>? previousShapes;
  final List<FreehandStroke>? previousFreehandStrokes;
  final List<TraceGeometry>? previousTraces;
  final GraphPoint? previousActiveWallStart;
  final GraphPoint? previousActivePathStartPoint;
  final int? previousActivePathStartSegmentIndex;
  final int? shapeIndex;
  final int addedSegmentCount;
}

enum _CanvasMessageSeverity { info, success, warning, error }

enum _SidePanelMode { properties, layers }

enum _CalloutKind { annotation, treatment }

enum _PhotoSource { files, camera }

// Item 10 of the production pass: the user's choice when a Save would
// otherwise silently overwrite a graph already saved to Holloman Ops
// Brain.
enum _SaveConflictChoice { overwrite, saveAsNew, cancel }

enum _EditorFileAction {
  saveGraphFile,
  exportPdf,
  exportPng,
  saveAndCreateSalesBrainReport,
  newWithExistingStructure,
}

enum _EditorOptionAction {
  grid,
  snapGrid,
  scale1,
  scale2,
  scale3,
  scale4,
  scale10,
}

enum _DragKind {
  wallEndpoint,
  segment,
  annotation,
  shape,
  shapeResize,
  shapeRotation,
  freehand,
  traceVertex,
  traceMove,
  traceRotation,
}

class _DragTarget {
  const _DragTarget._({
    required this.kind,
    required this.distance,
    this.annotationIndex,
    this.segmentIndex,
    this.shapeIndex,
    this.freehandIndex,
    this.traceIndex,
    this.traceVertexIndex,
    this.traceCenter,
    this.endpointRefs = const <_SegmentEndpointRef>[],
    this.movesActiveWallStart = false,
    this.movesActivePathStart = false,
    this.originalPoint,
    this.shapeCenter,
    this.originalBounds,
    this.resizeHandleIndex = 0,
    this.initialAngleRadians = 0,
    this.originalRotationDegrees = 0,
    this.selection,
  });

  factory _DragTarget.annotation({
    required int annotationIndex,
    required double distance,
  }) {
    return _DragTarget._(
      kind: _DragKind.annotation,
      annotationIndex: annotationIndex,
      distance: distance,
      selection: _Selection.annotation(annotationIndex),
    );
  }

  factory _DragTarget.segment({
    required int segmentIndex,
    required double distance,
    required GraphPoint originalPoint,
  }) {
    return _DragTarget._(
      kind: _DragKind.segment,
      segmentIndex: segmentIndex,
      distance: distance,
      originalPoint: originalPoint,
      selection: _Selection.segment(segmentIndex),
    );
  }

  factory _DragTarget.wallEndpoint({
    required List<_SegmentEndpointRef> endpointRefs,
    required bool movesActiveWallStart,
    required bool movesActivePathStart,
    required GraphPoint originalPoint,
    required double distance,
  }) {
    return _DragTarget._(
      kind: _DragKind.wallEndpoint,
      endpointRefs: endpointRefs,
      movesActiveWallStart: movesActiveWallStart,
      movesActivePathStart: movesActivePathStart,
      originalPoint: originalPoint,
      distance: distance,
      selection: endpointRefs.isEmpty
          ? null
          : _Selection.segment(endpointRefs.first.segmentIndex),
    );
  }

  factory _DragTarget.shape({
    required int shapeIndex,
    required double distance,
    required GraphPoint originalPoint,
  }) {
    return _DragTarget._(
      kind: _DragKind.shape,
      shapeIndex: shapeIndex,
      distance: distance,
      originalPoint: originalPoint,
      selection: _Selection.shape(shapeIndex),
    );
  }

  factory _DragTarget.shapeResize({
    required int shapeIndex,
    required double distance,
    required GraphPoint originalPoint,
    required Rect originalBounds,
    required int resizeHandleIndex,
  }) {
    return _DragTarget._(
      kind: _DragKind.shapeResize,
      shapeIndex: shapeIndex,
      distance: distance,
      originalPoint: originalPoint,
      originalBounds: originalBounds,
      resizeHandleIndex: resizeHandleIndex,
      selection: _Selection.shape(shapeIndex),
    );
  }

  factory _DragTarget.shapeRotation({
    required int shapeIndex,
    required double distance,
    required GraphPoint originalPoint,
    required GraphPoint shapeCenter,
    required double initialAngleRadians,
    required double originalRotationDegrees,
  }) {
    return _DragTarget._(
      kind: _DragKind.shapeRotation,
      shapeIndex: shapeIndex,
      distance: distance,
      originalPoint: originalPoint,
      shapeCenter: shapeCenter,
      initialAngleRadians: initialAngleRadians,
      originalRotationDegrees: originalRotationDegrees,
      selection: _Selection.shape(shapeIndex),
    );
  }

  factory _DragTarget.freehand({
    required int freehandIndex,
    required double distance,
    required GraphPoint originalPoint,
  }) {
    return _DragTarget._(
      kind: _DragKind.freehand,
      freehandIndex: freehandIndex,
      distance: distance,
      originalPoint: originalPoint,
      selection: _Selection.freehand(freehandIndex),
    );
  }

  factory _DragTarget.traceVertex({
    required int traceIndex,
    required int traceVertexIndex,
    required GraphPoint originalPoint,
    required double distance,
  }) {
    return _DragTarget._(
      kind: _DragKind.traceVertex,
      traceIndex: traceIndex,
      traceVertexIndex: traceVertexIndex,
      originalPoint: originalPoint,
      distance: distance,
      selection: _Selection.trace(traceIndex),
    );
  }

  factory _DragTarget.traceMove({
    required int traceIndex,
    required GraphPoint originalPoint,
  }) {
    return _DragTarget._(
      kind: _DragKind.traceMove,
      traceIndex: traceIndex,
      distance: 0,
      originalPoint: originalPoint,
      selection: _Selection.trace(traceIndex),
    );
  }

  factory _DragTarget.traceRotation({
    required int traceIndex,
    required double distance,
    required GraphPoint originalPoint,
    required GraphPoint traceCenter,
    required double initialAngleRadians,
  }) {
    return _DragTarget._(
      kind: _DragKind.traceRotation,
      traceIndex: traceIndex,
      distance: distance,
      originalPoint: originalPoint,
      traceCenter: traceCenter,
      initialAngleRadians: initialAngleRadians,
      selection: _Selection.trace(traceIndex),
    );
  }

  final _DragKind kind;
  final double distance;
  final int? annotationIndex;
  final int? segmentIndex;
  final int? shapeIndex;
  final int? freehandIndex;
  final int? traceIndex;
  final int? traceVertexIndex;
  final GraphPoint? traceCenter;
  final List<_SegmentEndpointRef> endpointRefs;
  final bool movesActiveWallStart;
  final bool movesActivePathStart;
  final GraphPoint? originalPoint;
  final GraphPoint? shapeCenter;
  final Rect? originalBounds;
  final int resizeHandleIndex;
  final double initialAngleRadians;
  final double originalRotationDegrees;
  final _Selection? selection;
}

class _SegmentEndpointRef {
  const _SegmentEndpointRef({
    required this.segmentIndex,
    required this.isStart,
  });

  final int segmentIndex;
  final bool isStart;
}

class _TextLabelDialog extends StatefulWidget {
  const _TextLabelDialog({
    required this.title,
    required this.initialText,
  });

  final String title;
  final String initialText;

  @override
  State<_TextLabelDialog> createState() => _TextLabelDialogState();
}

class _TextLabelDialogState extends State<_TextLabelDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Label',
          border: OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _FinishShapeResult {
  const _FinishShapeResult({
    required this.name,
    required this.closeShape,
    required this.fillColor,
    required this.fillOpacity,
    required this.borderColor,
    required this.borderWidth,
    required this.pattern,
  });

  final String name;
  final bool closeShape;
  final Color? fillColor;
  final double fillOpacity;
  final Color borderColor;
  final double borderWidth;
  final GraphShapePattern pattern;
}

enum _ShapeFillChoice {
  none('None', null, 0),
  noteYellow('Note yellow', Color(0xFFFFF2B8), 0.85),
  lime('Lime', Color(0xFFB6D94C), 0.34),
  teal('Teal', Color(0xFF24A69A), 0.32),
  blue('Blue', Color(0xFF3D7CFF), 0.30),
  violet('Violet', Color(0xFF8E5CF7), 0.30),
  amber('Amber', Color(0xFFFFB52E), 0.36),
  red('Red', Color(0xFFFF5A47), 0.30);

  const _ShapeFillChoice(this.label, this.color, this.opacity);

  final String label;
  final Color? color;
  final double opacity;
}

enum _ShapeBorderChoice {
  darkGreen('Dark green', Color(0xFF214D38)),
  black('Black', Color(0xFF1C2B22)),
  blue('Blue', Color(0xFF245BDB)),
  violet('Violet', Color(0xFF7048D8)),
  orange('Orange', Color(0xFFD1721E)),
  red('Red', Color(0xFFD33A2C));

  const _ShapeBorderChoice(this.label, this.color);

  final String label;
  final Color color;
}

enum _MarkerColorChoice {
  red('Red', Color(0xFFD33A2C)),
  orange('Orange', Color(0xFFE5792A)),
  yellow('Yellow', Color(0xFFE0AD19)),
  green('Green', Color(0xFF2E7D55)),
  teal('Teal', Color(0xFF168AAD)),
  blue('Blue', Color(0xFF245BDB)),
  purple('Purple', Color(0xFF7048D8)),
  black('Black', Color(0xFF1C2B22));

  const _MarkerColorChoice(this.label, this.color);

  final String label;
  final Color color;
}

String _patternLabel(GraphShapePattern pattern) {
  return switch (pattern) {
    GraphShapePattern.none => 'None',
    GraphShapePattern.diagonal => 'Diagonal',
    GraphShapePattern.reverseDiagonal => 'Reverse diagonal',
    GraphShapePattern.crossHatch => 'Cross hatch',
    GraphShapePattern.horizontal => 'Horizontal',
    GraphShapePattern.vertical => 'Vertical',
    GraphShapePattern.grid => 'Grid',
    GraphShapePattern.dots => 'Dots',
    GraphShapePattern.largeDots => 'Large dots',
    GraphShapePattern.checker => 'Checker',
  };
}
