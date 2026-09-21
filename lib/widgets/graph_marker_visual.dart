import 'package:flutter/material.dart';

import '../models/graph_annotation.dart';

/// The single icon mapping used by both toolbar controls and canvas/export
/// painting, keeping every finding visually consistent in every surface.
IconData iconForGraphMarker(GraphMarkerType marker) => switch (marker.symbol) {
      GraphMarkerSymbol.termite => Icons.pest_control_outlined,
      GraphMarkerSymbol.damage => Icons.handyman_outlined,
      GraphMarkerSymbol.mudTube => Icons.route_outlined,
      GraphMarkerSymbol.insect => Icons.bug_report_outlined,
      GraphMarkerSymbol.rodent => Icons.pets_outlined,
      GraphMarkerSymbol.moisture => Icons.water_drop_outlined,
      GraphMarkerSymbol.water => Icons.water_outlined,
      GraphMarkerSymbol.leak => Icons.plumbing_outlined,
      GraphMarkerSymbol.fungi => marker == GraphMarkerType.bushPlant
          ? Icons.yard_outlined
          : Icons.grass_outlined,
      GraphMarkerSymbol.crack => Icons.warning_amber_outlined,
      GraphMarkerSymbol.penetration => Icons.adjust_outlined,
      GraphMarkerSymbol.access => Icons.meeting_room_outlined,
      GraphMarkerSymbol.vent => Icons.air_outlined,
      GraphMarkerSymbol.door => Icons.door_front_door_outlined,
      GraphMarkerSymbol.window => Icons.window_outlined,
      GraphMarkerSymbol.steps => Icons.stairs_rounded,
      GraphMarkerSymbol.hvac => Icons.ac_unit_outlined,
      GraphMarkerSymbol.utility => switch (marker) {
          GraphMarkerType.crawlspaceAccess => Icons.door_sliding_outlined,
          GraphMarkerType.gasLine => Icons.local_fire_department_outlined,
          GraphMarkerType.waterLine => Icons.plumbing_outlined,
          _ => Icons.cable_outlined,
        },
      GraphMarkerSymbol.support => Icons.foundation_outlined,
      GraphMarkerSymbol.drillVertical => Icons.south_outlined,
      GraphMarkerSymbol.drillHorizontal => Icons.east_outlined,
      GraphMarkerSymbol.trench => Icons.linear_scale_outlined,
      GraphMarkerSymbol.injection => Icons.colorize_outlined,
      GraphMarkerSymbol.foam => Icons.bubble_chart_outlined,
      GraphMarkerSymbol.treatment => Icons.science_outlined,
      GraphMarkerSymbol.bait => switch (marker) {
          GraphMarkerType.rodentBox => Icons.inventory_2_outlined,
          GraphMarkerType.rodentTrap => Icons.gps_fixed_outlined,
          _ => Icons.location_on_outlined,
        },
      GraphMarkerSymbol.dust => Icons.blur_on_outlined,
      GraphMarkerSymbol.exclusion => Icons.block_outlined,
      GraphMarkerSymbol.camera => Icons.photo_camera_outlined,
      GraphMarkerSymbol.note => Icons.note_alt_outlined,
      GraphMarkerSymbol.alert => Icons.report_problem_outlined,
      GraphMarkerSymbol.generic => Icons.place_outlined,
    };

IconData? noticeIconForGraphAnnotation(GraphAnnotation annotation) {
  if (annotation.markerType == GraphMarkerType.moisture) {
    if (annotation.note.contains('Immediate Attention Needed')) {
      return Icons.dangerous_outlined;
    }
    if (annotation.note.contains('High Moisture')) {
      return Icons.warning_amber_rounded;
    }
  }

  return null;
}
