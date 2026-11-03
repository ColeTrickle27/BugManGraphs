import 'graph_file_handoff.dart';
import 'graph_file_handoff_stub.dart'
    if (dart.library.html) 'graph_file_handoff_web.dart';

GraphFileHandoff createGraphFileHandoff() => createFileHandoff();
