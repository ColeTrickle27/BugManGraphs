import 'dart:typed_data';

enum FileHandoffResult { handedOff, cancelled, unavailable, failed }

abstract class PreparedGraphFile {
  String get name;
  bool get canShare;
  Future<FileHandoffResult> share();
  void download();
}

abstract class GraphFileHandoff {
  PreparedGraphFile prepare(Uint8List bytes, String name, String contentType);
}
