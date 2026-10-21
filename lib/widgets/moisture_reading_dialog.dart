import 'package:flutter/material.dart';

class MoistureReadingDialog extends StatefulWidget {
  const MoistureReadingDialog({super.key});
  @override
  State<MoistureReadingDialog> createState() => _MoistureReadingDialogState();
}

class _MoistureReadingDialogState extends State<MoistureReadingDialog> {
  final _controller = TextEditingController(text: '15');
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _controller.selection =
          TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _controller.text.trim());
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Moisture percentage'),
        content: SizedBox(
            width: 320,
            child: TextField(
              key: const ValueKey('moisture-reading-entry'),
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                  labelText: 'Moisture reading', suffixText: '%'),
              onSubmitted: (_) => _save(),
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}
