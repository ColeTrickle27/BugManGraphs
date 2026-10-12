// LOCAL QA ONLY: injected local fixture origin; production activation stays off.
import 'package:flutter/material.dart';
import 'package:http/browser_client.dart';
import 'package:bugman_graphs/screens/cloud_drafts/graph_draft_session_screen.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_authentication.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store_factory.dart';
void main() {runApp(MaterialApp(home:GraphDraftSessionScreen(authentication:GraphDraftAuthentication(client:BrowserClient()..withCredentials=true,origin:Uri.parse(Uri.base.origin),currentOrigin:Uri.base),store:createGraphDraftStore())));}
