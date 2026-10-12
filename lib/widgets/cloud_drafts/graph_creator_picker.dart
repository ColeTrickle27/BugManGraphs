import 'package:flutter/material.dart';
import '../../models/cloud_graph_draft.dart';

class GraphCreatorPicker extends StatelessWidget {
  const GraphCreatorPicker(
      {super.key,
      required this.directory,
      required this.value,
      required this.historicalAuthor,
      required this.onChanged});
  final GraphDraftAuthors? directory;
  final String? value;
  final GraphDraftAuthor? historicalAuthor;
  final ValueChanged<GraphDraftAuthor> onChanged;
  @override
  Widget build(BuildContext context) {
    final active = directory?.authors ?? const <GraphDraftAuthor>[];
    final historical = historicalAuthor;
    final historicalOnly =
        historical != null && !active.any((a) => a.id == historical.id);
    final options = [...active, if (historicalOnly) historical];
    if (options.isEmpty) {
      return InputDecorator(
          decoration: const InputDecoration(
              labelText: 'Created By',
              helperText: 'Connect to choose an active creator.'),
          child: Text(historical?.name ?? 'Creator will be confirmed on sync'));
    }
    final selected = value ?? historical?.id ?? directory?.defaultAuthorId;
    return DropdownButtonFormField<String>(
        key: ValueKey('creator-$selected-${active.map((a) => a.id).join(',')}'),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: 'Created By',
            helperText: historicalOnly && selected == historical.id
                ? 'Retained historical creator. Choose an active creator to change it.'
                : 'Graphs stay in your account; this records who prepared the drawing.'),
        items: [
          for (final author in options)
            DropdownMenuItem(
                value: author.id,
                enabled: active.any((a) => a.id == author.id),
                child: Text(author.name, overflow: TextOverflow.ellipsis))
        ],
        onChanged: directory == null
            ? null
            : (id) {
                final author = active.where((a) => a.id == id).firstOrNull;
                if (author != null) onChanged(author);
              });
  }
}
