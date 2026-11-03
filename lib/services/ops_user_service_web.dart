import 'package:http/browser_client.dart';
import 'ops_user_service.dart';

OpsUserService createUserService() {
  final mounted = Uri.base.path.startsWith('/bugman-graphs/');
  if (!mounted &&
      !const {'graphs.holloman-ext.com', 'bugman-graphs.pages.dev'}
          .contains(Uri.base.host)) {
    return UnavailableOpsUserService();
  }
  return HttpOpsUserService(BrowserClient()..withCredentials = true,
      mounted ? Uri.base.origin : 'https://ops.holloman-ext.com');
}
