import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'graph_file_handoff.dart';

GraphFileHandoff createFileHandoff() => _WebFileHandoff();

class _WebFileHandoff implements GraphFileHandoff {
  @override
  PreparedGraphFile prepare(Uint8List bytes, String name, String contentType) =>
      _WebPreparedFile(
          web.File(
              [bytes.toJS].toJS, name, web.FilePropertyBag(type: contentType)),
          name);
}

class _WebPreparedFile implements PreparedGraphFile {
  _WebPreparedFile(this.file, this.name);
  final web.File file;
  @override
  final String name;
  web.ShareData get _data => web.ShareData(files: [file].toJS);
  @override
  bool get canShare {
    final navigator = web.window.navigator;
    if (!navigator.hasProperty('share'.toJS).toDart ||
        !navigator.hasProperty('canShare'.toJS).toDart) {
      return false;
    }
    try {
      return navigator.canShare(_data);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<FileHandoffResult> share() {
    if (!canShare) return Future.value(FileHandoffResult.unavailable);
    // The File is already prepared. Invoke synchronously on the final tap;
    // async conversion/rendering here can lose Safari's transient activation.
    try {
      final promise = web.window.navigator.share(_data);
      return promise.toDart.then((_) => FileHandoffResult.handedOff,
          onError: (Object error) => _shareError(error));
    } catch (error) {
      return Future.value(_shareError(error));
    }
  }

  FileHandoffResult _shareError(Object error) {
    if (error is web.DOMException && error.name == 'AbortError') {
      return FileHandoffResult.cancelled;
    }
    if (error is JSObject &&
        error.getProperty<JSAny?>('name'.toJS)?.dartify() == 'AbortError') {
      return FileHandoffResult.cancelled;
    }
    return FileHandoffResult.failed;
  }

  @override
  void download() {
    final url = web.URL.createObjectURL(file);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = name
      ..style.display = 'none';
    web.document.body!.append(link);
    link.click();
    link.remove();
    Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  }
}
