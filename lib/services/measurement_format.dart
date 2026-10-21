class MeasurementFormat {
  const MeasurementFormat._();

  static String linearFeet(num value, {bool includeUnit = true}) =>
      '${value.round()}${includeUnit ? ' lf' : ''}';

  static String squareFeet(num value, {bool includeUnit = true}) =>
      '${value.round()}${includeUnit ? ' sf' : ''}';

  static String acres(num value, {bool includeUnit = true}) =>
      '${value.toStringAsFixed(2)}${includeUnit ? ' ac' : ''}';
}
