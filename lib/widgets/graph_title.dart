import 'package:flutter/material.dart';

/// Keeps the full title reachable even when the app bar has little space.
class GraphTitle extends StatelessWidget {
  const GraphTitle(this.title,
      {this.style, this.overflow = TextOverflow.ellipsis, super.key});
  final String title;
  final TextStyle? style;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        label: 'Show full graph title',
        child: Tooltip(
          message: title,
          child: InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Graph title'),
                content: SingleChildScrollView(child: SelectableText(title)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'))
                ],
              ),
            ),
            child: Text(title, maxLines: 1, overflow: overflow, style: style),
          ),
        ),
      );
}
