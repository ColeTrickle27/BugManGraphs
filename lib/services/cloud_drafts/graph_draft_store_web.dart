import 'package:idb_shim/idb_browser.dart';
import 'graph_draft_store.dart';
import 'graph_draft_store_indexed.dart';

GraphDraftStore createDraftStore() =>
    IndexedDbGraphDraftStore(idbFactoryBrowser);
