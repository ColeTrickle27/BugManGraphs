import 'dart:convert';
import '../../models/cloud_graph_draft.dart';

class GraphDraftRecovery {
  GraphDraftRecovery(
      {required this.accountId,
      required Map<String, Object?> document,
      Map<String, String> blobs = const {},
      Map<String, Object?> packageExtras = const {},
      this.generation = 1,
      this.acknowledgedGeneration = 0,
      this.revision,
      this.author,
      this.pendingAuthor,
      this.authorIntent = 0,
      this.portalKey,
      this.errorCode,
      this.errorMessage,
      this.conflict})
      : _document = copyGraphJson(document),
        _blobs = Map.unmodifiable(blobs),
        _extras = copyGraphJson(packageExtras) {
    validateDraftId(id);
    if (revision != null) draftRevision(revision);
  }
  final String accountId;
  final Map<String, Object?> _document, _extras;
  final Map<String, String> _blobs;
  final int generation, acknowledgedGeneration, authorIntent;
  final String? revision, portalKey, errorMessage;
  final int? errorCode;
  final GraphDraftAuthor? author, pendingAuthor;
  final RemoteGraphDraft? conflict;
  String get id => _document['id'] as String;
  Map<String, Object?> get document => copyGraphJson(_document);
  Map<String, String> get blobs => Map.of(_blobs);
  Map<String, Object?> get packageExtras => copyGraphJson(_extras);
  bool get dirty =>
      revision == null ||
      generation > acknowledgedGeneration ||
      pendingAuthor != null;
  GraphDraftPackage get package => GraphDraftPackage.fromJson({
        ..._extras,
        'type': 'bugman-graph',
        'version': 1,
        'document': _document,
        'blobs': _blobs
      });
  String get fingerprint =>
      jsonEncode({'document': _document, 'blobs': _blobs, 'extras': _extras});
  GraphDraftRecovery copyWith(
          {Map<String, Object?>? document,
          Map<String, String>? blobs,
          int? generation,
          int? acknowledgedGeneration,
          String? revision,
          GraphDraftAuthor? author,
          GraphDraftAuthor? pendingAuthor,
          bool clearPendingAuthor = false,
          int? authorIntent,
          String? portalKey,
          int? errorCode,
          String? errorMessage,
          bool clearError = false,
          RemoteGraphDraft? conflict,
          bool clearConflict = false}) =>
      GraphDraftRecovery(
          accountId: accountId,
          document: document ?? _document,
          blobs: blobs ?? _blobs,
          packageExtras: _extras,
          generation: generation ?? this.generation,
          acknowledgedGeneration:
              acknowledgedGeneration ?? this.acknowledgedGeneration,
          revision: revision ?? this.revision,
          author: author ?? this.author,
          pendingAuthor:
              clearPendingAuthor ? null : pendingAuthor ?? this.pendingAuthor,
          authorIntent: authorIntent ?? this.authorIntent,
          portalKey: portalKey ?? this.portalKey,
          errorCode: clearError ? null : errorCode ?? this.errorCode,
          errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
          conflict: clearConflict ? null : conflict ?? this.conflict);
  Map<String, Object?> toJson() => {
        'version': 1,
        'accountId': accountId,
        'document': _document,
        'blobs': _blobs,
        'packageExtras': _extras,
        'generation': generation,
        'acknowledgedGeneration': acknowledgedGeneration,
        'revision': revision,
        'author': author?.toJson(),
        'pendingAuthor': pendingAuthor?.toJson(),
        'authorIntent': authorIntent,
        'portalKey': portalKey,
        'errorCode': errorCode,
        'errorMessage': errorMessage,
        'conflict': conflict == null
            ? null
            : {
                'package': conflict!.package.toJson(),
                'revision': conflict!.revision,
                'author': conflict!.author.toJson()
              }
      };
  factory GraphDraftRecovery.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const FormatException('Invalid recovery version');
    }
    final conflict = json['conflict'];
    return GraphDraftRecovery(
        accountId: draftString(json['accountId'], 'recovery account'),
        document: (json['document'] as Map).cast<String, Object?>(),
        blobs: (json['blobs'] as Map).cast<String, String>(),
        packageExtras:
            (json['packageExtras'] as Map? ?? {}).cast<String, Object?>(),
        generation: json['generation'] as int,
        acknowledgedGeneration: json['acknowledgedGeneration'] as int,
        revision: json['revision'] as String?,
        author: json['author'] is Map
            ? GraphDraftAuthor.fromJson(
                (json['author'] as Map).cast<String, Object?>())
            : null,
        pendingAuthor: json['pendingAuthor'] is Map
            ? GraphDraftAuthor.fromJson(
                (json['pendingAuthor'] as Map).cast<String, Object?>())
            : null,
        authorIntent: json['authorIntent'] as int? ?? 0,
        portalKey: json['portalKey'] as String?,
        errorCode: json['errorCode'] as int?,
        errorMessage: json['errorMessage'] as String?,
        conflict: conflict is Map
            ? RemoteGraphDraft(
                GraphDraftPackage.fromJson(
                    (conflict['package'] as Map).cast<String, Object?>()),
                draftRevision(conflict['revision']),
                GraphDraftAuthor.fromJson(
                    (conflict['author'] as Map).cast<String, Object?>()))
            : null);
  }
}

class LocalGraphDraftSummary {
  const LocalGraphDraftSummary(this.id, this.title, this.updatedAt, this.dirty,
      this.errorCode, this.author);
  final String id, title;
  final DateTime updatedAt;
  final bool dirty;
  final int? errorCode;
  final GraphDraftAuthor? author;
  factory LocalGraphDraftSummary.forRecovery(GraphDraftRecovery record) {
    final customer = record.document['customer'] as Map? ?? {};
    return LocalGraphDraftSummary(
        record.id,
        customer['name'] as String? ?? '',
        DateTime.tryParse(record.document['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        record.dirty,
        record.errorCode,
        record.pendingAuthor ?? record.author);
  }
  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'dirty': dirty,
        'errorCode': errorCode,
        'author': author?.toJson()
      };
  factory LocalGraphDraftSummary.fromJson(Map<String, Object?> json) =>
      LocalGraphDraftSummary(
          draftString(json['id'], 'ID'),
          json['title'] as String? ?? '',
          DateTime.parse(json['updatedAt'] as String),
          json['dirty'] as bool,
          json['errorCode'] as int?,
          json['author'] is Map
              ? GraphDraftAuthor.fromJson(
                  (json['author'] as Map).cast<String, Object?>())
              : null);
}
