import 'dart:ui';

import '../models/wall_segment.dart';

/// Presentation-only conversion. Stored points and calibration stay canonical.
class DrawingScale {
  const DrawingScale({this.feetPerGridUnit = 1}) : assert(feetPerGridUnit > 0);

  final double feetPerGridUnit;
  static const double displayedMinorSpacing = WallSegment.pixelsPerFoot;
  static const int minorUnitsPerMajor = 5;

  double displayedGridUnitsForFeet(double feet) => feet / feetPerGridUnit;
  double feetForDisplayedGridUnits(double units) => units * feetPerGridUnit;
  double get canonicalGridSpacing =>
      feetForDisplayedGridUnits(1) * WallSegment.pixelsPerFoot;
  double get presentationFactor => 1 / feetPerGridUnit;
  Offset toDisplay(Offset canonical) => canonical * presentationFactor;
  Offset toCanonical(Offset displayed) => displayed / presentationFactor;
}
