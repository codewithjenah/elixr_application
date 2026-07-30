/// Normalization, validation, composition, and legacy parsing for user names.
class UserNameParts {
  const UserNameParts({
    required this.firstName,
    this.middleName,
    required this.lastName,
  });

  final String firstName;
  final String? middleName;
  final String lastName;

  String get fullName => composeUserFullName(
    firstName: firstName,
    middleName: middleName,
    lastName: lastName,
  );
}

const int userFullNameMaxLength = 80;

String normalizeNamePart(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

String? normalizeOptionalNamePart(String value) {
  final normalized = normalizeNamePart(value);
  return normalized.isEmpty ? null : normalized;
}

String composeUserFullName({
  required String firstName,
  String? middleName,
  required String lastName,
}) {
  final parts = <String>[firstName];
  final middle = middleName?.trim();
  if (middle != null && middle.isNotEmpty) {
    parts.add(middle);
  }
  if (lastName.isNotEmpty) {
    parts.add(lastName);
  }
  return parts.join(' ');
}

UserNameParts parseLegacyFullName(String fullName) {
  final normalized = normalizeNamePart(fullName);
  if (normalized.isEmpty) {
    return const UserNameParts(firstName: '', lastName: '');
  }

  final tokens = normalized.split(' ');
  if (tokens.length == 1) {
    return UserNameParts(firstName: tokens.first, lastName: '');
  }
  if (tokens.length == 2) {
    return UserNameParts(firstName: tokens[0], lastName: tokens[1]);
  }

  return UserNameParts(
    firstName: tokens.first,
    middleName: tokens.sublist(1, tokens.length - 1).join(' '),
    lastName: tokens.last,
  );
}

UserNameParts normalizeUserNameParts({
  required String firstName,
  String? middleName,
  required String lastName,
}) {
  return UserNameParts(
    firstName: normalizeNamePart(firstName),
    middleName: middleName == null
        ? null
        : normalizeOptionalNamePart(middleName),
    lastName: normalizeNamePart(lastName),
  );
}

/// Returns a user-facing validation error, or null when valid.
String? validateUserNameParts({
  required String firstName,
  String? middleName,
  required String lastName,
}) {
  final normalized = normalizeUserNameParts(
    firstName: firstName,
    middleName: middleName,
    lastName: lastName,
  );

  if (normalized.firstName.isEmpty) {
    return 'First name is required.';
  }
  if (normalized.lastName.isEmpty) {
    return 'Last name is required.';
  }

  final composed = normalized.fullName;
  if (composed.isEmpty) {
    return 'First name is required.';
  }
  if (composed.length > userFullNameMaxLength) {
    return 'The complete name must be 80 characters or fewer.';
  }

  return null;
}
