import 'package:flutter/material.dart';

/// Server timestamps include an offset; ambiguous or malformed dates stay unknown.
DateTime? parseHistoryTimestamp(String raw) {
  final match = RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$')
      .firstMatch(raw);
  if (match == null) return null;
  final values = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final date = DateTime.utc(values[0], values[1], values[2]);
  if (date.year != values[0] ||
      date.month != values[1] ||
      date.day != values[2] ||
      values[3] > 23 ||
      values[4] > 59 ||
      values[5] > 59) {
    return null;
  }
  final zone = match.group(7)!;
  if (zone != 'Z' &&
      (int.parse(zone.substring(1, 3)) > 23 ||
          int.parse(zone.substring(4, 6)) > 59)) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}

/// Newest first, using instants rather than ISO strings with differing offsets.
/// Missing/invalid timestamps follow known ones. Callers retain stable key ties.
int compareHistoryTimestamps(String a, String b) {
  final first = parseHistoryTimestamp(a), second = parseHistoryTimestamp(b);
  if (first == null) return second == null ? 0 : 1;
  if (second == null) return -1;
  return second.compareTo(first);
}

String historyDateLabel(BuildContext context, String raw) {
  final instant = parseHistoryTimestamp(raw);
  if (instant == null) return 'Date unavailable';
  final local = instant.toLocal();
  final material = MaterialLocalizations.of(context);
  final minutes = local.timeZoneOffset.inMinutes;
  final offset =
      '${minutes < 0 ? '-' : '+'}${(minutes.abs() ~/ 60).toString().padLeft(2, '0')}:${(minutes.abs() % 60).toString().padLeft(2, '0')}';
  return '${material.formatShortDate(local)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))} (UTC$offset)';
}
