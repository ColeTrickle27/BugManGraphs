// Synthetic-only browser fixture. No customer or location data.
import 'package:flutter/material.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/services/graph_repository_factory.dart';
import '../test/support/crowded_canvas_fixture.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = createGraphRepository();
  final document = await repository.loadGraph('synthetic-canvas-review') ?? crowdedCanvasFixture();
  runApp(MaterialApp(home: GraphCanvasScreen(document: document, repository: repository)));
}
