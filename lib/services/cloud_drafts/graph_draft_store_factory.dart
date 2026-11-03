import 'graph_draft_store.dart';
import 'graph_draft_store_stub.dart'
    if (dart.library.html) 'graph_draft_store_web.dart' as platform;

GraphDraftStore createGraphDraftStore() => platform.createDraftStore();
