import 'dart:io';
import 'package:bugman_graphs/services/history_timestamp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timestamps sort by instant, including DST repeats and explicit offsets',
      () {
    expect(
        compareHistoryTimestamps(
            '2026-11-01T01:30:00-05:00', '2026-11-01T01:45:00-04:00'),
        lessThan(0));
    expect(
        compareHistoryTimestamps(
            '2026-01-01T01:00:00+02:00', '2025-12-31T23:00:00Z'),
        0);
    expect(
        compareHistoryTimestamps('', '2026-01-01T00:00:00Z'), greaterThan(0));
    expect(compareHistoryTimestamps('invalid', ''), 0);
  });
  test('missing, ambiguous and impossible values have no fabricated date', () {
    for (final value in [
      '',
      'invalid',
      '2026-02-30T00:00:00Z',
      '2026-13-01T00:00:00Z',
      '2026-01-01T24:00:00Z',
      '2026-01-01T00:00:00+24:00',
      '2026-11-01T01:30:00'
    ]) {
      expect(parseHistoryTimestamp(value), isNull, reason: value);
    }
    expect(parseHistoryTimestamp('2024-02-29T00:00:00.123456Z'),
        DateTime.utc(2024, 2, 29, 0, 0, 0, 123, 456));
  });
  testWidgets(
      'local display has a year, readable time, offset and invalid fallback',
      (t) async {
    late BuildContext context;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    expect(historyDateLabel(context, 'invalid'), 'Date unavailable');
    final label = historyDateLabel(context, '2026-11-01T06:30:00Z');
    expect(label, contains('2026'));
    expect(label, contains('UTC'));
    if (Platform.environment['TZ'] == 'America/New_York') {
      expect(label, contains('1:30'));
      expect(label, contains('UTC-05:00'));
      expect(historyDateLabel(context, '2026-11-01T05:30:00Z'),
          contains('UTC-04:00'));
      expect(
          historyDateLabel(context, '2026-03-08T07:30:00Z'), contains('3:30'));
      expect(
          historyDateLabel(context, '2026-03-08T06:30:00Z'), contains('1:30'));
    }
  });
}
