// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void Function() listenForUnsavedUnload(bool Function() hasChanges) {
  final subscription = html.window.onBeforeUnload.listen((event) {
    if (!hasChanges()) return;
    event.preventDefault();
    (event as html.BeforeUnloadEvent).returnValue = '';
  });
  return () => subscription.cancel();
}
