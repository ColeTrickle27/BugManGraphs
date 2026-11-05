import 'package:http/browser_client.dart';

import 'cloud_graph_history.dart';

CloudGraphHistoryService? createCloudGraphHistoryService() {
  final mounted = Uri.base.path.startsWith('/bugman-graphs/');
  if (!mounted &&
      !const {
        'graphs.holloman-ext.com',
        'bugman-graphs.pages.dev',
      }.contains(Uri.base.host)) {
    return null;
  }
  return HttpCloudGraphHistoryService(
    origin: Uri.parse(
      mounted ? Uri.base.origin : 'https://ops.holloman-ext.com',
    ),
    client: BrowserClient()..withCredentials = true,
  );
}
