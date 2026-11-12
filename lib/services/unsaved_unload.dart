import 'unsaved_unload_stub.dart'
    if (dart.library.html) 'unsaved_unload_web.dart' as platform;

/// Browsers control the wording and buttons of this native confirmation.
void Function() listenForUnsavedUnload(bool Function() hasChanges) =>
    platform.listenForUnsavedUnload(hasChanges);
