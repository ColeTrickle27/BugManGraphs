import 'ops_user_service.dart';
import 'ops_user_service_stub.dart'
    if (dart.library.html) 'ops_user_service_web.dart';

OpsUserService createOpsUserService() => createUserService();
