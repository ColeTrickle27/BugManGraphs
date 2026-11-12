import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
          preset == GraphDrawingPreset.mainStructure
              ? 'Sketch / Area'
              : preset == GraphDrawingPreset.propertyLine
                  ? 'Property Line (acres)'
                  : preset!.label,
        CanvasToolbarActionKind.marker => marker!.label,
      };

  String get shortLabel => switch (kind) {
        CanvasToolbarActionKind.tool => tool!.label,
        CanvasToolbarActionKind.preset =>
          preset == GraphDrawingPreset.mainStructure
              ? 'Sketch / Area'
              : preset!.shortLabel,
        CanvasToolbarActionKind.marker => marker!.shortLabel,
      };

  String get shortcut => tool?.shortcut ?? '';

  IconData get icon => switch (kind) {
        CanvasToolbarActionKind.tool => tool!.icon,
        CanvasToolbarActionKind.preset => iconForDrawingPreset(preset!),
        CanvasToolbarActionKind.marker => iconForGraphMarker(marker!),
      };

  Color get color => switch (kind) {
        CanvasToolbarActionKind.tool => AppColors.red,
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
  CanvasToolbarAction.preset(GraphDrawingPreset.patio),
  CanvasToolbarAction.preset(GraphDrawingPreset.custom),
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
  CanvasToolbarAction.marker(GraphMarkerType.stepsFront),
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
    this.width = 112,
    this.compact = false,
    this.panelHeader,
    this.onActionAdded,
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

  final double width;
  final bool compact;
  final Widget? panelHeader;
  final ValueChanged<CanvasToolbarAction>? onActionAdded;
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

  static int compactColumns(double width, TextScaler scaler) =>
      ((width - 10) / (76 * scaler.scale(12) / 12)).floor().clamp(2, 4);

  static double compactTileHeight(TextScaler scaler) =>
      60 + (scaler.scale(12) - 12).clamp(0, double.infinity) * 2;

  static double compactHeight(double width, TextScaler scaler) {
    final rows = (8 / compactColumns(width, scaler)).ceil();
    return 68 + rows * compactTileHeight(scaler) + (rows - 1) * 6;
  }
  @override
  State<CanvasToolbar> createState() => _CanvasToolbarState();
}

class _CanvasToolbarState extends State<CanvasToolbar> {
  String? _expandedSection = 'Sketch Structure';
  final _compactScrollController = ScrollController();

  @override
  void dispose() {
    _compactScrollController.dispose();
    super.dispose();
  }

  void _activate(CanvasToolbarAction action) {
    switch (action.kind) {
      case CanvasToolbarActionKind.tool:
        widget.onToolSelected(action.tool!);
      case CanvasToolbarActionKind.preset:
        widget.onDrawingPresetSelected(action.preset!);
      case CanvasToolbarActionKind.marker:
        widget.onMarkerSelected(action.marker!);
    }
    if (widget.compact) widget.onCollapse();
  }

  Widget _compactTools(BuildContext context) {
    Widget menu(
      String label,
      IconData icon,
      List<CanvasToolbarAction> actions,
    ) => PopupMenuButton<CanvasToolbarAction>(
      key: ValueKey('mobile-tool-$label'),
      tooltip: '$label tools',
      onSelected: _activate,
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
                  selectedTool: widget.selectedTool,
                  selectedPreset: widget.selectedDrawingPreset,
                  selectedMarker: widget.selectedMarkerType,
                ))
                  const Icon(Icons.check, size: 20),
                if (widget.onActionAdded != null)
                  IconButton(
                    tooltip: 'Add ${action.label} to quick tools',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onActionAdded!(action);
                      widget.onCollapse();
                    },
                    icon: const Icon(Icons.push_pin_outlined, size: 20),
                  ),
              ],
            ),
          ),
      ],
      child: _CompactToolFace(
        label: label,
        icon: icon,
        hasMenu: true,
        selected: actions.any(
          (action) => action.isSelected(
            selectedTool: widget.selectedTool,
            selectedPreset: widget.selectedDrawingPreset,
            selectedMarker: widget.selectedMarkerType,
          ),
        ),
      ),
    );

    return Scrollbar(
      controller: _compactScrollController,
      thumbVisibility: true,
      child: GridView.count(
        key: const ValueKey('mobile-tool-grid'),
        controller: _compactScrollController,
        padding: EdgeInsets.zero,
        crossAxisCount: CanvasToolbar.compactColumns(
          widget.width,
          MediaQuery.textScalerOf(context),
        ),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        mainAxisExtent: CanvasToolbar.compactTileHeight(
          MediaQuery.textScalerOf(context),
        ),
        children: [
          menu('Draw', Icons.edit_outlined, [
            ...basicLineToolbarActions,
            ...basicShapeToolbarActions,
          ]),
          InkWell(
            key: const ValueKey('mobile-tool-Sketch'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => _activate(
              const CanvasToolbarAction.preset(
                GraphDrawingPreset.mainStructure,
              ),
            ),
            onLongPress: widget.onActionAdded == null
                ? null
                : () {
                    widget.onActionAdded!(
                      const CanvasToolbarAction.preset(
                        GraphDrawingPreset.mainStructure,
                      ),
                    );
                    widget.onCollapse();
                  },
            child: _CompactToolFace(
              label: 'Sketch',
              icon: Icons.home_work_outlined,
              selected:
                  widget.selectedTool == CanvasTool.structure &&
                  widget.selectedDrawingPreset ==
                      GraphDrawingPreset.mainStructure,
            ),
          ),
          menu(
            'Structures',
            Icons.other_houses_outlined,
            buildingFeatureToolbarActions,
          ),
          menu('Features', Icons.hvac, utilityToolbarActions),
          menu('Property', Icons.border_style, propertyToolbarActions),
          menu('Findings', Icons.search_outlined, [
            for (final marker in inspectionMarkerTypes)
              CanvasToolbarAction.marker(marker),
            const CanvasToolbarAction.tool(CanvasTool.photo),
          ]),
          menu('Treatment', Icons.medical_services_outlined, [
            for (final marker in treatmentMarkerTypes)
              CanvasToolbarAction.marker(marker),
          ]),
          InkWell(
            key: const ValueKey('mobile-tool-Satellite'),
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              widget.onCollapse();
              widget.onToggleTraceLayer();
            },
            child: const _CompactToolFace(
              label: 'Satellite',
              icon: Icons.satellite_alt_outlined,
              selected: false,
            ),
          ),
        ],
      ),
    );
  }
  CanvasToolbarAction _displayedAction(List<CanvasToolbarAction> actions) {
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
      color: const Color(0xFF261F24),
      child: SizedBox(
        width: widget.width,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              widget.panelHeader ?? _ToolbarHeader(onCollapse: widget.onCollapse),
              const SizedBox(height: 4),
              Expanded(
                  child: widget.compact
                      ? _compactTools(context)
                      : SingleChildScrollView(
                      child: Column(children: [
                _section(
                  label: 'Annotate',
                  icon: Icons.edit_note_outlined,
                  children: [
                    _ActionPicker(
                      groupLabel: 'Callouts & Sketch',
                      displayedAction: _displayedAction(
                        basicLineToolbarActions,
                      ),
                      actions: basicLineToolbarActions,
                      selectedTool: widget.selectedTool,
                      selectedPreset: widget.selectedDrawingPreset,
                      selectedMarker: widget.selectedMarkerType,
                      onSelected: _activate,
                    ),
                    const SizedBox(height: 6),
                    _ActionPicker(
                      groupLabel: 'Basic Shapes',
                      displayedAction: _displayedAction(
                        basicShapeToolbarActions,
                      ),
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
                      groupLabel: 'Structure Features',
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
                      CanvasToolbarAction.tool(CanvasTool.photo),
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
                              .where(
                                (marker) =>
                                    marker != GraphMarkerType.treatmentNote,
                              )
                              .contains(widget.selectedMarkerType),
                      markers: treatmentMarkerTypes
                          .where(
                            (marker) => marker != GraphMarkerType.treatmentNote,
                          )
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
              ]))),
            ],
          ),
        ),
      ),
    );
  }
}

class CanvasQuickToolbar extends StatelessWidget {
  final bool showHistory;
  final bool canUndo;
  final bool canRedo;
  const CanvasQuickToolbar({
    this.showHistory = true,
    this.canUndo = true,
    this.canRedo = true,
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
  Widget build(BuildContext context) => _QuickToolbarRegion(
        builder: (expanded, expandLabel) => DragTarget<CanvasToolbarAction>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (details) => onActionAdded(details.data),
          builder: (context, candidates, rejected) =>
              LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final actionButtons = <Widget>[
              for (final action in actions)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _QuickActionButton(
                      action: action,
                      compact: compact,
                      expandLabel: expanded,
                      selected: action.isSelected(
                          selectedTool: selectedTool,
                          selectedPreset: selectedDrawingPreset,
                          selectedMarker: selectedMarkerType),
                      onPressed: () {
                        expandLabel();
                        onActionSelected(action);
                      },
                    )),
            ];
            final utilities = <Widget>[
              _QuickUtilityButton(
                  icon: Icons.undo,
                  tooltip: 'Quick undo',
                  selected: false,
                  onPressed: onUndo),
              _QuickUtilityButton(
                  icon: Icons.redo,
                  tooltip: 'Quick redo',
                  selected: false,
                  onPressed: onRedo),
              const _QuickToolbarDivider(),
              _QuickUtilityButton(
                  icon: Icons.edit_note,
                  tooltip: 'Object properties',
                  selected: propertiesSelected,
                  onPressed: onToggleProperties),
              _QuickUtilityButton(
                  icon: Icons.layers_outlined,
                  tooltip: 'Layers panel',
                  selected: layersSelected,
                  onPressed: onToggleLayers),
              _QuickUtilityButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete selection',
                  selected: false,
                  onPressed: onDeleteSelection),
              if (actions.length > 2)
                _QuickUtilityButton(
                    icon: Icons.restart_alt,
                    tooltip: 'Reset quick toolbar',
                    selected: false,
                    onPressed: onReset),
            ];
            final more = PopupMenuButton<String>(
              tooltip: 'More quick tools',
              icon: const Icon(Icons.more_horiz, color: Color(0xFF687078)),
              constraints: const BoxConstraints(minWidth: 220),
              onSelected: (value) {
                switch (value) {
                  case 'undo':
                    onUndo();
                  case 'redo':
                    onRedo();
                  case 'properties':
                    onToggleProperties();
                  case 'layers':
                    onToggleLayers();
                  case 'delete':
                    onDeleteSelection();
                  case 'reset':
                    onReset();
                  case 'hide':
                    onCollapse();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'undo', child: Text('Undo')),
                const PopupMenuItem(value: 'redo', child: Text('Redo')),
                CheckedPopupMenuItem(
                    value: 'properties',
                    checked: propertiesSelected,
                    child: const Text('Properties')),
                CheckedPopupMenuItem(
                    value: 'layers',
                    checked: layersSelected,
                    child: const Text('Layers')),
                const PopupMenuItem(
                    value: 'delete', child: Text('Delete selection')),
                if (actions.length > 2)
                  const PopupMenuItem(
                      value: 'reset', child: Text('Reset quick toolbar')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                    value: 'hide', child: Text('Hide quick toolbar')),
              ],
            );
            final history = <Widget>[
              if (!compact)
                IconButton(
                    tooltip: 'Hide quick toolbar',
                    onPressed: onCollapse,
                    icon: const Icon(Icons.keyboard_arrow_down)),
              if (showHistory) ...[
                IconButton(
                    key: const ValueKey('canvas-bottom-undo'),
                    tooltip: 'Undo',
                    constraints:
                        const BoxConstraints.tightFor(width: 44, height: 44),
                    padding: EdgeInsets.zero,
                    onPressed: canUndo ? onUndo : null,
                    icon: const Icon(Icons.undo)),
                IconButton(
                    key: const ValueKey('canvas-bottom-redo'),
                    tooltip: 'Redo',
                    constraints:
                        const BoxConstraints.tightFor(width: 44, height: 44),
                    padding: EdgeInsets.zero,
                    onPressed: canRedo ? onRedo : null,
                    icon: const Icon(Icons.redo)),
              ],
            ];
            final content = Row(mainAxisSize: MainAxisSize.min, children: [
              ...history,
              const _QuickToolbarDivider(),
              Flexible(
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [...actionButtons, ...utilities.skip(3)]))),
              if (compact) more,
            ]);
            final surface = Material(
              key: const ValueKey('canvas-quick-toolbar'),
              elevation: 3,
              shadowColor: const Color(0x26000000),
              color:
                  candidates.isEmpty ? Colors.white : const Color(0xFFFFEEEE),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                      color: candidates.isEmpty
                          ? const Color(0xFFDADDE1)
                          : AppColors.red)),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                  child: content),
            );
            return compact
                ? surface
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal, child: surface);
          }),
        ),
      );
}

class _QuickToolbarRegion extends StatefulWidget {
  const _QuickToolbarRegion({required this.builder});
  final Widget Function(bool, VoidCallback) builder;
  @override
  State<_QuickToolbarRegion> createState() => _QuickToolbarRegionState();
}

class _QuickToolbarRegionState extends State<_QuickToolbarRegion> {
  bool expanded = true;
  @override
  Widget build(BuildContext context) => TapRegion(
        onTapOutside: (_) {
          if (expanded) setState(() => expanded = false);
        },
        child: widget.builder(expanded, () => setState(() => expanded = true)),
      );
}

class _QuickToolbarDivider extends StatelessWidget {
  const _QuickToolbarDivider();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
          height: 30,
          child: VerticalDivider(
              width: 1, thickness: 1, color: Color(0xFFE4E6E8))));
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
  const _DraggableAction({required this.action, required this.child});

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
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          color: selected ? AppColors.red : const Color(0xFF687078),
          onPressed: onPressed,
          icon: Icon(icon, size: 24),
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
          border: Border.all(color: AppColors.red, width: 2),
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
    required this.expandLabel,
    required this.selected,
    required this.onPressed,
  });

  final CanvasToolbarAction action;
  final bool compact;
  final bool expandLabel;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: action.tooltip,
        child: Semantics(
            selected: selected,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFFFFEEEE) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      action.icon,
                      size: 24,
                      color: selected ? AppColors.red : const Color(0xFF687078),
                    ),
                    AnimatedSize(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: selected && expandLabel
                          ? Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxWidth: compact ? 48 : 160),
                                  child: Text(
                                    action.label,
                                    key: ValueKey(
                                        'quick-active-label-${action.label}'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.red,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )))
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            )),
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
              color: AppColors.red,
              active: selected,
            ),
          ),
        ),
      );
}

class _CompactToolFace extends StatelessWidget {
  const _CompactToolFace({
    required this.label,
    required this.icon,
    required this.selected,
    this.hasMenu = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool hasMenu;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Ink(
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFEEEE) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? AppColors.red : const Color(0xFFE6E1E4),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? AppColors.red : const Color(0xFF353036),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.red : const Color(0xFF353036),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasMenu)
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Color(0xFF687078),
              ),
            ),
        ],
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
                color: Color(0xFFE7DCE1),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Tooltip(
            message: 'Hide main toolbar',
            child: TextButton.icon(
              onPressed: onCollapse,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.red,
                minimumSize: const Size(80, 44),
                visualDensity: VisualDensity.standard,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: const Icon(Icons.close, size: 20),
              label: const Text('Hide'),
            ),
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
                    Icon(icon, size: 18, color: const Color(0xFFE7DCE1)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        style: const TextStyle(
                          color: Color(0xFFF8F2F5),
                          fontFamily: 'Raider Straight',
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
                      color: const Color(0xFFE7DCE1),
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
      GraphDrawingPreset.patio => Icons.grid_on,
      GraphDrawingPreset.custom => Icons.edit_outlined,
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
