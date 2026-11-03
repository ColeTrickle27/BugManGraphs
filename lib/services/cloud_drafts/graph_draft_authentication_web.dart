import 'package:http/browser_client.dart';
import 'graph_draft_authentication.dart';

GraphDraftAuthentication createAuthentication() => GraphDraftAuthentication(
    client: BrowserClient()..withCredentials = true,
    origin: Uri.parse(Uri.base.origin),
    currentOrigin: Uri.base);
