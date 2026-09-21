import 'package:flutter/material.dart';

import '../editor/editor_interaction_controller.dart';
import '../models/graph_annotation.dart';
import '../models/graph_marker_catalog.dart';
import '../models/graph_shape.dart';
import 'graph_marker_visual.dart';

enum CanvasToolbarActionKind { tool, preset, marker }

@immutable
class CanvasToolbarAction {
  const CanvasToolbarAction.tool(this.tool)
      : kind = CanvasToolbarActionKind.tool,
        preset = null,
        marker = null;

  const CanvasToolbarAction.preset(this.preset)
      : kind = CanvasToolbarActionKind.preset,
        tool = null,
        marker = null;

  const CanvasToolbarAction.marker(this.marker)
      : kind = CanvasToolbarActionKind.marker,
        tool = null,
        preset = null;

  final CanvasToolbarActionKind kind;
  final CanvasTool? tool;
  final GraphDrawingPreset? preset;
  final GraphMarkerType? marker;

  String get label => switch (kind) {
        CanvasToolbarActionKind.tool => tool!.label,
        CanvasToolbarActionKind.preset =>
          preset == GraphDrawingPreset.propertyLine
              ? 'Property Line (acres)'
              : preset!.label,
        CanvasToolbarActionKind.marker => marker!.label,
      };

  String get shortLabel => switch (kind) {
        CanvasToolbarActionKind.tool => tool!.label,
        CanvasToolbarActionKind.preset => preset!.shortLabel,
        CanvasToolbarActionKind.marker => marker!.shortLabel,
      };

  String get shortcut => tool?.shortcut ?? '';

  IconData get icon => switch (kind) {
        CanvasToolbarActionKind.tool => tool!.icon,
        CanvasToolbarActionKind.preset => iconForDrawingPreset(preset!),
        CanvasToolbarActionKind.marker => iconForGraphMarker(marker!),
      };

  Color get color => switch (kind) {
        CanvasToolbarActionKind.tool => const Color(0xFFCC2000),
        CanvasToolbarActionKind.preset => preset!.defaultBorderColor,
        CanvasToolbarActionKind.marker => marker!.defaultColor,
      };

  String get tooltip => shortcut.isEmpty ? label : '$label ($shortcut)';

  bool isSelected({
    required CanvasTool selectedTool,
    required GraphDrawingPreset? selectedPreset,
    required GraphMarkerType selectedMarker,
  }) =>
      switch (kind) {
        CanvasToolbarActionKind.tool => selectedTool == tool,
        CanvasToolbarActionKind.preset =>
          selectedTool == CanvasTool.structure && selectedPreset == preset,
        CanvasToolbarActionKind.marker =>
          selectedTool == CanvasTool.marker && selectedMarker == marker,
      };

  @override
  bool operator ==(Object other) =>
      other is CanvasToolbarAction &&
      other.kind == kind &&
      other.tool == tool &&
      other.preset == preset &&
      other.marker == marker;

  @override
  int get hashCode => Object.hash(kind, tool, preset, marker);
}

const basicLineToolbarActions = <CanvasToolbarAction>[
  CanvasToolbarAction.tool(CanvasTool.callout),
  CanvasToolbarAction.tool(CanvasTool.text),
  CanvasToolbarAction.tool(CanvasTool.arrow),
  CanvasToolbarAction.tool(CanvasTool.freehand),
];

const basicShapeToolbarActions = <CanvasToolbarAction>[
  CanvasToolbarAction.tool(CanvasTool.rectangle),
  CanvasToolbarAction.tool(CanvasTool.circle),
  CanvasToolbarAction.tool(CanvasTool.triangle),
  CanvasToolbarAction.tool(CanvasTool.wall),
];

const buildingFeatureToolbarActions = <CanvasToolbarAction>[
  CanvasToolbarAction.preset(GraphDrawingPreset.slab),
  CanvasToolbarAction.preset(GraphDrawingPreset.woodDeck),
  CanvasToolbarAction.preset(GraphDrawingPreset.woodPorch),
  CanvasToolbarAction.preset(GraphDrawingPreset.openPorch),
  CanvasToolbarAction.preset(GraphDrawingPreset.dirtFilledPorch),
  CanvasToolbarAction.preset(GraphDrawingPreset.garage),
  CanvasToolbarAction.preset(GraphDrawingPreset.detachedStructure),
];

const propertyToolbarActions = <CanvasToolbarAction>[
  CanvasToolbarAction.preset(GraphDrawingPreset.driveway),
  CanvasToolbarAction.preset(GraphDrawingPreset.walkway),
  CanvasToolbarAction.preset(GraphDrawingPreset.propertyLine),
];

const utilityToolbarActions = <CanvasToolbarAction>[
  CanvasToolbarAction.marker(GraphMarkerType.hvacUnit),
  CanvasToolbarAction.marker(GraphMarkerType.pier),
  CanvasToolbarAction.marker(GraphMarkerType.steps),
  CanvasToolbarAction.marker(GraphMarkerType.crawlspaceAccess),
  CanvasToolbarAction.marker(GraphMarkerType.gasLine),
  CanvasToolbarAction.marker(GraphMarkerType.waterLine),
  CanvasToolbarAction.marker(GraphMarkerType.bushPlant),
];

@visibleForTesting
List<GraphMarkerType> get availableInspectionMarkers => inspectionMarkerTypes;

@visibleForTesting
List<GraphMarkerType> get availableTreatmentMarkers => treatmentMarkerTypes;

@visibleForTesting
List<GraphDrawingPreset> get structureToolbarPresets => [
      GraphDrawingPreset.mainStructure,
      ...buildingFeatureToolbarActions.map((action) => action.preset!),
    ];

@visibleForTesting
List<GraphDrawingPreset> get drawingToolbarPresets => const [];

@visibleForTesting
List<GraphMarkerType> get utilityToolbarMarkers =>
    utilityToolbarActions.map((action) => action.marker!).toList();

class CanvasToolbar extends StatefulWidget {
  const CanvasToolbar({
    required this.selectedTool,
    required this.selectedMarkerType,
    required this.selectedDrawingPreset,
    required this.onToolSelected,
    required this.onMarkerSelected,
    required this.onDrawingPresetSelected,
    required this.traceLayerVisible,
    required this.onToggleTraceLayer,
    required this.onCollapse,
    required this.onActionDoubleTapped,
    super.key,
  });

  final CanvasTool selectedTool;
  final GraphMarkerType selectedMarkerType;
  final GraphDrawingPreset? selectedDrawingPreset;
  final ValueChanged<CanvasTool> onToolSelected;
  final ValueChanged<GraphMarkerType> onMarkerSelected;
  final ValueChanged<GraphDrawingPreset> onDrawingPresetSelected;
  final bool traceLayerVisible;
  final VoidCallback onToggleTraceLayer;
  final VoidCallback onCollapse;
  final ValueChanged<CanvasToolbarAction> onActionDoubleTapped;

  @override
  State<CanvasToolbar> createState() => _CanvasToolbarState();
}

class _CanvasToolbarState extends State<CanvasToolbar> {
  String? _expandedSection = 'Annotate';

  void _activate(CanvasToolbarAction action) {
    switch (action.kind) {
      case CanvasToolbarActionKind.tool:
        widget.onToolSelected(action.tool!);
      case CanvasToolbarActionKind.preset:
        widget.onDrawingPresetSelected(action.preset!);
      case CanvasToolbarActionKind.marker:
        widget.onMarkerSelected(action.marker!);
    }
  }

  CanvasToolbarAction _displayedAction(
    List<CanvasToolbarAction> actions,
  ) {
    for (final action in actions) {
      if (action.isSelected(
        selectedTool: widget.selectedTool,
        selectedPreset: widget.selectedDrawingPreset,
        selectedMarker: widget.selectedMarkerType,
      )) {
        return action;
      }
    }
    return actions.first;
  }

  void _toggleSection(String label) => setState(() {
        _expandedSection = _expandedSection == label ? null : label;
      });

  Widget _section({
    required String label,
    required IconData icon,
    required List<Widget> children,
  }) =>
      _CollapsibleToolbarSection(
        label: label,
        icon: icon,
        expanded: _expandedSection == label,
        onToggle: () => _toggleSection(label),
        children: children,
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: SizedBox(
        width: 112,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            child: Column(
              children: [
                _ToolbarHeader(onCollapse: widget.onCollapse),
                const SizedBox(height: 4),
                KeyedSubtree(
                  key: const ValueKey('draw-structure-tool'),
                  child: _ActionFace(
                    action: const CanvasToolbarAction.preset(
                      GraphDrawingPreset.mainStructure,
                    ),
                    selected: const CanvasToolbarAction.preset(
                      GraphDrawingPreset.mainStructure,
                    ).isSelected(
                      selectedTool: widget.selectedTool,
                      selectedPreset: widget.selectedDrawingPreset,
                      selectedMarker: widget.selectedMarkerType,
                    ),
                    onPressed: () => _activate(
                      const CanvasToolbarAction.preset(
                        GraphDrawingPreset.mainStructure,
                      ),
                    ),
                    onDoubleTap: () => widget.onActionDoubleTapped(
                      const CanvasToolbarAction.preset(
                        GraphDrawingPreset.mainStructure,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 18),
                _section(
                  label: 'Annotate',
                  icon: Icons.edit_note_outlined,
                  children: [
                    _ActionPicker(
                      groupLabel: 'Callouts & Sketch',
                      displayedAction:
                          _displayedAction(basicLineToolbarActions),
                      actions: basicLineToolbarActions,
                      selectedTool: widget.selectedTool,
                      selectedPreset: widget.selectedDrawingPreset,
                      selectedMarker: widget.selectedMarkerType,
                      onSelected: _activate,
                    ),
                    const SizedBox(height: 6),
                    _ActionPicker(
                      groupLabel: 'Basic Shapes',
                      displayedAction:
                          _displayedAction(basicShapeToolbarActions),
                      actions: basicShapeToolbarActions,
                      selectedTool: widget.selectedTool,
                      selectedPreset: widget.selectedDrawingPreset,
                      selectedMarker: widget.selectedMarkerType,
                      onSelected: _activate,
                    ),
                  ],
                ),
                _section(
                  label: 'Sketch Structure',
                  icon: Icons.home_work_outlined,
                  children: [
                    _ActionButton(
                      action: const CanvasToolbarAction.preset(
                        GraphDrawingPreset.mainStructure,
                      ),
                      selectedTool: widget.selectedTool,
                      selectedPreset: widget.selectedDrawingPreset,
                      selectedMarker: widget.selectedMarkerType,
                      onPressed: _activate,
                      onDoubleTap: () => widget.onActionDoubleTapped(
                        const CanvasToolbarAction.preset(
                          GraphDrawingPreset.mainStructure,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _ActionPicker(
                      groupLabel: 'Other Structures',
                      displayedAction:
                          _displayedAction(buildingFeatureToolbarActions),
                      actions: buildingFeatureToolbarActions,
                      selectedTool: widget.selectedTool,
                      selectedPreset: widget.selectedDrawingPreset,
                      selectedMarker: widget.selectedMarkerType,
                      onSelected: _activate,
                    ),
                    const SizedBox(height: 6),
                    _ActionPicker(
                      groupLabel: 'Miscellaneous Structures',
                      displayedAction: _displayedAction(utilityToolbarActions),
                      actions: utilityToolbarActions,
                      selectedTool: widget.selectedTool,
                      selectedPreset: widget.selectedDrawingPreset,
                      selectedMarker: widget.selectedMarkerType,
                      onSelected: _activate,
                    ),
                  ],
                ),
                _section(
                  label: 'Inspection Findings',
                  icon: Icons.search_outlined,
                  children: [
                    for (final marker in const [
                      GraphMarkerType.moisture,
                      GraphMarkerType.termiteActivity,
                    ]) ...[
                      _ActionButton(
                        action: CanvasToolbarAction.marker(marker),
                        selectedTool: widget.selectedTool,
                        selectedPreset: widget.selectedDrawingPreset,
                        selectedMarker: widget.selectedMarkerType,
                        onPressed: _activate,
                        onDoubleTap: () => widget.onActionDoubleTapped(
                          CanvasToolbarAction.marker(marker),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    for (final action in const [
                      CanvasToolbarAction.tool(CanvasTool.photo)
                    ]) ...[
                      _ActionButton(
                        action: action,
                        selectedTool: widget.selectedTool,
                        selectedPreset: widget.selectedDrawingPreset,
                        selectedMarker: widget.selectedMarkerType,
                        onPressed: _activate,
                        onDoubleTap: () => widget.onActionDoubleTapped(action),
                      ),
                      const SizedBox(height: 6),
                    ],
                    _MarkerPickerButton(
                      tooltipLabel: 'More Inspection Markers',
                      displayLabel: 'More findings',
                      selectedMarker: widget.selectedMarkerType,
                      active: widget.selectedTool == CanvasTool.marker &&
                          inspectionMarkerTypes
                              .skip(2)
                              .contains(widget.selectedMarkerType),
                      markers: inspectionMarkerTypes.skip(2).toList(),
                      onSelected: widget.onMarkerSelected,
                    ),
                  ],
                ),
                _section(
                  label: 'Treatment Details',
                  icon: Icons.medical_services_outlined,
                  children: [
                    _ActionButton(
                      action: const CanvasToolbarAction.marker(
                        GraphMarkerType.treatmentNote,
                      ),
                      selectedTool: widget.selectedTool,
                      selectedPreset: widget.selectedDrawingPreset,
                      selectedMarker: widget.selectedMarkerType,
                      onPressed: _activate,
                      onDoubleTap: () => widget.onActionDoubleTapped(
                        const CanvasToolbarAction.marker(
                          GraphMarkerType.treatmentNote,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _MarkerPickerButton(
                      tooltipLabel: 'Treatment Marker',
                      displayLabel: 'More treatment',
                      selectedMarker: widget.selectedMarkerType,
                      active: widget.selectedTool == CanvasTool.marker &&
                          treatmentMarkerTypes
                              .where((marker) =>
                                  marker != GraphMarkerType.treatmentNote)
                              .contains(widget.selectedMarkerType),
                      markers: treatmentMarkerTypes
                          .where((marker) =>
                              marker != GraphMarkerType.treatmentNote)
                          .toList(),
                      onSelected: widget.onMarkerSelected,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Divider(height: 18),
                _PlainToolButton(
                  icon: Icons.satellite_alt_outlined,
                  label: 'Satellite',
                  selected: widget.traceLayerVisible,
                  onPressed: widget.onToggleTraceLayer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CanvasQuickToolbar extends StatelessWidget {
  const CanvasQuickToolbar({
    required this.actions,
    required this.selectedTool,
    required this.selectedMarkerType,
    required this.selectedDrawingPreset,
    required this.onActionSelected,
    required this.onActionAdded,
    required this.onReset,
    required this.onCollapse,
    required this.onToggleProperties,
    required this.onToggleLayers,
    required this.onDeleteSelection,
    required this.onUndo,
    required this.onRedo,
    required this.propertiesSelected,
    required this.layersSelected,
    super.key,
  });

  final List<CanvasToolbarAction> actions;
  final CanvasTool selectedTool;
  final GraphMarkerType selectedMarkerType;
  final GraphDrawingPreset? selectedDrawingPreset;
  final ValueChanged<CanvasToolbarAction> onActionSelected;
  final ValueChanged<CanvasToolbarAction> onActionAdded;
  final VoidCallback onReset;
  final VoidCallback onCollapse;
  final VoidCallback onToggleProperties;
  final VoidCallback onToggleLayers;
  final VoidCallback onDeleteSelection;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool propertiesSelected;
  final bool layersSelected;

  @override
  Widget build(BuildContext context) {
    return DragTarget<CanvasToolbarAction>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onActionAdded(details.data),
      builder: (context, candidates, rejected) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1120;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Material(
              key: const ValueKey('canvas-quick-toolbar'),
              elevation: 10,
              color:
                  candidates.isEmpty ? Colors.white : const Color(0xFFFFE7E2),
              shape: StadiumBorder(
                side: BorderSide(
                  color: candidates.isEmpty
                      ? const Color(0xFF6D6E71)
                      : const Color(0xFFCC2000),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Hide quick toolbar',
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: onCollapse,
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                    const SizedBox(height: 34, child: VerticalDivider()),
                    for (final action in actions)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _QuickActionButton(
                          action: action,
                          compact: compact,
                          selected: action.isSelected(
                            selectedTool: selectedTool,
                            selectedPreset: selectedDrawingPreset,
                            selectedMarker: selectedMarkerType,
                          ),
                          onPressed: () => onActionSelected(action),
                        ),
                      ),
                    const SizedBox(height: 34, child: VerticalDivider()),
                    _QuickUtilityButton(
                      icon: Icons.undo,
                      tooltip: 'Quick undo',
                      selected: false,
                      onPressed: onUndo,
                    ),
                    _QuickUtilityButton(
                      icon: Icons.redo,
                      tooltip: 'Quick redo',
                      selected: false,
                      onPressed: onRedo,
                    ),
                    const SizedBox(height: 34, child: VerticalDivider()),
                    _QuickUtilityButton(
                      icon: Icons.tune,
                      tooltip: 'Properties panel',
                      selected: propertiesSelected,
                      onPressed: onToggleProperties,
                    ),
                    _QuickUtilityButton(
                      icon: Icons.layers_outlined,
                      tooltip: 'Layers panel',
                      selected: layersSelected,
                      onPressed: onToggleLayers,
                    ),
                    _QuickUtilityButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete selection',
                      selected: false,
                      onPressed: onDeleteSelection,
                    ),
                    if (actions.length > 2) ...[
                      const SizedBox(height: 34, child: VerticalDivider()),
                      IconButton(
                        tooltip: 'Reset quick toolbar',
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 34,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: onReset,
                        icon: const Icon(Icons.restart_alt),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActionPicker extends StatelessWidget {
  const _ActionPicker({
    required this.groupLabel,
    required this.displayedAction,
    required this.actions,
    required this.selectedTool,
    required this.selectedPreset,
    required this.selectedMarker,
    required this.onSelected,
  });

  final String groupLabel;
  final CanvasToolbarAction displayedAction;
  final List<CanvasToolbarAction> actions;
  final CanvasTool selectedTool;
  final GraphDrawingPreset? selectedPreset;
  final GraphMarkerType selectedMarker;
  final ValueChanged<CanvasToolbarAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = displayedAction.isSelected(
      selectedTool: selectedTool,
      selectedPreset: selectedPreset,
      selectedMarker: selectedMarker,
    );
    final picker = SizedBox(
      width: 88,
      height: 54,
      child: PopupMenuButton<CanvasToolbarAction>(
        tooltip: '$groupLabel: ${displayedAction.tooltip}',
        onSelected: onSelected,
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 340),
        itemBuilder: (context) => [
          for (final action in actions)
            PopupMenuItem(
              value: action,
              child: Row(
                children: [
                  Icon(action.icon, color: action.color, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text(action.label)),
                  if (action.isSelected(
                    selectedTool: selectedTool,
                    selectedPreset: selectedPreset,
                    selectedMarker: selectedMarker,
                  ))
                    const Icon(Icons.check, size: 20),
                ],
              ),
            ),
        ],
        child: _PickerFace(
          icon: displayedAction.icon,
          label: groupLabel,
          color: displayedAction.color,
          active: selected,
          showMenuIndicator: true,
        ),
      ),
    );
    return _DraggableAction(action: displayedAction, child: picker);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.selectedTool,
    required this.selectedPreset,
    required this.selectedMarker,
    required this.onPressed,
    this.onDoubleTap,
  });

  final CanvasToolbarAction action;
  final CanvasTool selectedTool;
  final GraphDrawingPreset? selectedPreset;
  final GraphMarkerType selectedMarker;
  final ValueChanged<CanvasToolbarAction> onPressed;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final child = _ActionFace(
      action: action,
      selected: action.isSelected(
        selectedTool: selectedTool,
        selectedPreset: selectedPreset,
        selectedMarker: selectedMarker,
      ),
      onPressed: () => onPressed(action),
      onDoubleTap: onDoubleTap,
    );
    return _DraggableAction(action: action, child: child);
  }
}

class _DraggableAction extends StatelessWidget {
  const _DraggableAction({
    required this.action,
    required this.child,
  });

  final CanvasToolbarAction action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<CanvasToolbarAction>(
      data: action,
      delay: const Duration(milliseconds: 350),
      maxSimultaneousDrags: 1,
      feedback: Material(
        color: Colors.transparent,
        child: _DragFeedback(action: action),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }
}

class _QuickUtilityButton extends StatelessWidget {
  const _QuickUtilityButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: IconButton(
          constraints: const BoxConstraints.tightFor(width: 38, height: 34),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          color: selected ? const Color(0xFFCC2000) : Colors.black87,
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
        ),
      );
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.action});
  final CanvasToolbarAction action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCC2000), width: 2),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, color: action.color),
            const SizedBox(width: 8),
            Text(action.label),
          ],
        ),
      );
}

class _ActionFace extends StatelessWidget {
  const _ActionFace({
    required this.action,
    required this.selected,
    required this.onPressed,
    this.onDoubleTap,
  });

  final CanvasToolbarAction action;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 88,
        height: 54,
        child: Tooltip(
          message: '${action.tooltip}\nHold and drag to customize quick tools',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            onDoubleTap: onDoubleTap,
            child: _PickerFace(
              icon: action.icon,
              label: action.shortLabel,
              color: action.color,
              active: selected,
            ),
          ),
        ),
      );
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.action,
    required this.compact,
    required this.selected,
    required this.onPressed,
  });

  final CanvasToolbarAction action;
  final bool compact;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: action.tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: BoxConstraints(minWidth: compact ? 36 : 58),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 7 : 10,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFCC2000) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  action.icon,
                  size: 20,
                  color: selected ? Colors.white : action.color,
                ),
                if (!compact &&
                    action.tool != CanvasTool.select &&
                    action.tool != CanvasTool.pan) ...[
                  const SizedBox(width: 5),
                  Text(
                    action.label,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class _MarkerPickerButton extends StatelessWidget {
  const _MarkerPickerButton({
    required this.tooltipLabel,
    required this.displayLabel,
    required this.selectedMarker,
    required this.active,
    required this.markers,
    required this.onSelected,
  });

  final String tooltipLabel;
  final String displayLabel;
  final GraphMarkerType selectedMarker;
  final bool active;
  final List<GraphMarkerType> markers;
  final ValueChanged<GraphMarkerType> onSelected;

  @override
  Widget build(BuildContext context) {
    final displayedMarker =
        markers.contains(selectedMarker) ? selectedMarker : markers.first;
    final action = CanvasToolbarAction.marker(displayedMarker);
    final picker = SizedBox(
      width: 88,
      height: 54,
      child: PopupMenuButton<GraphMarkerType>(
        tooltip: '$tooltipLabel: ${displayedMarker.label}',
        onSelected: onSelected,
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 360),
        itemBuilder: (context) => [
          for (final marker in markers)
            PopupMenuItem(
              value: marker,
              child: Row(
                children: [
                  Icon(
                    iconForGraphMarker(marker),
                    color: marker.defaultColor,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(marker.label)),
                  if (marker == selectedMarker)
                    const Icon(Icons.check, size: 20),
                ],
              ),
            ),
        ],
        child: _PickerFace(
          icon: iconForGraphMarker(displayedMarker),
          label: displayLabel,
          color: displayedMarker.defaultColor,
          active: active && displayedMarker == selectedMarker,
          showMenuIndicator: true,
        ),
      ),
    );
    return _DraggableAction(action: action, child: picker);
  }
}

class _PickerFace extends StatelessWidget {
  const _PickerFace({
    required this.icon,
    required this.label,
    required this.color,
    required this.active,
    this.showMenuIndicator = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final bool showMenuIndicator;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.16) : Colors.white,
          border: Border.all(
            color: active ? color : const Color(0xFFD8D8D8),
            width: active ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 23, color: color),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showMenuIndicator)
              Positioned(
                right: 1,
                bottom: 0,
                child: Icon(Icons.arrow_drop_down, size: 15, color: color),
              ),
          ],
        ),
      );
}

class _PlainToolButton extends StatelessWidget {
  const _PlainToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 88,
        height: 54,
        child: Tooltip(
          message: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: _PickerFace(
              icon: icon,
              label: label,
              color: const Color(0xFFCC2000),
              active: selected,
            ),
          ),
        ),
      );
}

class _ToolbarHeader extends StatelessWidget {
  const _ToolbarHeader({required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Expanded(
            child: Text(
              'TOOLS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFF6D6E71),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Hide main toolbar',
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: onCollapse,
            icon: const Icon(Icons.chevron_left, size: 20),
          ),
        ],
      );
}

class _CollapsibleToolbarSection extends StatelessWidget {
  const _CollapsibleToolbarSection({
    required this.label,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final String label;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            label: '$label tools',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: const Color(0xFF6D6E71)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF4C4D50),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: const Color(0xFF6D6E71),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...children,
          const Divider(height: 12),
        ],
      );
}

IconData iconForDrawingPreset(GraphDrawingPreset preset) => switch (preset) {
      GraphDrawingPreset.mainStructure => Icons.home_work_outlined,
      GraphDrawingPreset.slab => Icons.grid_on,
      GraphDrawingPreset.crawlspace => Icons.foundation_outlined,
      GraphDrawingPreset.basement => Icons.layers_outlined,
      GraphDrawingPreset.woodDeck => Icons.deck_outlined,
      GraphDrawingPreset.woodPorch => Icons.deck_outlined,
      GraphDrawingPreset.openPorch => Icons.meeting_room_outlined,
      GraphDrawingPreset.dirtFilledPorch => Icons.terrain_outlined,
      GraphDrawingPreset.dirtArea => Icons.landscape_outlined,
      GraphDrawingPreset.garage => Icons.garage_outlined,
      GraphDrawingPreset.detachedStructure => Icons.other_houses_outlined,
      GraphDrawingPreset.driveway => Icons.drive_eta_outlined,
      GraphDrawingPreset.walkway => Icons.directions_walk_outlined,
      GraphDrawingPreset.propertyLine => Icons.border_style,
      GraphDrawingPreset.fenceLine => Icons.fence,
      GraphDrawingPreset.measurementLine => Icons.straighten,
      GraphDrawingPreset.treatmentArea => Icons.select_all_outlined,
    };
