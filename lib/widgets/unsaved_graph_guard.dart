import 'package:flutter/material.dart';
import '../services/unsaved_unload.dart';

/// Guards the ordinary local editor; cloud draft recovery has its own boundary.
class UnsavedGraphGuard extends StatefulWidget {
  const UnsavedGraphGuard(
      {super.key,
      required this.enabled,
      required this.hasChanges,
      required this.save,
      required this.beforeExit,
      required this.isSaving,
      required this.child});
  final bool enabled;
  final bool Function() hasChanges;
  final bool Function() isSaving;
  final Future<bool> Function() save;
  final VoidCallback beforeExit;
  final Widget child;
  @override
  State<UnsavedGraphGuard> createState() => _UnsavedGraphGuardState();
}

class _UnsavedGraphGuardState extends State<UnsavedGraphGuard> {
  bool _allowPop = false;
  bool _leaving = false;
  late final VoidCallback _stopUnload;
  @override
  void initState() {
    super.initState();
    _stopUnload = listenForUnsavedUnload(() =>
        mounted &&
        widget.enabled &&
        !_allowPop &&
        (widget.hasChanges() || widget.isSaving()));
  }

  @override
  void dispose() {
    _stopUnload();
    super.dispose();
  }

  Future<void> _requestExit(Object? result) async {
    if (_leaving) return;
    if (widget.isSaving()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Wait for the current save to finish before leaving.')));
      return;
    }
    setState(() => _leaving = true);
    try {
      widget.beforeExit();
      if (widget.hasChanges()) {
        final choice = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Unsaved changes'),
                    content: const Text(
                        'Save your changes before leaving this graph?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, 'stay'),
                          child: const Text('Stay')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, 'discard'),
                          child: const Text('Discard and continue')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, 'save'),
                          child: const Text('Save and continue')),
                    ]));
        if (!mounted || choice == null || choice == 'stay') return;
        if (choice == 'save') {
          try {
            if (!await widget.save() || !mounted || widget.hasChanges()) return;
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Changes could not be saved. Keep this graph open and try again.')));
            }
            return;
          }
        }
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop(result);
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
      canPop: !widget.enabled || _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.enabled) _requestExit(result);
      },
      child: AbsorbPointer(absorbing: _leaving, child: widget.child));
}
