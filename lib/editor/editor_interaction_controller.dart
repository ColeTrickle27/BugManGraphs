import 'package:flutter/material.dart';

import '../models/graph_annotation.dart';
import '../models/graph_shape.dart';

enum CanvasTool {
  select(Icons.navigation, 'Select', 'V'),
  pan(Icons.pan_tool_outlined, 'Pan', 'H'),
  structure(Icons.account_tree_outlined, 'Draw Structure', 'B'),
  rectangle(Icons.crop_square, 'Rectangle', 'R'),
  square(Icons.check_box_outline_blank, 'Square', 'S'),
  circle(Icons.circle_outlined, 'Circle', 'C'),
  ellipse(Icons.radio_button_unchecked, 'Ellipse', 'E'),
  triangle(Icons.change_history, 'Triangle', 'G'),
  wall(Icons.polyline_outlined, 'Line', 'L'),
  arrow(Icons.arrow_forward, 'Arrow', 'A'),
  curve(Icons.timeline, 'Curve', 'U'),
  freehand(Icons.gesture, 'Freehand', 'F'),
  callout(Icons.add_comment_outlined, 'Callout Box', ''),
  marker(Icons.place_outlined, 'Marker', 'M'),
  photo(Icons.add_a_photo_outlined, 'Photo', ''),
  text(Icons.note_add_outlined, '+Note', 'T');

  const CanvasTool(this.icon, this.label, this.shortcut);

  final IconData icon;
  final String label;
  final String shortcut;
}

enum EditorDrawingSession {
  idle,
  plottingStructure,
  creatingShape,
  drawingLine,
  drawingFreehand,
  movingObject,
  editingText,
}

enum EditorObjectKind {
  annotation,
  shape,
  freehand,
  segment,
  trace,
}

@immutable
class EditorObjectReference {
  const EditorObjectReference(this.kind, this.index);

  final EditorObjectKind kind;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is EditorObjectReference &&
      other.kind == kind &&
      other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);
}

/// Authoritative UI-only interaction state for the graph editor.
///
/// Saved graph objects remain owned by [GraphDocument]. This controller owns
/// only the technician's current intent and pointer session so the toolbar,
/// canvas, cursor, and keyboard handling cannot disagree about the active mode.
class EditorInteractionController extends ChangeNotifier {
  CanvasTool _primaryTool = CanvasTool.structure;
  GraphDrawingPreset _structureType = GraphDrawingPreset.mainStructure;
  GraphMarkerType _markerType = GraphMarkerType.mudTube;
  EditorDrawingSession _drawingSession = EditorDrawingSession.idle;
  EditorObjectReference? _selectedObject;
  EditorObjectReference? _hoveredObject;
  Offset? _pointerDownScene;
  bool _dragging = false;
  bool _pickerOpen = false;
  bool _textEditing = false;

  CanvasTool get primaryTool => _primaryTool;
  GraphDrawingPreset get structureType => _structureType;
  GraphMarkerType get markerType => _markerType;
  EditorDrawingSession get drawingSession => _drawingSession;
  EditorObjectReference? get selectedObject => _selectedObject;
  EditorObjectReference? get hoveredObject => _hoveredObject;
  Offset? get pointerDownScene => _pointerDownScene;
  bool get dragging => _dragging;
  bool get pickerOpen => _pickerOpen;
  bool get textEditing => _textEditing;
  bool get shouldInterceptKeyboard => !_pickerOpen;

  void selectTool(CanvasTool value) {
    _primaryTool = value;
    _drawingSession = EditorDrawingSession.idle;
    notifyListeners();
  }

  void selectStructure(GraphDrawingPreset value) {
    _structureType = value;
    _primaryTool = CanvasTool.structure;
    _drawingSession = EditorDrawingSession.idle;
    notifyListeners();
  }

  void selectMarker(GraphMarkerType value) {
    _markerType = value;
    _primaryTool = CanvasTool.marker;
    _drawingSession = EditorDrawingSession.idle;
    notifyListeners();
  }

  void setDrawingSession(EditorDrawingSession value) {
    if (_drawingSession == value) return;
    _drawingSession = value;
    notifyListeners();
  }

  void setSelected(EditorObjectReference? value) {
    if (_selectedObject == value) return;
    _selectedObject = value;
    notifyListeners();
  }

  void setHovered(EditorObjectReference? value) {
    if (_hoveredObject == value) return;
    _hoveredObject = value;
    notifyListeners();
  }

  void pointerDown(Offset scenePosition) {
    _pointerDownScene = scenePosition;
    _dragging = false;
    notifyListeners();
  }

  void beginDrag() {
    if (_dragging) return;
    _dragging = true;
    notifyListeners();
  }

  void pointerUp() {
    _pointerDownScene = null;
    _dragging = false;
    notifyListeners();
  }

  void setPickerOpen(bool value) {
    if (_pickerOpen == value) return;
    _pickerOpen = value;
    notifyListeners();
  }

  void setTextEditing(bool value) {
    if (_textEditing == value) return;
    _textEditing = value;
    _drawingSession =
        value ? EditorDrawingSession.editingText : EditorDrawingSession.idle;
    notifyListeners();
  }
}
