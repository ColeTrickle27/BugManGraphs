/// Screen-only label sizing; exports use the default unscaled presentation.
class LabelPresentation {
  const LabelPresentation(
      {this.zoom = 1, this.textScale = 1, this.bounded = false});
  final double zoom;
  final double textScale;
  final bool bounded;
  double fontSize(double base) {
    if (!bounded) return base * textScale;
    final safeZoom = zoom.clamp(0.001, 100.0);
    return (base * textScale * safeZoom).clamp(12.0, 26.0) / safeZoom;
  }
}
