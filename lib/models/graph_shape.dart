import 'dart:ui';

enum GraphShapePattern {
  none,
  diagonal,
  reverseDiagonal,
  crossHatch,
  horizontal,
  vertical,
  grid,
  dots,
  largeDots,
  checker,
}

enum GraphDrawingPresetKind {
  area,
  line,
}

/// The foundation condition recorded with a main structure. It is stored in
/// [GraphShape.extraProperties] so older saved graphs remain valid.
enum StructureFoundationType {
  crawlspace('Crawlspace'),
  slab('Slab'),
  basement('Basement'),
  combination('Combination');

  const StructureFoundationType(this.label);

  final String label;
}

enum GraphDrawingPreset {
  mainStructure(
    'Draw Structure',
    'Main Structure',
    GraphDrawingPresetKind.area,
    Color(0xFFB6D94C),
    0.30,
    Color(0xFF214D38),
    3,
    GraphShapePattern.none,
    Color(0xFF214D38),
    5,
    LinePatternValue.solid,
  ),
  slab(
    'Concrete Slab',
    'SLAB',
    GraphDrawingPresetKind.area,
    Color(0xFFD8DEE6),
    0.45,
    Color(0xFF56616E),
    3,
    GraphShapePattern.grid,
    Color(0xFF56616E),
    5,
    LinePatternValue.solid,
  ),
  crawlspace(
    'Crawlspace',
    'CRAWL',
    GraphDrawingPresetKind.area,
    Color(0xFFC99A52),
    0.32,
    Color(0xFF7A4E21),
    3,
    GraphShapePattern.diagonal,
    Color(0xFF7A4E21),
    5,
    LinePatternValue.solid,
  ),
  basement(
    'Basement',
    'BASE',
    GraphDrawingPresetKind.area,
    Color(0xFF8FB5E8),
    0.34,
    Color(0xFF245B9E),
    3,
    GraphShapePattern.horizontal,
    Color(0xFF245B9E),
    5,
    LinePatternValue.solid,
  ),
  woodDeck(
    'Wood Deck',
    'DECK',
    GraphDrawingPresetKind.area,
    Color(0xFFE2B56D),
    0.38,
    Color(0xFF8A5A2B),
    3,
    GraphShapePattern.vertical,
    Color(0xFF8A5A2B),
    5,
    LinePatternValue.solid,
  ),
  openPorch(
    'Open Porch',
    'PORCH',
    GraphDrawingPresetKind.area,
    Color(0xFFFFD66B),
    0.30,
    Color(0xFFB17C18),
    3,
    GraphShapePattern.dots,
    Color(0xFFB17C18),
    5,
    LinePatternValue.solid,
  ),
  woodPorch(
    'Wood Porch',
    'PORCH',
    GraphDrawingPresetKind.area,
    Color(0xFFE2B56D),
    0.38,
    Color(0xFF8A5A2B),
    3,
    GraphShapePattern.vertical,
    Color(0xFF8A5A2B),
    5,
    LinePatternValue.solid,
  ),
  dirtFilledPorch(
    'Dirt-Filled Porch',
    'DIRT',
    GraphDrawingPresetKind.area,
    Color(0xFFC58D5A),
    0.35,
    Color(0xFF6A4328),
    3,
    GraphShapePattern.crossHatch,
    Color(0xFF6A4328),
    5,
    LinePatternValue.solid,
  ),
  dirtArea(
    'Dirt Area',
    'DIRT',
    GraphDrawingPresetKind.area,
    Color(0xFFC58D5A),
    0.30,
    Color(0xFF6A4328),
    3,
    GraphShapePattern.dots,
    Color(0xFF6A4328),
    5,
    LinePatternValue.solid,
  ),
  garage(
    'Garage/Carport',
    'GAR',
    GraphDrawingPresetKind.area,
    Color(0xFFB5C8D8),
    0.36,
    Color(0xFF435C70),
    3,
    GraphShapePattern.none,
    Color(0xFF435C70),
    5,
    LinePatternValue.solid,
  ),
  detachedStructure(
    'Detached Structure',
    'DET',
    GraphDrawingPresetKind.area,
    Color(0xFFC7B3E8),
    0.32,
    Color(0xFF6246A8),
    3,
    GraphShapePattern.reverseDiagonal,
    Color(0xFF6246A8),
    5,
    LinePatternValue.solid,
  ),
  driveway(
    'Driveway',
    'DRIVE',
    GraphDrawingPresetKind.area,
    Color(0xFF9EA3A8),
    0.30,
    Color(0xFF4B4F54),
    3,
    GraphShapePattern.none,
    Color(0xFF4B4F54),
    4,
    LinePatternValue.solid,
  ),
  walkway(
    'Walkway',
    'WALK',
    GraphDrawingPresetKind.area,
    Color(0xFFC4C7CA),
    0.34,
    Color(0xFF6D6E71),
    3,
    GraphShapePattern.none,
    Color(0xFF6D6E71),
    4,
    LinePatternValue.solid,
  ),
  propertyLine(
    'Property Line',
    'PROP',
    GraphDrawingPresetKind.line,
    null,
    0,
    Color(0xFF1C2B22),
    2,
    GraphShapePattern.none,
    Color(0xFF1C2B22),
    3,
    LinePatternValue.dashed,
  ),
  fenceLine(
    'Fence Line',
    'FENCE',
    GraphDrawingPresetKind.line,
    null,
    0,
    Color(0xFF795548),
    2,
    GraphShapePattern.none,
    Color(0xFF795548),
    4,
    LinePatternValue.xMarks,
  ),
  measurementLine(
    'Quick Measure',
    'MEASURE',
    GraphDrawingPresetKind.area,
    Color(0xFF4D9CFF),
    0.14,
    Color(0xFF245BDB),
    3,
    GraphShapePattern.none,
    Color(0xFF245BDB),
    3,
    LinePatternValue.dashed,
  ),
  treatmentArea(
    'Treatment Area',
    'TA',
    GraphDrawingPresetKind.area,
    Color(0xFF5B8DEF),
    0.22,
    Color(0xFF245BDB),
    3,
    GraphShapePattern.dots,
    Color(0xFF245BDB),
    3,
    LinePatternValue.solid,
  );

  const GraphDrawingPreset(
    this.label,
    this.shortLabel,
    this.kind,
    this.defaultFillColor,
    this.defaultFillOpacity,
    this.defaultBorderColor,
    this.defaultBorderWidth,
    this.defaultPattern,
    this.defaultLineColor,
    this.defaultLineWidth,
    this.defaultLinePattern,
  );

  final String label;
  final String shortLabel;
  final GraphDrawingPresetKind kind;
  final Color? defaultFillColor;
  final double defaultFillOpacity;
  final Color defaultBorderColor;
  final double defaultBorderWidth;
  final GraphShapePattern defaultPattern;
  final Color defaultLineColor;
  final double defaultLineWidth;
  final LinePatternValue defaultLinePattern;
}

extension GraphDrawingPresetMeasurements on GraphDrawingPreset {
  bool get showsLinearAndAreaMeasurements => const {
        GraphDrawingPreset.mainStructure,
        GraphDrawingPreset.slab,
        GraphDrawingPreset.crawlspace,
        GraphDrawingPreset.woodDeck,
        GraphDrawingPreset.woodPorch,
        GraphDrawingPreset.openPorch,
        GraphDrawingPreset.dirtFilledPorch,
        GraphDrawingPreset.garage,
        GraphDrawingPreset.detachedStructure,
        GraphDrawingPreset.measurementLine,
      }.contains(this);

  bool get showsPropertyAreaMeasurements =>
      this == GraphDrawingPreset.propertyLine;
}

enum LinePatternValue {
  solid,
  dashed,
  xMarks,
  dottedSmall,
  dottedLarge,
  diamonds,
}

class GraphShape {
  const GraphShape({
    required this.name,
    required this.segmentIndexes,
    required this.fillColor,
    required this.fillOpacity,
    required this.borderColor,
    required this.borderWidth,
    required this.pattern,
    required this.closed,
    required this.rotationDegrees,
    this.preset,
    this.text = '',
    this.extraProperties = const <String, Object?>{},
  });

  final String name;
  final List<int> segmentIndexes;
  final Color? fillColor;
  final double fillOpacity;
  final Color borderColor;
  final double borderWidth;
  final GraphShapePattern pattern;
  final bool closed;
  final double rotationDegrees;
  final GraphDrawingPreset? preset;
  final String text;
  final Map<String, Object?> extraProperties;

  bool get isStructure => preset != null;

  StructureFoundationType? get foundationType {
    final rawValue = extraProperties['foundationType'];
    if (rawValue is! String) return null;
    for (final type in StructureFoundationType.values) {
      if (type.name == rawValue) return type;
    }
    return null;
  }

  GraphShape copyWith({
    String? name,
    List<int>? segmentIndexes,
    Color? fillColor,
    bool clearFillColor = false,
    double? fillOpacity,
    Color? borderColor,
    double? borderWidth,
    GraphShapePattern? pattern,
    bool? closed,
    double? rotationDegrees,
    GraphDrawingPreset? preset,
    bool clearPreset = false,
    String? text,
    Map<String, Object?>? extraProperties,
  }) {
    return GraphShape(
      name: name ?? this.name,
      segmentIndexes: segmentIndexes ?? this.segmentIndexes,
      fillColor: clearFillColor ? null : fillColor ?? this.fillColor,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      pattern: pattern ?? this.pattern,
      closed: closed ?? this.closed,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      preset: clearPreset ? null : preset ?? this.preset,
      text: text ?? this.text,
      extraProperties: extraProperties ?? this.extraProperties,
    );
  }
}
