final RegExp _authEmailPattern = RegExp(
  r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
);

String? validateAuthEmail(String value) {
  final email = value.trim();
  if (email.isEmpty) return 'Email address is required.';
  if (!_authEmailPattern.hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

bool passwordHasMinimumLength(String value) => value.length >= 8;
bool passwordHasLetter(String value) => RegExp(r'[A-Za-z]').hasMatch(value);
bool passwordHasNumber(String value) => RegExp(r'[0-9]').hasMatch(value);

String? validateRegistrationPassword(String value) {
  if (value.isEmpty) return 'Password is required.';
  if (!passwordHasMinimumLength(value) ||
      !passwordHasLetter(value) ||
      !passwordHasNumber(value)) {
    return 'Use 8+ characters with at least one letter and one number.';
  }
  return null;
}

String? validatePasswordConfirmation(String password, String confirmation) {
  if (confirmation.isEmpty) return 'Confirm your password.';
  if (password != confirmation) return 'Passwords do not match.';
  return null;
}
