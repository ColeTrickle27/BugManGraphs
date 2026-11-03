import 'employee_access_stub.dart'
    if (dart.library.html) 'employee_access_web.dart' as platform;

void openGraphEmployeeAccess() => platform.openEmployeeAccess();
