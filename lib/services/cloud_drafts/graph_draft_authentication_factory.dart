import 'graph_draft_authentication.dart';
import 'graph_draft_authentication_stub.dart'
    if (dart.library.html) 'graph_draft_authentication_web.dart' as platform;

GraphDraftAuthentication createGraphDraftAuthentication() =>
    platform.createAuthentication();
