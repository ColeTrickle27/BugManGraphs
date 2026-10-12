import 'dart:convert';
import 'dart:typed_data';

Map<String, Object?> copyGraphJson(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();
String draftString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid cloud draft $field');
  }
  return value;
}

void validateDraftId(String id) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,120}$').hasMatch(id) || const {'authors', 'context'}.contains(id)) {
    throw const FormatException('This graph needs a valid draft identity.');
  }
}

String draftRevision(Object? value) {
  final revision = draftString(value, 'revision');
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(revision)) {
    throw const FormatException('Invalid cloud draft revision');
  }
  return revision;
}

class GraphDraftAuthor {
  const GraphDraftAuthor(this.id, this.name);
  final String id, name;
  factory GraphDraftAuthor.fromJson(Map<String, Object?> json) =>
      GraphDraftAuthor(draftString(json['id'], 'author ID'),
          draftString(json['name'], 'author name'));
  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

class GraphDraftAuthors {
  const GraphDraftAuthors(this.defaultAuthorId, this.authors);
  final String defaultAuthorId;
  final List<GraphDraftAuthor> authors;
  factory GraphDraftAuthors.fromJson(Map<String, Object?> json) {
    final list = json['authors'];
    if (list is! List) throw const FormatException('Invalid author directory');
    final authors = list
        .map((a) =>
            GraphDraftAuthor.fromJson((a as Map).cast<String, Object?>()))
        .toList();
    final defaultId = draftString(json['defaultAuthorId'], 'default author');
    if (!authors.any((a) => a.id == defaultId) ||
        authors.map((a) => a.id).toSet().length != authors.length) {
      throw const FormatException('Invalid active author directory');
    }
    return GraphDraftAuthors(defaultId, List.unmodifiable(authors));
  }
}

/// Complete version-one .bgraph data. Owner identity is never inferred here.
/// Unknown document/package fields and attachment ordering are retained.
class GraphDraftPackage {
  GraphDraftPackage._(this._json);
  final Map<String, Object?> _json;
  factory GraphDraftPackage.fromJson(Map<String, Object?> json) {
    final data = copyGraphJson(json);
    if (data['type'] != 'bugman-graph' ||
        data['version'] != 1 ||
        data['document'] is! Map ||
        data['blobs'] is! Map) {
      throw const FormatException('Invalid graph package');
    }
    final doc = (data['document'] as Map).cast<String, Object?>();
    validateDraftId(draftString(doc['id'], 'ID'));
    final attachments = doc['attachments'];
    if (attachments is! List) {
      throw const FormatException('Graph attachments are missing');
    }
    final blobs = (data['blobs'] as Map).cast<String, Object?>();
    for (final value in blobs.values) {
      if (value is! String || value.isEmpty) {
        throw const FormatException('Photo data is missing');
      }
      try {
        if (base64Decode(value).isEmpty) {
          throw const FormatException('Photo data is empty');
        }
      } on FormatException {
        throw const FormatException('Photo data could not be read');
      }
    }
    final ids = <String>{};
    for (final item in attachments) {
      if (item is! Map) throw const FormatException('Invalid photo attachment');
      final id = draftString(item['id'], 'attachment ID');
      if (!ids.add(id)) {
        throw const FormatException('Duplicate photo attachment');
      }
      final full = draftString(item['blobKey'], 'full photo key');
      final thumbnail = item['thumbnailKey'];
      if (!blobs.containsKey(full) ||
          (thumbnail is String &&
              thumbnail.isNotEmpty &&
              !blobs.containsKey(thumbnail))) {
        throw const FormatException(
            'Full photo or thumbnail data needs recovery');
      }
    }
    return GraphDraftPackage._(data);
  }
  String get id => (_json['document'] as Map)['id'] as String;
  Map<String, Object?> get document =>
      copyGraphJson((_json['document'] as Map).cast<String, Object?>());
  Map<String, Object?> toJson() => copyGraphJson(_json);
  Map<String, Uint8List> decodeBlobs() => {
        for (final entry in (_json['blobs'] as Map).entries)
          entry.key as String: base64Decode(entry.value as String),
      };
}

class GraphDraftSummary {
  const GraphDraftSummary(
      {required this.id,
      required this.revision,
      required this.title,
      required this.updatedAt,
      required this.author});
  final String id, revision, title;
  final DateTime updatedAt;
  final GraphDraftAuthor author;
  factory GraphDraftSummary.fromJson(Map<String, Object?> json) {
    final id = draftString(json['id'], 'ID');
    validateDraftId(id);
    return GraphDraftSummary(
        id: id,
        revision: draftRevision(json['revision']),
        title: json['title'] as String? ?? '',
        updatedAt:
            DateTime.parse(draftString(json['updatedAt'], 'updated time')),
        author: GraphDraftAuthor(draftString(json['authorId'], 'author ID'),
            draftString(json['authorName'], 'author name')));
  }
}

class GraphDraftPage {
  const GraphDraftPage(this.drafts, this.nextCursor);
  final List<GraphDraftSummary> drafts;
  final String? nextCursor;
}

class RemoteGraphDraft {
  const RemoteGraphDraft(this.package, this.revision, this.author);
  final GraphDraftPackage package;
  final String revision;
  final GraphDraftAuthor author;
}

class GraphDraftWriteResult {
  const GraphDraftWriteResult(
      this.id, this.revision, this.updatedAt, this.author);
  final String id, revision;
  final DateTime updatedAt;
  final GraphDraftAuthor author;
}
