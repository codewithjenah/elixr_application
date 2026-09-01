import 'package:intl/intl.dart';

/// Formats an instant for user-facing labels in the app's long, readable form.
///
/// Stored timestamps remain UTC/ISO; only presentation is converted to the
/// machine's local time zone here.
String formatElixrDateTime(DateTime value) {
  return DateFormat('MMM d, yyyy h:mm a', 'en_US').format(value.toLocal());
}

/// Formats a local date for user-facing labels without exposing numeric dates.
String formatElixrDate(DateTime value) {
  return DateFormat('MMM d, yyyy', 'en_US').format(value.toLocal());
}

/// Formats a local time with a 12-hour clock and an AM/PM marker.
String formatElixrTime(DateTime value) {
  return DateFormat('h:mm a', 'en_US').format(value.toLocal());
}
