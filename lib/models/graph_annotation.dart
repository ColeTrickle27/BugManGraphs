import 'dart:ui';

import 'graph_point.dart';

enum GraphAnnotationKind {
  marker,
  photo,
  text,
}

enum GraphMarkerCategory {
  insectFindings('Insect Findings'),
  structureFindings('Structure Findings'),
  moistureFindings('Moisture Findings'),
  structureDetails('Structure Details'),
  treatment('Treatment Markers'),
  review('Review');

  const GraphMarkerCategory(this.label);
  final String label;
}

enum GraphMarkerSymbol {
  termite,
  damage,
  mudTube,
  insect,
  rodent,
  moisture,
  water,
  leak,
  fungi,
  crack,
  penetration,
  access,
  vent,
  door,
  window,
  steps,
  hvac,
  utility,
  support,
  drillVertical,
  drillHorizontal,
  trench,
  injection,
  foam,
  treatment,
  bait,
  dust,
  exclusion,
  camera,
  note,
  alert,
  generic,
}

enum GraphMarkerType {
  termiteActivity('Termite Activity', 'AT', Color(0xFFE24A33)),
  termiteDamage('Termite Damage', 'TD', Color(0xFFD33A2C)),
  moisture('Moisture', 'M%', Color(0xFF168AAD)),
  standingWater('Standing Water', 'SW', Color(0xFF0077B6)),
  conduciveCondition('Conducive Condition', 'CC', Color(0xFFE0AD19)),
  treatmentArea('Treatment Area', 'TA', Color(0xFF245BDB)),
  baitStation('Bait Station', 'BS', Color(0xFF2E7D55)),
  crawlspaceIssue('Crawlspace Issue', 'CS', Color(0xFF7048D8)),
  plumbingLeak('Plumbing Leak', 'PL', Color(0xFF168AAD)),
  hvacCondensation('HVAC Condensation', 'HVAC', Color(0xFF5A9BD8)),
  insulationIssue('Insulation Issue', 'INS', Color(0xFFE5792A)),
  woodDecay('Wood Decay', 'WD', Color(0xFF8A5A2B)),
  accessPoint('Access Point', 'AP', Color(0xFF2E7D55)),
  entryPoint('Entry Point', 'EP', Color(0xFF111111)),
  rodentActivity('Rodent Activity', 'RA', Color(0xFF5B4B3A)),
  generalPestActivity('General Pest Activity', 'GP', Color(0xFF7A4E8A)),
  photoPoint('Photo Insert', 'PH', Color(0xFF2C6F9F)),
  notePoint('Note Point', 'N', Color(0xFF444444)),
  recommendationPoint('Recommendation', 'REC', Color(0xFF245BDB)),
  oldDamage('Old Damage', 'OD', Color(0xFF9A6B29)),
  damage('X - Damage', 'X', Color(0xFFD33A2C)),
  activeTermites('AT - Active Termites', 'AT', Color(0xFFE24A33)),
  oldTermiteActivity('OT - Old Termite Activity', 'OT', Color(0xFF9A6B29)),
  circle('Circle', 'C', Color(0xFF245BDB)),
  triangle('Triangle', 'T', Color(0xFF7048D8)),
  square('Square', 'S', Color(0xFF2E7D55)),
  camera('Camera', 'CAM', Color(0xFF2C6F9F)),
  woodFungi('Wood Destroying Fungi', 'WDF', Color(0xFF4D7F33)),
  oldHouseBorers('OHB - Old House Borers', 'OHB', Color(0xFF6E5332)),
  powderPostBeetles('PPB - Powder Post Beetles', 'PPB', Color(0xFF7A4E8A)),
  treatmentNote('Treatment Note', 'TXT', Color(0xFF222222)),
  mudTube('Mud Tube', 'MT', Color(0xFF8A5A2B)),
  carpenterAntEvidence('Carpenter Ant Evidence', 'CA', Color(0xFF5B4B3A)),
  carpenterBeeEvidence('Carpenter Bee Evidence', 'CB', Color(0xFFE0AD19)),
  roachActivity('Roach Activity', 'RO', Color(0xFF6E5332)),
  otherPestEvidence('Other Pest Evidence', 'PE', Color(0xFF7A4E8A)),
  rot('Wood Rot', 'ROT', Color(0xFF8A5A2B)),
  woodToGroundContact('Wood-to-Ground Contact', 'WG', Color(0xFFE5792A)),
  foundationCrack('Foundation Crack', 'FC', Color(0xFFD33A2C)),
  plumbingPenetration('Plumbing Penetration', 'PP', Color(0xFF168AAD)),
  utilityPenetration('Utility Penetration', 'UP', Color(0xFF5A6C7D)),
  crawlspaceAccess('Crawl Space Access', 'Access', Color(0xFF2E7D55)),
  vent('Vent', 'V', Color(0xFF5A9BD8)),
  expansionJoint('Expansion Joint', 'EJ', Color(0xFF56616E)),
  structuralConcern('Structural Concern', 'SC', Color(0xFFD33A2C)),
  pestEntryPoint('Pest Entry Point', 'EP', Color(0xFF111111)),
  moistureReading('Moisture Reading', 'M%', Color(0xFF168AAD)),
  highMoisture('High Moisture', 'HM', Color(0xFF0077B6)),
  activeLeak('Active Leak', 'AL', Color(0xFF0077B6)),
  condensation('Condensation', 'CON', Color(0xFF5A9BD8)),
  drainageConcern('Drainage Concern', 'DC', Color(0xFF168AAD)),
  vaporBarrierIssue('Vapor Barrier Issue', 'VB', Color(0xFF245BDB)),
  door('Door', 'DR', Color(0xFF435C70)),
  window('Window', 'WIN', Color(0xFF245B9E)),
  garageDoor('Garage Door', 'GD', Color(0xFF435C70)),
  steps('Steps', 'ST', Color(0xFF795548)),
  hvacUnit('HVAC', 'AC', Color(0xFF5A9BD8)),
  gasLine('Gas', 'GAS', Color(0xFFE0AD19)),
  waterLine('Water Pipe', 'WP', Color(0xFF168AAD)),
  bushPlant('Bush / Plant', 'Plant', Color(0xFF2E7D55)),
  wellOrCistern('Well or Cistern', 'WELL', Color(0xFF0077B6)),
  deckSupport('Deck Support', 'DS', Color(0xFF8A5A2B)),
  pier('Pier', 'PIER', Color(0xFF56616E)),
  foundationVent('Foundation Vent', 'FV', Color(0xFF5A9BD8)),
  verticalDrill('Vertical Drill', 'VD', Color(0xFF245BDB)),
  horizontalDrill('Horizontal Drill', 'HD', Color(0xFF245BDB)),
  trenchAndTreat('Trench and Treat', 'TT', Color(0xFFD1721E)),
  rodInjection('Rod Injection', 'RI', Color(0xFF7048D8)),
  foamApplication('Foam Application', 'FA', Color(0xFF168AAD)),
  liquidTreatmentZone('Liquid Treatment Zone', 'LT', Color(0xFF245BDB)),
  interiorBaitPlacement('Interior Bait Placement', 'IB', Color(0xFF2E7D55)),
  dustApplication('Dust Application', 'DA', Color(0xFF7A4E8A)),
  exclusionPoint('Exclusion Point', 'EX', Color(0xFF111111)),
  rodentBox('Rodent Box', 'RB', Color(0xFF355C46)),
  rodentTrap('Rodent Trap', 'RT', Color(0xFFB45F34));

  const GraphMarkerType(this.label, this.shortLabel, this.defaultColor);

  final String label;
  final String shortLabel;
  final Color defaultColor;
}

extension GraphMarkerTypeMetadata on GraphMarkerType {
  GraphMarkerCategory get category => switch (this) {
        GraphMarkerType.termiteActivity ||
        GraphMarkerType.activeTermites ||
        GraphMarkerType.termiteDamage ||
        GraphMarkerType.mudTube ||
        GraphMarkerType.carpenterAntEvidence ||
        GraphMarkerType.carpenterBeeEvidence ||
        GraphMarkerType.roachActivity ||
        GraphMarkerType.rodentActivity ||
        GraphMarkerType.generalPestActivity ||
        GraphMarkerType.otherPestEvidence ||
        GraphMarkerType.oldTermiteActivity ||
        GraphMarkerType.oldHouseBorers ||
        GraphMarkerType.powderPostBeetles =>
          GraphMarkerCategory.insectFindings,
        GraphMarkerType.woodDecay ||
        GraphMarkerType.rot ||
        GraphMarkerType.oldDamage ||
        GraphMarkerType.damage ||
        GraphMarkerType.woodToGroundContact ||
        GraphMarkerType.foundationCrack ||
        GraphMarkerType.plumbingPenetration ||
        GraphMarkerType.utilityPenetration ||
        GraphMarkerType.expansionJoint ||
        GraphMarkerType.structuralConcern ||
        GraphMarkerType.pestEntryPoint ||
        GraphMarkerType.entryPoint ||
        GraphMarkerType.conduciveCondition ||
        GraphMarkerType.crawlspaceIssue ||
        GraphMarkerType.insulationIssue =>
          GraphMarkerCategory.structureFindings,
        GraphMarkerType.moisture ||
        GraphMarkerType.moistureReading ||
        GraphMarkerType.highMoisture ||
        GraphMarkerType.standingWater ||
        GraphMarkerType.activeLeak ||
        GraphMarkerType.plumbingLeak ||
        GraphMarkerType.condensation ||
        GraphMarkerType.hvacCondensation ||
        GraphMarkerType.woodFungi ||
        GraphMarkerType.drainageConcern ||
        GraphMarkerType.vaporBarrierIssue =>
          GraphMarkerCategory.moistureFindings,
        GraphMarkerType.accessPoint ||
        GraphMarkerType.crawlspaceAccess ||
        GraphMarkerType.vent ||
        GraphMarkerType.door ||
        GraphMarkerType.window ||
        GraphMarkerType.garageDoor ||
        GraphMarkerType.steps ||
        GraphMarkerType.hvacUnit ||
        GraphMarkerType.bushPlant ||
        GraphMarkerType.gasLine ||
        GraphMarkerType.waterLine ||
        GraphMarkerType.wellOrCistern ||
        GraphMarkerType.deckSupport ||
        GraphMarkerType.pier ||
        GraphMarkerType.foundationVent =>
          GraphMarkerCategory.structureDetails,
        GraphMarkerType.treatmentArea ||
        GraphMarkerType.baitStation ||
        GraphMarkerType.verticalDrill ||
        GraphMarkerType.horizontalDrill ||
        GraphMarkerType.trenchAndTreat ||
        GraphMarkerType.rodInjection ||
        GraphMarkerType.foamApplication ||
        GraphMarkerType.liquidTreatmentZone ||
        GraphMarkerType.interiorBaitPlacement ||
        GraphMarkerType.dustApplication ||
        GraphMarkerType.exclusionPoint ||
        GraphMarkerType.rodentBox ||
        GraphMarkerType.rodentTrap ||
        GraphMarkerType.circle ||
        GraphMarkerType.triangle ||
        GraphMarkerType.square =>
          GraphMarkerCategory.treatment,
        GraphMarkerType.photoPoint ||
        GraphMarkerType.notePoint ||
        GraphMarkerType.recommendationPoint ||
        GraphMarkerType.camera ||
        GraphMarkerType.treatmentNote =>
          GraphMarkerCategory.review,
      };

  GraphMarkerSymbol get symbol => switch (this) {
        GraphMarkerType.termiteActivity ||
        GraphMarkerType.activeTermites ||
        GraphMarkerType.oldTermiteActivity =>
          GraphMarkerSymbol.termite,
        GraphMarkerType.termiteDamage ||
        GraphMarkerType.damage ||
        GraphMarkerType.oldDamage ||
        GraphMarkerType.woodDecay ||
        GraphMarkerType.rot ||
        GraphMarkerType.woodToGroundContact ||
        GraphMarkerType.vaporBarrierIssue =>
          GraphMarkerSymbol.damage,
        GraphMarkerType.mudTube => GraphMarkerSymbol.mudTube,
        GraphMarkerType.rodentActivity => GraphMarkerSymbol.rodent,
        GraphMarkerType.moisture ||
        GraphMarkerType.moistureReading ||
        GraphMarkerType.highMoisture ||
        GraphMarkerType.condensation ||
        GraphMarkerType.hvacCondensation ||
        GraphMarkerType.drainageConcern =>
          GraphMarkerSymbol.moisture,
        GraphMarkerType.standingWater => GraphMarkerSymbol.water,
        GraphMarkerType.activeLeak ||
        GraphMarkerType.plumbingLeak =>
          GraphMarkerSymbol.leak,
        GraphMarkerType.woodFungi ||
        GraphMarkerType.bushPlant =>
          GraphMarkerSymbol.fungi,
        GraphMarkerType.foundationCrack ||
        GraphMarkerType.expansionJoint ||
        GraphMarkerType.structuralConcern =>
          GraphMarkerSymbol.crack,
        GraphMarkerType.plumbingPenetration ||
        GraphMarkerType.utilityPenetration ||
        GraphMarkerType.pestEntryPoint ||
        GraphMarkerType.entryPoint =>
          GraphMarkerSymbol.penetration,
        GraphMarkerType.accessPoint => GraphMarkerSymbol.access,
        GraphMarkerType.crawlspaceAccess => GraphMarkerSymbol.utility,
        GraphMarkerType.vent ||
        GraphMarkerType.foundationVent =>
          GraphMarkerSymbol.vent,
        GraphMarkerType.door ||
        GraphMarkerType.garageDoor =>
          GraphMarkerSymbol.door,
        GraphMarkerType.window => GraphMarkerSymbol.window,
        GraphMarkerType.steps => GraphMarkerSymbol.steps,
        GraphMarkerType.hvacUnit => GraphMarkerSymbol.hvac,
        GraphMarkerType.gasLine ||
        GraphMarkerType.waterLine ||
        GraphMarkerType.wellOrCistern =>
          GraphMarkerSymbol.utility,
        GraphMarkerType.deckSupport ||
        GraphMarkerType.pier =>
          GraphMarkerSymbol.support,
        GraphMarkerType.verticalDrill => GraphMarkerSymbol.drillVertical,
        GraphMarkerType.horizontalDrill => GraphMarkerSymbol.drillHorizontal,
        GraphMarkerType.trenchAndTreat => GraphMarkerSymbol.trench,
        GraphMarkerType.rodInjection => GraphMarkerSymbol.injection,
        GraphMarkerType.foamApplication => GraphMarkerSymbol.foam,
        GraphMarkerType.treatmentArea ||
        GraphMarkerType.liquidTreatmentZone =>
          GraphMarkerSymbol.treatment,
        GraphMarkerType.baitStation ||
        GraphMarkerType.rodentBox ||
        GraphMarkerType.rodentTrap ||
        GraphMarkerType.interiorBaitPlacement =>
          GraphMarkerSymbol.bait,
        GraphMarkerType.dustApplication => GraphMarkerSymbol.dust,
        GraphMarkerType.exclusionPoint => GraphMarkerSymbol.exclusion,
        GraphMarkerType.camera ||
        GraphMarkerType.photoPoint =>
          GraphMarkerSymbol.camera,
        GraphMarkerType.notePoint ||
        GraphMarkerType.treatmentNote =>
          GraphMarkerSymbol.note,
        GraphMarkerType.recommendationPoint ||
        GraphMarkerType.conduciveCondition ||
        GraphMarkerType.crawlspaceIssue ||
        GraphMarkerType.insulationIssue =>
          GraphMarkerSymbol.alert,
        _ => GraphMarkerSymbol.insect,
      };

  /// Whether this legacy-compatible type may be placed from the cleaned UI.
  bool get availableForNewPlacement => !const <GraphMarkerType>{
        GraphMarkerType.carpenterAntEvidence,
        GraphMarkerType.carpenterBeeEvidence,
        GraphMarkerType.roachActivity,
        GraphMarkerType.otherPestEvidence,
        GraphMarkerType.conduciveCondition,
        GraphMarkerType.crawlspaceIssue,
        GraphMarkerType.woodDecay,
        GraphMarkerType.entryPoint,
        GraphMarkerType.moistureReading,
        GraphMarkerType.generalPestActivity,
        GraphMarkerType.termiteDamage,
        GraphMarkerType.activeTermites,
        GraphMarkerType.oldTermiteActivity,
        GraphMarkerType.oldDamage,
        GraphMarkerType.damage,
        GraphMarkerType.foundationCrack,
        GraphMarkerType.plumbingPenetration,
        GraphMarkerType.utilityPenetration,
        GraphMarkerType.expansionJoint,
        GraphMarkerType.pestEntryPoint,
        GraphMarkerType.highMoisture,
        GraphMarkerType.activeLeak,
        GraphMarkerType.condensation,
        GraphMarkerType.drainageConcern,
        GraphMarkerType.accessPoint,
        GraphMarkerType.vent,
        GraphMarkerType.door,
        GraphMarkerType.window,
        GraphMarkerType.garageDoor,
        GraphMarkerType.deckSupport,
        GraphMarkerType.foundationVent,
        GraphMarkerType.circle,
        GraphMarkerType.triangle,
        GraphMarkerType.square,
        GraphMarkerType.foamApplication,
        GraphMarkerType.liquidTreatmentZone,
        GraphMarkerType.interiorBaitPlacement,
        GraphMarkerType.dustApplication,
        GraphMarkerType.exclusionPoint,
        GraphMarkerType.photoPoint,
        GraphMarkerType.camera,
        GraphMarkerType.notePoint,
      }.contains(this);
}

class GraphAnnotation {
  const GraphAnnotation({
    this.id = '',
    required this.kind,
    required this.point,
    required this.label,
    this.markerType = GraphMarkerType.damage,
    this.color,
    this.size = 1,
    this.rotationDegrees = 0,
    this.note = '',
    this.fontSize = 16,
    this.bold = false,
    this.italic = false,
    this.textColor = const Color(0xFF1C2B22),
    this.backgroundColor = const Color(0xFFFFF2B8),
    this.borderColor = const Color(0xFFC7A93C),
    this.extraProperties = const <String, Object?>{},
    this.attachmentIds = const <String>[],
  });

  final String id;
  final GraphAnnotationKind kind;
  final GraphPoint point;
  final String label;
  final GraphMarkerType markerType;
  final Color? color;
  final double size;
  final double rotationDegrees;
  final String note;
  final double fontSize;
  final bool bold;
  final bool italic;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;
  final Map<String, Object?> extraProperties;
  final List<String> attachmentIds;

  GraphAnnotation copyWith({
    String? id,
    GraphAnnotationKind? kind,
    GraphPoint? point,
    String? label,
    GraphMarkerType? markerType,
    Color? color,
    bool clearColor = false,
    double? size,
    double? rotationDegrees,
    String? note,
    double? fontSize,
    bool? bold,
    bool? italic,
    Color? textColor,
    Color? backgroundColor,
    Color? borderColor,
    Map<String, Object?>? extraProperties,
    List<String>? attachmentIds,
  }) {
    return GraphAnnotation(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      point: point ?? this.point,
      label: label ?? this.label,
      markerType: markerType ?? this.markerType,
      color: clearColor ? null : color ?? this.color,
      size: size ?? this.size,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      note: note ?? this.note,
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
      extraProperties: extraProperties ?? this.extraProperties,
      attachmentIds: attachmentIds ?? this.attachmentIds,
    );
  }
}
