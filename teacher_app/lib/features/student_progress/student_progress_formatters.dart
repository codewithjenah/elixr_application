import 'package:flutter/material.dart';

String formatPracticeDuration(int seconds) {
  if (seconds <= 0) return '0 min';
  if (seconds < 60) return '< 1 min';
  final minutes = seconds ~/ 60;
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours == 0) return '$minutes min';
  return remainingMinutes == 0
      ? '$hours hr'
      : '$hours hr $remainingMinutes min';
}

String formatSessionDate(BuildContext context, String? raw) {
  final date = raw == null ? null : DateTime.tryParse(raw);
  if (date == null) return 'Date unavailable';
  final local = date.toLocal();
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(local)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}
