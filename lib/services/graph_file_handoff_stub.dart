import 'dart:typed_data';
import 'graph_file_handoff.dart';

GraphFileHandoff createFileHandoff() => _UnavailableHandoff();

class _UnavailableHandoff implements GraphFileHandoff {
  @override
  PreparedGraphFile prepare(Uint8List bytes, String name, String contentType) =>
      _UnavailableFile(name);
}

class _UnavailableFile implements PreparedGraphFile {
  _UnavailableFile(this.name);
  @override
  final String name;
  @override
  bool get canShare => false;
  @override
  Future<FileHandoffResult> share() async => FileHandoffResult.unavailable;
  @override
  void download() =>
      throw UnsupportedError('File downloads require a web browser');
}
