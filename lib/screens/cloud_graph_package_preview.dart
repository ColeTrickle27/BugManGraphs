import 'package:flutter/material.dart';

import '../services/bugman_portal_service.dart';
import '../services/bugman_portal_service_stub.dart';
import '../services/cloud_graph_preview_repository.dart';
import 'graph_canvas_screen.dart';

/// Both entry routes use an isolated viewer, with no persistent write boundary.
class CloudGraphPackagePreview extends StatelessWidget {
  const CloudGraphPackagePreview(
      {super.key,
      required this.package,
      this.completePackagePreview = true,
      this.presentationMarkerIds = const {},
      this.presentationKey});
  final PortalGraphPackage package;
  final bool completePackagePreview;
  final Set<String> presentationMarkerIds;
  final String? presentationKey;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(package.isFinalized
                ? 'Locked · read only'
                : 'Cloud history · read only')),
        body: GraphCanvasScreen(
          document: package.document,
          repository: CloudGraphPreviewRepository(package),
          portalService: UnavailableBugManPortalService(),
          portalKey: presentationKey,
          presentationMode: true,
          completePackagePreview: completePackagePreview,
          presentationMarkerIds: presentationMarkerIds,
          presentationFitToContent: true,
        ),
      );
}
