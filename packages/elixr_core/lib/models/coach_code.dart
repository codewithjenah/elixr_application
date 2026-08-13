import 'dart:math';

/// Human-readable high-entropy coach codes for Teacher discovery.
///
/// Format example: `7KPM-XR4D-Q2WT`. The stored lookup key is the same value
/// with hyphens removed. The alphabet omits ambiguous characters (`I`, `O`,
/// `0`, `1`).
abstract final class CoachCode {
  static const lifetime = Duration(days: 7);
  static const normalizedLength = 12;
  static const groupSize = 4;
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final _normalizedPattern = RegExp(r'^[A-HJ-NP-Z2-9]{12}$');

  /// Uppercases and strips hyphens/whitespace. Does not validate membership.
  static String normalize(String input) {
    return input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static bool isNormalized(String value) => _normalizedPattern.hasMatch(value);

  /// Returns a normalized code, or null when [input] is not a valid coach code.
  static String? tryNormalize(String input) {
    final normalized = normalize(input);
    return isNormalized(normalized) ? normalized : null;
  }

  static String format(String normalized) {
    final code = normalize(normalized);
    if (!isNormalized(code)) {
      throw ArgumentError.value(normalized, 'normalized', 'Invalid coach code');
    }
    final buffer = StringBuffer();
    for (var i = 0; i < code.length; i += groupSize) {
      if (i > 0) buffer.write('-');
      buffer.write(code.substring(i, i + groupSize));
    }
    return buffer.toString();
  }

  /// Cryptographically secure 12-character code, already normalized.
  static String generateNormalized({Random? random}) {
    final rng = random ?? Random.secure();
    final chars = List<String>.generate(
      normalizedLength,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    );
    return chars.join();
  }

  static String generateDisplay({Random? random}) {
    return format(generateNormalized(random: random));
  }
}
