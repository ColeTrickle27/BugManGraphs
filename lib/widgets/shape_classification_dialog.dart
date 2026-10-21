import 'package:flutter/material.dart';
import '../models/graph_shape.dart';

class ShapeClassificationChoice {
  const ShapeClassificationChoice(this.preset,
      {this.description = '', this.undo = false});
  const ShapeClassificationChoice.undo()
      : preset = null,
        description = '',
        undo = true;
  final GraphDrawingPreset? preset;
  final String description;
  final bool undo;
}

class ShapeClassificationDialog extends StatefulWidget {
  const ShapeClassificationDialog(
      {required this.initial,
      this.description = '',
      this.editing = false,
      super.key});
  final GraphDrawingPreset initial;
  final String description;
  final bool editing;
  @override
  State<ShapeClassificationDialog> createState() =>
      _ShapeClassificationDialogState();
}

class _ShapeClassificationDialogState extends State<ShapeClassificationDialog> {
  late GraphDrawingPreset selected = widget.initial;
  late final description = TextEditingController(text: widget.description);
  final search = TextEditingController();
  bool more = false;
  String group = 'All';
  static const common = [
    GraphDrawingPreset.mainStructure,
    GraphDrawingPreset.slab,
    GraphDrawingPreset.crawlspace,
    GraphDrawingPreset.basement,
    GraphDrawingPreset.patio,
    GraphDrawingPreset.woodDeck
  ];
  static String groupFor(GraphDrawingPreset p) => switch (p) {
        GraphDrawingPreset.propertyLine ||
        GraphDrawingPreset.fenceLine =>
          'Lines',
        GraphDrawingPreset.treatmentArea => 'Treatment',
        GraphDrawingPreset.woodDeck ||
        GraphDrawingPreset.openPorch ||
        GraphDrawingPreset.dirtFilledPorch ||
        GraphDrawingPreset.dirtArea ||
        GraphDrawingPreset.driveway ||
        GraphDrawingPreset.walkway ||
        GraphDrawingPreset.patio =>
          'Outdoors',
        _ => 'Building',
      };
  @override
  void dispose() {
    description.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recent = widget.initial;
    final choices = <GraphDrawingPreset>{
      if (recent != GraphDrawingPreset.custom &&
          recent != GraphDrawingPreset.measurementLine)
        recent,
      ...common
    }.take(6).toList();
    final matches = GraphDrawingPreset.values
        .where((p) =>
            p != GraphDrawingPreset.measurementLine &&
            p != GraphDrawingPreset.custom &&
            (group == 'All' || groupFor(p) == group) &&
            p.label.toLowerCase().contains(search.text.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text(widget.editing ? 'Change shape type' : 'Classify shape'),
      content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Choose a type. You can change it later.'),
                const SizedBox(height: 12),
                if (!more)
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final p in choices)
                      ChoiceChip(
                          label: Text(p.label),
                          selected: selected == p,
                          onSelected: (_) => setState(() => selected = p),
                          materialTapTargetSize: MaterialTapTargetSize.padded)
                  ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  TextButton.icon(
                      key: const ValueKey('classification-more'),
                      onPressed: () => setState(() => more = !more),
                      icon: Icon(more ? Icons.expand_less : Icons.search),
                      label: Text(more ? 'Hide more types' : 'More types')),
                  ChoiceChip(
                      label: const Text('Custom'),
                      selected: selected == GraphDrawingPreset.custom,
                      onSelected: (_) =>
                          setState(() => selected = GraphDrawingPreset.custom))
                ]),
                if (selected == GraphDrawingPreset.custom)
                  TextField(
                      key: const ValueKey('classification-description'),
                      controller: description,
                      maxLength: 120,
                      decoration: const InputDecoration(
                          labelText: 'Custom description',
                          hintText: 'e.g. Covered patio'),
                      onChanged: (_) => setState(() {})),
                if (more) ...[
                  TextField(
                      key: const ValueKey('classification-search'),
                      controller: search,
                      decoration: const InputDecoration(
                          labelText: 'Search all types',
                          prefixIcon: Icon(Icons.search)),
                      onChanged: (_) => setState(() {})),
                  const SizedBox(height: 8),
                  Wrap(spacing: 4, children: [
                    for (final g in [
                      'All',
                      'Building',
                      'Outdoors',
                      'Lines',
                      'Treatment'
                    ])
                      FilterChip(
                          label: Text(g),
                          selected: group == g,
                          onSelected: (_) => setState(() => group = g))
                  ]),
                  SizedBox(
                      height: 180,
                      child: matches.isEmpty
                          ? const Center(child: Text('No matching types'))
                          : ListView(children: [
                              for (final p in matches)
                                ListTile(
                                    title: Text(p.label),
                                    subtitle: Text(groupFor(p)),
                                    leading: Icon(selected == p
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off),
                                    onTap: () => setState(() => selected = p))
                            ])),
                ],
              ]))),
      actions: [
        if (!widget.editing)
          TextButton(
              onPressed: () => Navigator.pop(
                  context, const ShapeClassificationChoice.undo()),
              child: const Text('Undo shape')),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.editing ? 'Cancel' : 'Classify later')),
        FilledButton(
            onPressed: selected == GraphDrawingPreset.custom &&
                    description.text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    ShapeClassificationChoice(selected,
                        description: description.text.trim())),
            child: const Text('Apply')),
      ],
    );
  }
}
