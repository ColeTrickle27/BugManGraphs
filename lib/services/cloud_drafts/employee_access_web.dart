import 'package:web/web.dart' as web;

void openEmployeeAccess() {
  if (Uri.base.origin != 'https://graphs.holloman-ext.com') {
    throw UnsupportedError('Use the official Graphs host for employee access.');
  }
  web.window.open(
      'https://graphs.holloman-ext.com/access-ready', '_blank', 'noopener');
}
