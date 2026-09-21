import 'dart:ui';

import 'graph_annotation.dart';

const utilityMarkerTypes = <GraphMarkerType>{
  GraphMarkerType.hvacUnit,
  GraphMarkerType.pier,
  GraphMarkerType.steps,
  GraphMarkerType.crawlspaceAccess,
  GraphMarkerType.gasLine,
  GraphMarkerType.waterLine,
  GraphMarkerType.bushPlant,
};

final inspectionMarkerTypes = <GraphMarkerType>[
  GraphMarkerType.moisture,
  GraphMarkerType.termiteActivity,
  ...GraphMarkerType.values.where(
    (marker) =>
        marker.availableForNewPlacement &&
        marker != GraphMarkerType.moisture &&
        marker != GraphMarkerType.termiteActivity &&
        marker != GraphMarkerType.moistureReading &&
        marker != GraphMarkerType.generalPestActivity &&
        marker.category != GraphMarkerCategory.treatment &&
        marker.category != GraphMarkerCategory.review &&
        !utilityMarkerTypes.contains(marker),
  ),
];

final treatmentMarkerTypes = <GraphMarkerType>[
  GraphMarkerType.treatmentArea,
  ...GraphMarkerType.values.where(
    (marker) =>
        marker.availableForNewPlacement &&
        marker.category == GraphMarkerCategory.treatment &&
        marker != GraphMarkerType.treatmentArea,
  ),
  GraphMarkerType.treatmentNote,
];

bool isTreatmentMarker(GraphMarkerType marker) =>
    treatmentMarkerTypes.contains(marker);

bool isInspectionMarker(GraphMarkerType marker) =>
    inspectionMarkerTypes.contains(marker);

Color moistureMarkerColor(double percentage) {
  if (percentage < 10) return const Color(0xFFE0AD19);
  if (percentage <= 15) return const Color(0xFF2E7D55);
  if (percentage <= 20) return const Color(0xFFE0AD19);
  return const Color(0xFFCC2000);
}
