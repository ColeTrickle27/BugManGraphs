// LOCAL QA ONLY. Synthetic data, in-process fake API, no production activation.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:bugman_graphs/models/cloud_graph_draft.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/models/graph_point.dart';
import 'package:bugman_graphs/models/graph_shape.dart';
import 'package:bugman_graphs/models/wall_segment.dart';
import 'package:bugman_graphs/screens/cloud_drafts/account_graph_gallery.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_service.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_store_factory.dart';
import 'package:bugman_graphs/services/cloud_drafts/graph_draft_workspace.dart';

const scope = '11111111-1111-4111-8111-111111111111';
const creator = GraphDraftAuthor('fixture-author-1', 'Alex Synthetic');
const other = GraphDraftAuthor('fixture-author-2', 'Jules Synthetic');

class LocalFixtureApi implements GraphDraftService {
  static const key = 'bugman-local-fixture-remote';
  Map<String, dynamic> get data =>
      jsonDecode(web.window.localStorage.getItem(key) ?? '{}')
          as Map<String, dynamic>;
  void write(Map<String, dynamic> value) =>
      web.window.localStorage.setItem(key, jsonEncode(value));
  @override
  Future<GraphDraftAuthors> authors() async =>
      const GraphDraftAuthors('fixture-author-1', [creator, other]);
  @override
  Future<GraphDraftPage> list({int limit = 100, String? cursor}) async =>
      GraphDraftPage([
        for (final item in data.entries)
          GraphDraftSummary(
              id: item.key,
              revision: item.value['revision'] as String,
              title: (item.value['package']['document']['customer']['name']
                  as String),
              updatedAt: DateTime.parse(item.value['updatedAt'] as String),
              author: GraphDraftAuthor.fromJson(
                  (item.value['author'] as Map).cast<String, Object?>()))
      ], null);
  @override
  Future<RemoteGraphDraft> get(String id) async {
    final row = data[id];
    if (row == null) {
      throw const GraphDraftException(404, 'Fixture graph not found');
    }
    return RemoteGraphDraft(
        GraphDraftPackage.fromJson(
            (row['package'] as Map).cast<String, Object?>()),
        row['revision'] as String,
        GraphDraftAuthor.fromJson(
            (row['author'] as Map).cast<String, Object?>()));
  }

  @override
  Future<GraphDraftWriteResult> save(GraphDraftPackage package,
      {required String? expectedRevision, String? authorId}) async {
    final all = data, old = all[package.id];
    if ((expectedRevision == null && old != null) ||
        (expectedRevision != null && old?['revision'] != expectedRevision)) {
      throw const GraphDraftException(409, 'Fixture cloud copy differs.');
    }
    final version = (old?['counter'] as int? ?? 0) + 1,
        revision = version.toRadixString(16).padLeft(32, '0');
    final author = authorId == null
        ? (old == null
            ? creator
            : GraphDraftAuthor.fromJson(
                (old['author'] as Map).cast<String, Object?>()))
        : authorId == other.id
            ? other
            : creator;
    final at = DateTime.now().toUtc();
    all[package.id] = {
      'package': package.toJson(),
      'revision': revision,
      'counter': version,
      'updatedAt': at.toIso8601String(),
      'author': author.toJson()
    };
    write(all);
    return GraphDraftWriteResult(package.id, revision, at, author);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = LocalFixtureApi();
  if (api.data.isEmpty) {
    final document = GraphDocument.forJob(Job(
        customerName: 'Synthetic cloud canvas',
        serviceAddress: 'Synthetic site - no real address',
        pestPacLocationNumber: '',
        pestPacBillToNumber: '',
        serviceType: 'WDIR',
        createdBy: creator.name,
        createdDate: DateTime.utc(2026, 10, 12)));
    final json = document.toJson();
    json['id'] = 'fixture-cloud-canvas';
    final d = GraphDocument.fromJson(json);
    const points = [
      GraphPoint(x: 800, y: 600),
      GraphPoint(x: 1400, y: 600),
      GraphPoint(x: 1400, y: 1000),
      GraphPoint(x: 800, y: 1000)
    ];
    d.replaceWallSegments([
      for (var i = 0; i < 4; i++)
        WallSegment(start: points[i], end: points[(i + 1) % 4])
    ]);
    d.replaceShapes([
      const GraphShape(
          name: 'Main Structure',
          segmentIndexes: [0, 1, 2, 3],
          fillColor: Colors.green,
          fillOpacity: 0.2,
          borderColor: Colors.green,
          borderWidth: 3,
          pattern: GraphShapePattern.none,
          closed: true,
          rotationDegrees: 0,
          preset: GraphDrawingPreset.mainStructure)
    ]);
    await api.save(
        GraphDraftPackage.fromJson({
          'type': 'bugman-graph',
          'version': 1,
          'document': d.toJson(),
          'blobs': {}
        }),
        expectedRevision: null);
  }
  final workspace = GraphDraftWorkspace(
      account: GraphDraftAccount(id: scope, displayName: 'Synthetic account'),
      service: api,
      store: createGraphDraftStore());
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          colorSchemeSeed: const Color(0xffc20000), useMaterial3: true),
      home: AccountGraphGallery(workspace: workspace)));
}
