import 'package:flutter/material.dart';
import '../services/bugman_portal_service.dart';
import 'cloud_graph_package_preview.dart';

/// Receipt repair has its own boundary: no graph repository or save operation.
class PendingGraphFinalizationScreen extends StatefulWidget {
  const PendingGraphFinalizationScreen(
      {super.key,
      required this.portal,
      required this.graphKey,
      this.completePackagePreview = true,
      this.presentationMarkerIds = const {},
      this.presentationKey});
  final BugManPortalService portal;
  final String graphKey;
  final bool completePackagePreview;
  final Set<String> presentationMarkerIds;
  final String? presentationKey;
  @override
  State<PendingGraphFinalizationScreen> createState() => _PendingState();
}

class _PendingState extends State<PendingGraphFinalizationScreen> {
  bool _busy = false;
  String? _error;
  PortalGraphPackage? _verified;
  Future<void> _retry() async {
    if (_busy || widget.portal is! PortalFinalizationRecovery) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final package = await (widget.portal as PortalFinalizationRecovery)
          .retryFinalization(widget.graphKey);
      if (!package.isFinalized) {
        throw const PortalFinalizationException();
      }
      if (mounted) setState(() => _verified = package);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final package = _verified;
    if (package != null) {
      return CloudGraphPackagePreview(
          package: package,
          completePackagePreview: widget.completePackagePreview,
          presentationMarkerIds: widget.presentationMarkerIds,
          presentationKey: widget.presentationKey);
    }
    return Scaffold(
        appBar: AppBar(title: const Text('Finalization pending · read only')),
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'The receipt is not verified. The saved graph remains locked.'),
          if (_error != null) Text(_error!),
          if (widget.portal is PortalFinalizationRecovery)
            FilledButton(
                onPressed: _busy ? null : _retry,
                child:
                    Text(_busy ? 'Verifying receipt…' : 'Retry Finalization')),
        ])));
  }
}
